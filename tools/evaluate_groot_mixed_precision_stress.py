#!/usr/bin/env python3
"""Evaluate C10 against finite numerical stress rows and special-value policy."""

from __future__ import annotations

import csv
import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "tools/explore_groot_mixed_precision.py"
OUT = ROOT / "reports/groot_normalization/results/mixed_precision_exploration"
VECTORS = ROOT / "reports/groot_normalization/results/mixed_precision_stress_vectors"


def load_model():
    spec = importlib.util.spec_from_file_location("mixed_stress_model", MODEL)
    module = importlib.util.module_from_spec(spec);sys.modules[spec.name] = module;spec.loader.exec_module(module)
    return module


def main() -> int:
    m = load_model()
    VECTORS.mkdir(parents=True, exist_ok=True)
    finite = {
        "all_zero": np.zeros(64, dtype=np.float32),
        "constant_1p25": np.full(64, 1.25, dtype=np.float32),
        "small_variance": np.asarray([1.0 + ((i % 5) - 2) / 128.0 for i in range(64)], dtype=np.float32),
        "large_offset": np.asarray([1024.0 + ((i % 5) - 2) * 8.0 for i in range(64)], dtype=np.float32),
        "mixed_magnitude": np.asarray([(-1.0 if i & 1 else 1.0) * (2.0 ** ((i % 17) - 8)) for i in range(64)], dtype=np.float32),
        "subnormal_input": np.asarray([(-1.0 if i & 1 else 1.0) * (2.0 ** -133) for i in range(64)], dtype=np.float32),
    }
    rows = []
    rtl_x=[];rtl_actual=[];rtl_pytorch=[];rtl_mean=[];rtl_inv=[]
    for name, raw in finite.items():
        x = m.q(raw).reshape(1, 64)
        gamma = np.ones(64, dtype=np.float32);beta = np.zeros(64, dtype=np.float32)
        total, sumsq = m.reduce_fp32_balanced(x)
        mean, inverse = m.scalar_fp32(total, sumsq, 64, 1.0e-5, "FP32_NR2")
        actual = m.apply_fp32(x, gamma, beta, mean, inverse)
        canonical_mean = np.mean(x, axis=1, dtype=np.float32)
        canonical_var = np.mean(np.asarray((x - canonical_mean[:, None]) ** 2, dtype=np.float32), axis=1, dtype=np.float32)
        canonical_inv = np.asarray(np.float32(1.0) / np.sqrt(canonical_var + np.float32(1.0e-5)), dtype=np.float32)
        expected = m.apply_fp32(x, gamma, beta, canonical_mean, canonical_inv)
        metric = m.calculate_metrics(actual, expected)
        rows.append({"case": name, **metric, "variance_clamp_expected": name in ("all_zero", "constant_1p25", "subnormal_input"), "result": "PASS" if metric["max_abs"] <= 0.025 and metric["nonfinite"] == 0 else "FAIL"})
        rtl_x.extend(m.float_to_bits(x.reshape(-1)).tolist());rtl_actual.extend(actual.reshape(-1).tolist());rtl_pytorch.extend(expected.reshape(-1).tolist())
        rtl_mean.append(int(mean.view(np.uint32)[0]));rtl_inv.append(int(inverse.view(np.uint32)[0]))
    # Explicit policy rather than numerical comparison: any NaN/Inf in a
    # LayerNorm row propagates to canonical NaN outputs.
    policy = [
        {"case": "contains_nan", "input": "one qNaN", "expected_policy": "canonical NaN output row", "rtl_primitive_support": "fp32 add/mul canonicalize NaN"},
        {"case": "contains_pos_inf", "input": "one +Inf", "expected_policy": "canonical NaN output row", "rtl_primitive_support": "Inf-Inf and 0*Inf canonicalize NaN"},
        {"case": "contains_neg_inf", "input": "one -Inf", "expected_policy": "canonical NaN output row", "rtl_primitive_support": "Inf-Inf and 0*Inf canonicalize NaN"},
    ]
    for special,expected_mean in ((0x7FC0,0x7FC00000),(0x7F80,0x7F800000),(0xFF80,0xFF800000)):
        vector=[0]*64;vector[0]=special;rtl_x.extend(vector);rtl_actual.extend([0x7FC0]*64);rtl_pytorch.extend([0x7FC0]*64);rtl_mean.append(expected_mean);rtl_inv.append(0x7FC00000)
    def write16(name,values):
        (VECTORS/name).write_text("\n".join(f"{int(value):04x}" for value in values)+"\n",encoding="ascii")
    def write32(name,values):
        (VECTORS/name).write_text("\n".join(f"{int(value):08x}" for value in values)+"\n",encoding="ascii")
    write16("stress_x.hex",rtl_x);write16("stress_gamma.hex",[0x3F80]*64);write16("stress_beta.hex",[0]*64)
    write16("stress_mixed_expected.hex",rtl_actual);write16("stress_pytorch_expected.hex",rtl_pytorch)
    write32("stress_mean_fp32.hex",rtl_mean);write32("stress_inv_std_fp32.hex",rtl_inv)
    with (OUT / "mixed_precision_stress_accuracy.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    payload = {"candidate": "C10_FP32_BALANCED_NR2_FUSED", "finite_cases": rows, "special_value_policy": policy, "overall_finite_result": "PASS" if all(row["result"] == "PASS" for row in rows) else "FAIL"}
    (OUT / "mixed_precision_stress_accuracy.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"GROOT_MIXED_PRECISION_STRESS result={payload['overall_finite_result']} cases={len(rows)}")
    return 0 if payload["overall_finite_result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
