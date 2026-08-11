#!/usr/bin/env python3
"""Evaluate LUT/NR reciprocal-square-root candidates for GR00T normalization."""

from __future__ import annotations

import argparse
import csv
import math
import random
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
RESULT_DIR = ROOT / "reports" / "groot_normalization" / "results"
LUT_ENTRIES = 256
SEED = 20260811


def fp32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", float(value)))[0]


def fp16(value: float) -> float:
    try:
        return struct.unpack("<e", struct.pack("<e", float(value)))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


def bf16(value: float) -> float:
    bits = struct.unpack("<I", struct.pack("<f", fp32(value)))[0]
    exponent = bits & 0x7F800000
    if exponent == 0x7F800000:
        return struct.unpack("<f", struct.pack("<I", bits & 0xFFFF0000))[0]
    rounded = bits + 0x7FFF + ((bits >> 16) & 1)
    return struct.unpack("<f", struct.pack("<I", rounded & 0xFFFF0000))[0]


QUANTIZERS: Dict[str, Callable[[float], float]] = {"FP16": fp16, "BF16": bf16}


def qmul(a: float, b: float, q: Callable[[float], float]) -> float:
    return q(q(a) * q(b))


def qsub(a: float, b: float, q: Callable[[float], float]) -> float:
    return q(q(a) - q(b))


