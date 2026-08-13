#!/usr/bin/env python3
"""Discrete-event replay of the GR00T normalization manifest.

Stage service times come from groot_normalization_model. Resource capacities and
arrival rates are explicit assumptions. This is a system simulator, not GPU or
silicon measurement.
"""

from __future__ import annotations

import argparse
import csv
import heapq
import json
import math
from collections import defaultdict
from pathlib import Path

from groot_normalization_model import load_parameters, load_profiles, model_profile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports" / "groot_normalization" / "results"


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1)]


def stages(case: str, row: dict) -> list[tuple[str, str, float]]:
    b = row
    if case == "gpu_full":
        return [
            ("launch", "gpu", b["queue_sync_ns"]),
            ("input", "offload_link", b["partial_transfer_ns"]),
            ("normalize", "gpu", b["global_reduce_ns"]),
            ("output", "offload_link", b["return_ns"]),
        ]
    if case == "bank_only":
        return [
            ("local_reduce", "bank", b["local_reduce_ns"]),
            ("partial_offload", "offload_link", b["partial_transfer_ns"]),
            ("gpu_scalar", "gpu", b["queue_sync_ns"] + b["global_reduce_ns"] +
             b["finalize_ns"] + b["rsqrt_ns"]),
            ("scalar_return", "offload_link", b["return_ns"]),
            ("bank_apply", "bank", b["apply_ns"]),
        ]
    if case == "logic_only":
        return [
            ("tensor_to_logic", "ondie_link", b["partial_transfer_ns"]),
            ("logic_normalize", "logic", b["local_reduce_ns"] + b["global_reduce_ns"] +
             b["finalize_ns"] + b["rsqrt_ns"] + b["apply_ns"]),
            ("tensor_return", "ondie_link", b["return_ns"]),
        ]
    if case == "hierarchical":
        return [
            ("local_reduce", "bank", b["local_reduce_ns"]),
            ("partial_to_logic", "ondie_link", b["partial_transfer_ns"]),
            ("logic_scalar", "logic", b["global_reduce_ns"] + b["finalize_ns"] + b["rsqrt_ns"]),
            ("scalar_broadcast", "ondie_link", b["return_ns"]),
            ("bank_apply", "bank", b["apply_ns"]),
        ]
    raise ValueError(case)


def reserve(slots: list[float], ready: float, duration: float) -> tuple[float, float]:
    available = heapq.heappop(slots)
    start = max(ready, available)
    finish = start + duration
    heapq.heappush(slots, finish)
    return start, finish


def simulate(case: str, scenario: str, rate: float, profiles, params: dict) -> tuple[dict, list[dict]]:
    ref = params["reference_point"]
    capacities = params["system_simulation"]["resource_capacity"]
    resources = {name: [0.0] * int(count) for name, count in capacities.items()}
    for slots in resources.values():
        heapq.heapify(slots)
    busy = defaultdict(float)
    stage_busy = defaultdict(float)
    latencies: list[float] = []
    queues: list[float] = []
    trace_rows: list[dict] = []
    total_tensor = total_partial = total_return = 0
    ordinal = 0
    interval_ns = 1.0e9 / (rate * int(params["system_simulation"]["channels"]))

    for profile in profiles:
        modeled = model_profile(profile, case, ref)
        for _ in range(profile.invocations):
            arrival = ordinal * interval_ns
            ready = arrival
            queue_total = 0.0
            for stage_name, resource, duration in stages(case, modeled):
                start, finish = reserve(resources[resource], ready, float(duration))
                queue_total += start - ready
                busy[resource] += float(duration)
                stage_busy[stage_name] += float(duration)
                ready = finish
            latency = ready - arrival
            latencies.append(latency)
            queues.append(queue_total)
            total_tensor += int(modeled["tensor_bytes"])
            total_partial += int(modeled["partial_bytes"])
            total_return += int(modeled["return_bytes"])
            trace_rows.append({
                "scenario": scenario, "case": case, "ordinal": ordinal,
                "profile_id": profile.profile_id, "arrival_ns": round(arrival, 6),
                "completion_ns": round(ready, 6), "latency_ns": round(latency, 6),
                "queue_ns": round(queue_total, 6),
                "service_ns": round(latency - queue_total, 6),
            })
            ordinal += 1

    span = max(row["completion_ns"] for row in trace_rows)
    rtl = params["rtl_measurements"]
    bank_reducer_area = (rtl["bank_local_scalar_reducer_generic_cells_per_bank"]["value"] *
                         int(ref["banks"]))
    logic_array = rtl["logic_normalization_dispatcher"]
    logic_count = int(ref["logic_pcus"])
    logic_array_area = dict(zip(logic_array["engines"], logic_array["generic_cells_with_dispatcher"]))[logic_count]
    area = {
        "gpu_full": None,
        "bank_only": bank_reducer_area,
        "logic_only": logic_array_area,
        "hierarchical": bank_reducer_area +
                        logic_array_area,
    }[case]
    summary = {
        "scenario": scenario, "case": case, "requests": len(latencies),
        "arrival_rate_per_channel_s": rate,
        "completion_span_ns": round(span, 6),
        "mean_latency_ns": round(sum(latencies) / len(latencies), 6),
        "p95_latency_ns": round(percentile(latencies, 0.95), 6),
        "mean_queue_ns": round(sum(queues) / len(queues), 6),
        "max_queue_ns": round(max(queues), 6),
        "tensor_bytes": total_tensor, "partial_bytes": total_partial,
        "return_bytes": total_return,
        "bank_utilization": round(busy["bank"] / (span * capacities["bank"]), 9),
        "logic_utilization": round(busy["logic"] / (span * capacities["logic"]), 9),
        "gpu_utilization": round(busy["gpu"] / (span * capacities["gpu"]), 9),
        "offload_link_utilization": round(busy["offload_link"] / (span * capacities["offload_link"]), 9),
        "ondie_link_utilization": round(busy["ondie_link"] / (span * capacities["ondie_link"]), 9),
        "area_generic_cells_proxy": area,
        "energy_nj": None,
        "stage_service_ns_json": json.dumps(dict(stage_busy), sort_keys=True),
        "evidence_class": "MIXED_RTL_MEASURED_SIMULATOR_MEASURED_ASSUMED_SYSTEM",
    }
    return summary, trace_rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=OUT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    profiles = load_profiles()
    params = load_parameters()
    summaries, traces = [], []
    for scenario, rate in params["system_simulation"]["request_rates_per_second_per_channel"].items():
        for case in ("gpu_full", "bank_only", "logic_only", "hierarchical"):
            summary, trace = simulate(case, scenario, float(rate), profiles, params)
            summaries.append(summary)
            traces.extend(trace)
    if args.self_test:
        assert len(summaries) == 12
        assert all(row["requests"] == 333 for row in summaries)
        assert all(row["mean_latency_ns"] >= 0 for row in summaries)
        assert all(0 <= row["bank_utilization"] <= 1 for row in summaries)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, rows in (("system_simulation_summary.csv", summaries),
                       ("system_simulation_trace.csv", traces)):
        with (args.output_dir / name).open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader(); writer.writerows(rows)
    print(f"SYSTEM_SIM PASS summaries={len(summaries)} trace_rows={len(traces)}")


if __name__ == "__main__":
    main()
