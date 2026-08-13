#!/usr/bin/env python3
"""Measure full-tensor mixed-precision RTL accuracy against PyTorch BF16."""

from __future__ import annotations

import csv
import argparse
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "reports/groot_normalization/results/actual_groot/action_head_trace"
THRESHOLD = 0.025


def words(path: Path) -> list[int]:
    return [int(value, 16) for value in path.read_text(encoding="ascii").split()]


def fp(word: int) -> float:
    return struct.unpack(">f", struct.pack(">I", word << 16))[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=("C10", "C11"), default="C10")
    args = parser.parse_args()
    variant = args.variant.upper()
    suffix = "mixed_precision_rtl" if variant == "C10" else "mixed_precision_c11_rtl"
    vectors = ROOT / f"reports/groot_normalization/results/{suffix}_vectors"
    results = ROOT / f"reports/groot_normalization/results/{suffix}_results"
    cases = list(csv.DictReader((vectors / "cases.csv").open(encoding="utf-8")))
    rows = []
    for case in cases:
        profile = case["profile_id"]
        actual_bits = words(results / f"{profile}_actual.hex")
        expected_bits = words(vectors / f"{profile}_pytorch_expected.hex")
        model_bits = words(vectors / f"{profile}_mixed_expected.hex")
        if len(actual_bits) != len(expected_bits):
            raise RuntimeError(f"length mismatch {profile}")
        actual = [fp(value) for value in actual_bits]
        expected = [fp(value) for value in expected_bits]
        errors = [abs(a - e) for a, e in zip(actual, expected)]
        worst = max(range(len(errors)), key=errors.__getitem__)
        row = {
            "profile_id": profile,
            "rows": int(case["rows"]),
            "hidden_size": int(case["hidden_size"]),
            "samples": len(errors),
            "rtl_vs_model_bit_mismatches": sum(a != b for a, b in zip(actual_bits, model_bits)),
            "rtl_vs_pytorch_bit_mismatches": sum(a != b for a, b in zip(actual_bits, expected_bits)),
            "bit_exact_rate": sum(a == b for a, b in zip(actual_bits, expected_bits)) / len(errors),
            "max_abs": max(errors),
            "mean_abs": sum(errors) / len(errors),
            "rmse": math.sqrt(sum(value * value for value in errors) / len(errors)),
            "nonfinite": sum(not math.isfinite(value) for value in actual),
            "worst_flat_index": worst,
            "worst_row": worst // int(case["hidden_size"]),
            "worst_column": worst % int(case["hidden_size"]),
            "worst_actual_bf16": f"{actual_bits[worst]:04x}",
            "worst_pytorch_bf16": f"{expected_bits[worst]:04x}",
            "threshold": THRESHOLD,
            "result": "PASS" if max(errors) <= THRESHOLD and all(math.isfinite(value) for value in actual) else "FAIL",
            "source_classification": case["source_classification"],
        }
        rows.append(row)
    with (results / "accuracy_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    summary = {
        "candidate": f"{variant}_FP32_BALANCED_NR2_FUSED",
        "scope": "all rows/elements in six captured tensors",
        "threshold": THRESHOLD,
        "profiles": rows,
        "total_samples": sum(row["samples"] for row in rows),
        "total_rtl_vs_model_bit_mismatches": sum(row["rtl_vs_model_bit_mismatches"] for row in rows),
        "total_rtl_vs_pytorch_bit_mismatches": sum(row["rtl_vs_pytorch_bit_mismatches"] for row in rows),
        "overall_max_abs": max(row["max_abs"] for row in rows),
        "passed_profiles": sum(row["result"] == "PASS" for row in rows),
        "overall_result": "PASS" if all(row["result"] == "PASS" for row in rows) else "FAIL",
    }
    (results / "accuracy_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"GROOT_MIXED_PRECISION_RTL_ACCURACY variant={variant} result={summary['overall_result']} profiles={summary['passed_profiles']}/6 samples={summary['total_samples']} max_abs={summary['overall_max_abs']}")
    return 0 if summary["overall_result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