def lut_seed(value: float, q: Callable[[float], float], entries: int = LUT_ENTRIES) -> float:
    if math.isnan(value) or value < 0.0:
        return math.nan
    if value == 0.0:
        return math.inf
    if math.isinf(value):
        return 0.0
    mantissa, exponent = math.frexp(value)  # value = mantissa * 2**exponent, m in [0.5,1)
    mantissa *= 2.0
    exponent -= 1
    if exponent & 1:
        mantissa *= 2.0
        exponent -= 1
    # After making exponent even, mantissa is in [1,4). Use bin midpoint ROM values.
    index = min(entries - 1, max(0, int((mantissa - 1.0) * entries / 3.0)))
    midpoint = 1.0 + (index + 0.5) * 3.0 / entries
    rom_value = q(1.0 / math.sqrt(midpoint))
    return q(math.ldexp(rom_value, -(exponent // 2)))


def rsqrt_candidate(value: float, dtype: str, iterations: int, wide_internal: bool = False) -> float:
    q = QUANTIZERS[dtype]
    x = q(value)
    y = lut_seed(x, q)
    if not math.isfinite(y) or not math.isfinite(x):
        return y
    for _ in range(iterations):
        if wide_internal:
            y = fp32(y * fp32(1.5 - fp32(0.5 * fp32(x * fp32(y * y)))))
        else:
            yy = qmul(y, y, q)
            xyy = qmul(x, yy, q)
            correction = qsub(1.5, qmul(0.5, xyy, q), q)
            y = qmul(y, correction, q)
    return q(y)


def scalar_inputs() -> List[Tuple[str, float]]:
    rng = random.Random(SEED)
    values: List[Tuple[str, float]] = [
        ("epsilon_ln", 1.0e-5),
        ("epsilon_rms", 1.0e-6),
        ("tiny", 2.0**-20),
        ("small", 2.0**-10),
        ("one", 1.0),
        ("large", 2.0**15),
        ("max_fp16", 65504.0),
    ]
    for _ in range(20000):
        exponent = rng.uniform(-19.0, 15.0)
        values.append(("random_log_uniform", 2.0**exponent))
    return values


def error_metrics(pairs: Iterable[Tuple[float, float]]) -> Dict[str, float | int]:
    abs_errors: List[float] = []
    rel_errors: List[float] = []
    nonfinite = 0
    for actual, expected in pairs:
        if not math.isfinite(actual) or not math.isfinite(expected):
            nonfinite += 1
            continue
        error = abs(actual - expected)
        abs_errors.append(error)
        rel_errors.append(error / max(abs(expected), 1.0e-30))
    return {
        "samples": len(abs_errors),
        "nonfinite": nonfinite,
        "max_abs": max(abs_errors, default=0.0),
        "mean_abs": sum(abs_errors) / max(1, len(abs_errors)),
        "max_rel": max(rel_errors, default=0.0),
        "mean_rel": sum(rel_errors) / max(1, len(rel_errors)),
        "rmse": math.sqrt(sum(value * value for value in abs_errors) / max(1, len(abs_errors))),
    }


def evaluate_scalar() -> List[Dict]:
    rows: List[Dict] = []
    values = scalar_inputs()
    for dtype, q in QUANTIZERS.items():
        candidates = (
            (0, False, "LUT256"),
            (1, False, "LUT256_NR1_NARROW"),
            (2, False, "LUT256_NR2_NARROW"),
            (1, True, "LUT256_NR1_WIDE"),
            (2, True, "LUT256_NR2_WIDE"),
        )
        for iterations, wide_internal, candidate in candidates:
            pairs = []
            for _, value in values:
                quantized = q(value)
                expected = 1.0 / math.sqrt(quantized)
                pairs.append((rsqrt_candidate(value, dtype, iterations, wide_internal), expected))
            metrics = error_metrics(pairs)
            threshold = 0.01 if iterations == 0 else (0.002 if dtype == "FP16" else 0.01)
            rows.append(
                {
                    "dtype": dtype,
                    "candidate": candidate,
                    "lut_entries": LUT_ENTRIES,
                    "nr_iterations": iterations,
                    "wide_internal": wide_internal,
                    **{key: round(value, 10) if isinstance(value, float) else value for key, value in metrics.items()},
                    "max_rel_threshold": threshold,
                    "result": "PASS" if metrics["nonfinite"] == 0 and metrics["max_rel"] <= threshold else "FAIL",
                }
            )
    return rows


@dataclass(frozen=True)
class NormCase:
    name: str
    norm: str
    values: Sequence[float]
    epsilon: float


def normalization_cases() -> List[NormCase]:
    rng = random.Random(SEED + 1)
    random_mixed = [rng.uniform(-3.0, 3.0) for _ in range(2048)]
    positive_rms = [rng.uniform(-1.0, 1.0) for _ in range(2048)]
    return [
        NormCase("all_zero", "LayerNorm", [0.0] * 2048, 1.0e-5),
        NormCase("constant", "LayerNorm", [1.25] * 2048, 1.0e-5),
        NormCase("mixed_random", "LayerNorm", random_mixed, 1.0e-5),
        NormCase("small_variance", "LayerNorm", [1.0 + (i % 7 - 3) * 1.0e-4 for i in range(2048)], 1.0e-5),
        NormCase("large_offset_small_variance", "LayerNorm", [1000.0 + (i % 7 - 3) * 0.05 for i in range(1536)], 1.0e-5),
        NormCase("all_zero", "RMSNorm", [0.0] * 2048, 1.0e-6),
        NormCase("constant", "RMSNorm", [1.25] * 2048, 1.0e-6),
        NormCase("mixed_random", "RMSNorm", positive_rms, 1.0e-6),
        NormCase("epsilon_near", "RMSNorm", [(i % 5 - 2) * 1.0e-4 for i in range(64)], 1.0e-6),
    ]


def normalize(
    case: NormCase, dtype: str, iterations: int | None, wide_internal: bool = False
) -> List[float]:
    q = QUANTIZERS[dtype]
    values = [q(value) for value in case.values]
    mean = sum(values) / len(values) if case.norm == "LayerNorm" else 0.0
    centered = [value - mean for value in values]
    statistic_values = centered if case.norm == "LayerNorm" else values
    variance = sum(value * value for value in statistic_values) / len(values)
    argument = variance + case.epsilon
    inv = (
        1.0 / math.sqrt(argument)
        if iterations is None
        else rsqrt_candidate(argument, dtype, iterations, wide_internal)
    )
    return [value * inv for value in centered if True]


def evaluate_normalization() -> List[Dict]:
    rows: List[Dict] = []
    for dtype in QUANTIZERS:
        for case in normalization_cases():
            golden = normalize(case, dtype, None)
            candidates = (
                (0, False, "LUT256"),
                (1, False, "LUT256_NR1_NARROW"),
                (2, False, "LUT256_NR2_NARROW"),
                (1, True, "LUT256_NR1_WIDE"),
                (2, True, "LUT256_NR2_WIDE"),
            )
            for iterations, wide_internal, candidate in candidates:
                actual = normalize(case, dtype, iterations, wide_internal)
                metrics = error_metrics(zip(actual, golden))
                rows.append(
                    {
                        "dtype": dtype,
                        "norm_type": case.norm,
                        "input_case": case.name,
                        "hidden_size": len(case.values),
                        "candidate": candidate,
                        "nr_iterations": iterations,
                        "wide_internal": wide_internal,
                        **{key: round(value, 10) if isinstance(value, float) else value for key, value in metrics.items()},
                        "max_abs_threshold": 0.025,
                        "result": "PASS" if metrics["nonfinite"] == 0 and metrics["max_abs"] <= 0.025 else "FAIL",
                    }
                )
    return rows


def write_csv(path: Path, rows: List[Dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def self_test() -> None:
    assert fp16(1.0) == 1.0
    assert bf16(1.0) == 1.0
    assert math.isinf(rsqrt_candidate(0.0, "FP16", 1))
    assert math.isnan(rsqrt_candidate(-1.0, "FP16", 1))
    for dtype in QUANTIZERS:
        exact = 1.0 / math.sqrt(2.0)
        lut_error = abs(rsqrt_candidate(2.0, dtype, 0) - exact)
        nr_error = abs(rsqrt_candidate(2.0, dtype, 1) - exact)
        assert nr_error <= lut_error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        print("RSQRT_CANDIDATE_SELF_TEST PASS")
        return
    scalar = evaluate_scalar()
    normalization = evaluate_normalization()
    write_csv(RESULT_DIR / "rsqrt_scalar_accuracy.csv", scalar)
    write_csv(RESULT_DIR / "rsqrt_normalization_accuracy.csv", normalization)
    print(
        f"WROTE scalar_rows={len(scalar)} normalization_rows={len(normalization)} "
        f"scalar_pass={sum(row['result'] == 'PASS' for row in scalar)} "
        f"normalization_pass={sum(row['result'] == 'PASS' for row in normalization)}"
    )


if __name__ == "__main__":
    main()
