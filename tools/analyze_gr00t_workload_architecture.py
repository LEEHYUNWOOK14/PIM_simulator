#!/usr/bin/env python3
"""Audit the available GR00T normalization evidence and build a provisional DSE.

This intentionally keeps measured, derived, modeled, and assumed values separate.
It does not turn synthetic activation replay into a claim of full-model profiling.
"""
from __future__ import annotations

import csv
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization"
RESULTS = REPORT / "results"
OUT = RESULTS / "gr00t_workload_architecture"
OUT.mkdir(parents=True, exist_ok=True)


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(row, key, cast=float):
    return cast(float(row[key]))


def main():
    manifest = read_csv(REPORT / "gr00t_normalization_profile_manifest.csv")
    trace = read_csv(ROOT / "experiment/gr00t_placement/results/gr00t_scheduler_replay_base_trace.csv")
    synth = read_csv(RESULTS / "normalization_synthesis_metrics.csv")
    sky = read_csv(RESULTS / "normalization_sky130_metrics.csv")

    by_profile = defaultdict(list)
    for r in trace:
        by_profile[r["profile"]].append(r)
    characteristics = []
    for m in manifest:
        events = by_profile[m["profile_id"]]
        queues = [int(x["queue_cycles"]) for x in events]
        service = [int(x["service_cycles"]) for x in events]
        chars = {
            "profile_id": m["profile_id"], "norm_type": m["norm_type"],
            "rows": int(m["rows"]), "hidden_size": int(m["hidden_size"]),
            "shape": m["shape"], "invocations": int(m["invocations"]),
            "simulator_dtype": m["simulator_dtype"], "official_dtype": m["official_dtype"],
            "elements_per_call": int(m["rows"]) * int(m["hidden_size"]),
            "vector_length": int(m["hidden_size"]),
            "reduction_scalars_per_call": int(m["global_stat_scalars_per_call"]),
            "logical_input_output_bytes_per_call": int(m["logical_input_bytes_per_call"]) + int(m["logical_output_bytes_per_call"]),
            "affine_parameter_bytes_per_call": int(m["affine_parameter_bytes_per_call"]),
            "measured_compute_cycles_per_call": int(m["cycles_per_profile_run"]),
            "trace_calls": len(events), "trace_mean_queue_cycles": round(statistics.mean(queues), 3),
            "trace_max_queue_cycles": max(queues), "trace_mean_service_cycles": round(statistics.mean(service), 3),
            "trace_total_service_cycles": sum(service),
            "evidence_activation": m["activation_status"],
            "evidence_shape_calls": m["source_status"],
            "cycle_scope": m["cycle_scope"],
        }
        characteristics.append(chars)

    with (OUT / "workload_characteristics.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(characteristics[0]))
        writer.writeheader(); writer.writerows(characteristics)

    total = {
        "profile_count": len(manifest), "trace_call_count": len(trace),
        "norm_type_counts": dict(Counter(r["norm_type"] for r in manifest)),
        "simulator_dtype_counts": dict(Counter(r["simulator_dtype"] for r in manifest)),
        "official_dtype_counts": dict(Counter(r["official_dtype"] for r in manifest)),
        "total_invocations": sum(int(r["invocations"]) for r in manifest),
        "total_elements": sum(int(r["rows"]) * int(r["hidden_size"]) * int(r["invocations"]) for r in manifest),
        "total_logical_input_output_bytes": sum((int(r["logical_input_bytes_per_call"]) + int(r["logical_output_bytes_per_call"])) * int(r["invocations"]) for r in manifest),
        "total_reduction_scalars": sum(int(r["global_stat_scalars_per_call"]) * int(r["invocations"]) for r in manifest),
        "trace_total_queue_cycles": sum(int(r["queue_cycles"]) for r in trace),
        "trace_total_service_cycles": sum(int(r["service_cycles"]) for r in trace),
        "trace_max_queue_cycles": max(int(r["queue_cycles"]) for r in trace),
        "trace_channel_counts": dict(Counter(r["channel"] for r in trace)),
        "trace_arrival_span_cycles": int(trace[-1]["arrival_cycle"]) - int(trace[0]["arrival_cycle"]),
        "data_classification": {
            "model_and_revision": "DERIVED; nvidia/GR00T-N1.7-3B and pinned revisions in experiment/gr00t_placement/README.md and assumptions.json",
            "shape_and_invocations": "DERIVED_FROM_PINNED_OFFICIAL_SOURCE",
            "activation": "SYNTHETIC deterministic FP16; not pretrained activation trace",
            "compute_cycles": "MEASURED simulator profile run; projected across invocation count",
            "queue_and_service": "MEASURED replay of synthetic profile trace under fixed arrival schedule",
            "bandwidth_latency_power": "NOT_MEASURED for GR00T; any DSE values are modeled/assumed",
        },
    }
    (OUT / "workload_characteristics.json").write_text(json.dumps(total, indent=2), encoding="utf-8")

    # Candidate values are intentionally split: lane/core evidence is from RTL; PCU/FIFO/buffer are design assumptions.
    sky_by = {(r["data_format"], int(r["lanes"])): r for r in sky}
    gen_by = {(r["data_format"], int(r["lanes"])): r for r in synth if r["architecture"] == "pipelined_tree"}
    candidates = [
        ("low_area", 2, 1, 4, 4, 4, 1, "16 KiB", "MEASURED lane core; ASSUMED scaling/queue/context"),
        ("balanced", 4, 8, 8, 8, 16, 2, "64 KiB", "MEASURED lane core; ASSUMED scalar/PCU/FIFO/buffer"),
        ("high_performance", 8, 16, 16, 16, 16, 4, "256 KiB", "MODELED lane extrapolation; ASSUMED scalar/PCU/FIFO/buffer"),
    ]
    dse = []
    for name, lanes, scalar, pcu, fifo, context, buffers, buf, evidence in candidates:
        fp = sky_by.get(("FP16", min(lanes, 4)))
        bf = sky_by.get(("BF16", min(lanes, 4)))
        fp_area = float(fp["mapped_area_um2"]) if fp else None
        bf_area = float(bf["mapped_area_um2"]) if bf else None
        fp_timing = float(fp["critical_path_ns"]) if fp else None
        bf_timing = float(bf["critical_path_ns"]) if bf else None
        if lanes > 4:
            fp_area *= lanes / 4.0; bf_area *= lanes / 4.0
            fp_timing = None; bf_timing = None
        base = sum(int(r["cycles_per_profile_run"]) * int(r["invocations"]) for r in manifest)
        # Only a transparent throughput model: measured elementwise proxy divided by replication count.
        modeled_cycles = base / max(1, pcu) + total["total_reduction_scalars"] / max(1, scalar) * 16
        dse.append({
            "candidate": name, "lanes": lanes, "reducer": "pipelined_tree", "scalar_engines": scalar,
            "pcu": pcu, "fifo_depth": fifo, "context_entries": context, "buffer": buf,
            "expected_reducer_pipeline_stages": lanes.bit_length() - 1,
            "expected_ii_cycles": 1,
            "modeled_projected_cycles": round(modeled_cycles, 3),
            "modeled_throughput_elements_per_cycle": round(pcu * lanes, 3),
            "modeled_utilization_percent": round(min(100.0, total["trace_total_service_cycles"] / max(1, total["trace_arrival_span_cycles"]) * 100.0 * pcu / 8.0), 3),
            "modeled_partial_bandwidth_GBps": round(total["total_reduction_scalars"] * 4 / max(1, total["trace_arrival_span_cycles"] / 100.0) / 1e3, 6),
            "fp16_norm_core_area_um2": round(fp_area, 4), "bf16_norm_core_area_um2": round(bf_area, 4),
            "fp16_critical_path_ns": fp_timing, "bf16_critical_path_ns": bf_timing,
            "fp16_max_frequency_mhz": round(1000.0 / fp_timing, 3) if fp_timing else None,
            "bf16_max_frequency_mhz": round(1000.0 / bf_timing, 3) if bf_timing else None,
            "timing_status": "FAIL at 100MHz measured for 2/4 lanes; >4 lanes not STA-measured" if lanes <= 4 else "UNVERIFIED; lane extrapolation only",
            "power_energy": "UNAVAILABLE: no representative VCD/SAIF",
            "evidence_class": evidence,
        })
    with (OUT / "architecture_dse.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(dse[0])); writer.writeheader(); writer.writerows(dse)

    audit = {
        "status": "PROVISIONAL_ONLY",
        "reason": ["activation is synthetic", "no full GR00T E2E profiler", "no pretrained BF16 activation/transaction trace", "100MHz Sky130 timing fails measured 2/4-lane variants"],
        "actual_evidence": ["7 profile manifest rows", "333 synthetic replay calls", "2 simulator tests PASS", "normalization_synthesis_metrics.csv", "normalization_sky130_metrics.csv"],
        "missing_evidence": ["raw GR00T command/address/timestamp trace", "seeded full inference command", "actual bank/channel distribution", "real bandwidth and queue occupancy", "activity-annotated power/energy"],
        "reproduction": ["python tools/analyze_gr00t_workload_architecture.py", "bash verification/groot_normalization/run_foundation_regression.sh --tests-only", "bash verification/groot_normalization/run_normalization_structural_audit.sh", "bash verification/groot_normalization/run_normalization_sky130_mapping.sh"],
    }
    (OUT / "audit_summary.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print(f"GR00T_WORKLOAD_ARCHITECTURE_ANALYSIS PASS profiles={len(manifest)} trace_calls={len(trace)} candidates={len(dse)} status=PROVISIONAL_ONLY")


if __name__ == "__main__":
    main()
