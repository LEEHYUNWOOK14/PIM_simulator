#!/usr/bin/env python3
"""Measure CUDA BF16 LayerNorm latency for captured GR00T action-head shapes."""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from pathlib import Path

import torch
import torch.nn.functional as F


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "reports/groot_normalization/results/actual_groot/action_head_trace"
OUT = ROOT / "reports/groot_normalization/results/actual_groot/gpu_benchmark"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--warmup", type=int, default=100)
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--repeats", type=int, default=7)
    args = parser.parse_args()
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is required; do not label a CPU fallback as GPU measurement")
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    with (TRACE / "invocations.csv").open(encoding="utf-8") as stream:
        invocation_rows = list(csv.DictReader(stream))
    affine_by_profile = {}
    for row in invocation_rows:
        affine_by_profile.setdefault(row["profile_id"], row["elementwise_affine"].lower() == "true")
    rows = []
    raw = {}
    for profile, sample in manifest["samples"].items():
        payload = torch.load(TRACE / sample["sample_file"], map_location="cpu", weights_only=True)
        x = payload["input"].to(device="cuda", dtype=torch.bfloat16)
        elementwise_affine = affine_by_profile[profile]
        weight = payload["weight"].to(device="cuda", dtype=torch.bfloat16) if elementwise_affine else None
        bias = payload["bias"].to(device="cuda", dtype=torch.bfloat16) if elementwise_affine else None
        epsilon = float(payload["epsilon"])
        for _ in range(args.warmup):
            F.layer_norm(x, (x.shape[-1],), weight, bias, epsilon)
        torch.cuda.synchronize()
        samples_us = []
        for _ in range(args.repeats):
            start = torch.cuda.Event(enable_timing=True)
            end = torch.cuda.Event(enable_timing=True)
            start.record()
            for _ in range(args.iterations):
                F.layer_norm(x, (x.shape[-1],), weight, bias, epsilon)
            end.record()
            end.synchronize()
            samples_us.append(start.elapsed_time(end) * 1000.0 / args.iterations)
        rows_count = x.numel() // x.shape[-1]
        tensor_bytes = x.numel() * x.element_size()
        affine_bytes = ((weight.numel() + bias.numel()) * weight.element_size()) if elementwise_affine else 0
        logical_bytes = tensor_bytes * 2 + affine_bytes
        median_us = statistics.median(samples_us)
        count = int(manifest["profile_counts"][profile])
        rows.append(
            {
                "profile_id": profile,
                "shape": "x".join(str(value) for value in x.shape),
                "rows": rows_count,
                "hidden_size": x.shape[-1],
                "dtype": str(x.dtype).replace("torch.", ""),
                "elementwise_affine": elementwise_affine,
                "invocations": count,
                "warmup_iterations": args.warmup,
                "timed_iterations_per_repeat": args.iterations,
                "repeats": args.repeats,
                "latency_us_min": min(samples_us),
                "latency_us_median": median_us,
                "latency_us_max": max(samples_us),
                "logical_input_bytes": tensor_bytes,
                "logical_output_bytes": tensor_bytes,
                "affine_parameter_bytes_per_call": affine_bytes,
                "logical_bytes_per_call_with_affine": logical_bytes,
                "effective_logical_gbytes_per_s": logical_bytes / median_us / 1000.0,
                "projected_serial_latency_us": median_us * count,
                "evidence_class": "MEASURED_CUDA_KERNEL_SYNTHETIC_BOUNDARY_ACTIVATION",
            }
        )
        raw[profile] = samples_us
    with (OUT / "gpu_layernorm_latency.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "model": manifest["model"],
        "model_revision": manifest["model_revision"],
        "classification": manifest["classification"],
        "device": torch.cuda.get_device_name(0),
        "device_capability": list(torch.cuda.get_device_capability(0)),
        "torch_version": torch.__version__,
        "cuda_runtime": torch.version.cuda,
        "dtype": "bfloat16",
        "timing_method": "CUDA events around repeated torch.nn.functional.layer_norm calls; median of repeats",
        "synchronization": "end event synchronize after each repeat",
        "total_projected_serial_latency_us": sum(row["projected_serial_latency_us"] for row in rows),
        "total_invocations": sum(row["invocations"] for row in rows),
        "raw_repeat_latency_us": raw,
        "profiles": rows,
        "limitations": [
            "Normalization microbenchmark only; not end-to-end GR00T latency.",
            "Activation is from pretrained action-head execution with synthetic boundary input.",
            "Logical traffic is not an HBM transaction measurement; cache effects are included in measured latency.",
            "Projected total assumes serial invocation and multiplies representative profile medians by captured call counts.",
        ],
    }
    (OUT / "gpu_layernorm_latency.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(
        "GROOT_GPU_LAYERNORM_BENCHMARK PASS "
        f"device={summary['device'].replace(' ', '_')} profiles={len(rows)} "
        f"calls={summary['total_invocations']} projected_us={summary['total_projected_serial_latency_us']:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
