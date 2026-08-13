#!/usr/bin/env python3
"""Create first-row C10 mixed-precision RTL vectors for all GR00T profiles."""

from __future__ import annotations

import csv
import importlib.util
import json
import math
import os
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "reports/groot_normalization/results/actual_groot/action_head_trace"
VARIANT = os.environ.get("GROOT_MIXED_VARIANT", "C10").upper()
OUT = ROOT / "reports/groot_normalization/results" / ("mixed_precision_c11_rtl_vectors" if VARIANT == "C11" else "mixed_precision_rtl_vectors")


def load_model():
    path = ROOT / "tools/explore_groot_mixed_precision.py"
    spec = importlib.util.spec_from_file_location("mixed_precision_model", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load mixed precision model")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def fp32_bits(value: float) -> int:
    return struct.unpack(">I", struct.pack(">f", float(value)))[0]


def write_hex(path: Path, values) -> None:
    path.write_text("\n".join(f"{int(value):04x}" for value in values) + "\n", encoding="ascii")


def main() -> int:
    model = load_model()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    cases = []
    for profile, sample in manifest["samples"].items():
        hidden = int(sample["shape"][-1])
        rows = math.prod(sample["shape"][:-1])
        x_bits_all = model.read_hex(TRACE / sample["input_hex"]).reshape(rows, hidden)
        gamma_bits = model.read_hex(TRACE / sample["gamma_hex"])
        beta_bits = model.read_hex(TRACE / sample["beta_hex"])
        pytorch_bits = model.read_hex(TRACE / sample["output_hex"]).reshape(rows, hidden)
        x = model.bits_to_float(x_bits_all)
        gamma = model.bits_to_float(gamma_bits)
        beta = model.bits_to_float(beta_bits)
        epsilon = 1.0e-6 if profile == "action_dit_norm_out" else 1.0e-5
        if VARIANT == "C11":
            total, sumsq = model.reduce_fp32_interleaved4(x)
        else:
            total, sumsq = model.reduce_fp32_balanced(x)
        mean, inverse = model.scalar_fp32(total, sumsq, hidden, epsilon, "FP32_NR2")
        mixed_bits = model.apply_fp32(x, gamma, beta, mean, inverse)
        for suffix, values in (("x", x_bits_all.reshape(-1)), ("gamma", gamma_bits), ("beta", beta_bits), ("mixed_expected", mixed_bits.reshape(-1)), ("pytorch_expected", pytorch_bits.reshape(-1))):
            write_hex(OUT / f"{profile}_{suffix}.hex", values)
        (OUT / f"{profile}_mean_fp32.hex").write_text("\n".join(f"{int(value):08x}" for value in mean.view(model.np.uint32)) + "\n", encoding="ascii")
        (OUT / f"{profile}_inv_std_fp32.hex").write_text("\n".join(f"{int(value):08x}" for value in inverse.view(model.np.uint32)) + "\n", encoding="ascii")
        cases.append({
            "profile_id": profile,
            "rows": rows,
            "hidden_size": hidden,
            "vectors_per_bank": hidden // 64,
            "inv_hidden_fp32": f"{fp32_bits(1.0 / hidden):08x}",
            "epsilon_fp32": f"{fp32_bits(epsilon):08x}",
            "first_mean_fp32": f"{int(mean.view(model.np.uint32)[0]):08x}",
            "first_inv_std_fp32": f"{int(inverse.view(model.np.uint32)[0]):08x}",
            "source_classification": manifest["classification"],
        })
    with (OUT / "cases.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(cases[0]))
        writer.writeheader();writer.writerows(cases)
    print(f"GROOT_MIXED_PRECISION_RTL_VECTORS PASS variant={VARIANT} cases={len(cases)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
