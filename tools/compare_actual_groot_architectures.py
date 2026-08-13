#!/usr/bin/env python3
"""Compare four normalization placements using the captured GR00T action workload."""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/groot_normalization/results/actual_groot"
TRACE = BASE / "action_head_trace"
GPU = BASE / "gpu_benchmark/gpu_layernorm_latency.json"
OUT = BASE / "architecture_comparison"

PARAMS = {
    "evidence_class": "MIXED_MEASURED_DERIVED_MODELED_ASSUMED",
    "tensor_dtype": "BF16",
    "bytes_per_element": 2,
    "banks": 16,
    "reducer_lanes_per_bank": 4,
    "bank_pcu_vector_elements": 16,
    "scalar_engines": 8,
    "reference_clock_mhz": 40,
    "reference_clock_status": "MODELED_SAFE_TARGET_FROM_EXISTING_SKY130_STA; NOT A NEW TIMING-CLOSED RESULT",
    "reducer_pipeline_cycles": 3,
    "scalar_pipeline_cycles": 5,
    "layernorm_commands_per_bank_vector": 4,
    "replay_cycles_per_bank_vector": 1,
    "writeback_cycles_per_bank_vector": 1,
    "mode_sync_cycles_per_call": 8,
    "partial_bytes_per_bank_row": 4,
    "scalar_return_bytes_per_bank_row": 4,
    "ondie_one_way_latency_ns": 50,
    "ondie_bandwidth_gbytes_per_s": 128,
    "offload_one_way_latency_ns": 2500,
    "offload_bandwidth_gbytes_per_s": 8,
    "gpu_scalar_batch_latency_ns": 5000,
    "logic_pcus": 16,
    "logic_vector_lanes": 16,
    "logic_commands_per_vector": 4,
    "traffic_definition": "logical payload bytes; not measured DRAM/HBM transactions",
    "energy_status": "UNAVAILABLE_NO_ACTIVITY_CALIBRATED_POWER_MODEL",
}


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def transfer_ns(byte_count: float, bandwidth_gbytes_s: float) -> float:
    return byte_count / bandwidth_gbytes_s


def workload_rows() -> list[dict]:
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    invocations = load_csv(TRACE / "invocations.csv")
    affine = {}
    for row in invocations:
        affine.setdefault(row["profile_id"], row["elementwise_affine"].lower() == "true")
    mapping = json.loads((BASE / "rtl_mapping/mapping_manifest.json").read_text(encoding="utf-8"))
    mapped = {row["profile_id"]: row for row in mapping["profiles"]}
    rows = []
    for profile, sample in manifest["samples"].items():
        shape = sample["shape"]
        row_count = math.prod(shape[:-1])
        hidden = shape[-1]
        calls = int(manifest["profile_counts"][profile])
        elements = row_count * hidden
        tensor_bytes = elements * PARAMS["bytes_per_element"]
        affine_bytes = hidden * PARAMS["bytes_per_element"] * 2 if affine[profile] else 0
        partial_bytes = row_count * PARAMS["banks"] * PARAMS["partial_bytes_per_bank_row"]
        scalar_bytes = row_count * PARAMS["banks"] * PARAMS["scalar_return_bytes_per_bank_row"]
        rows.append({
            "profile_id": profile,
            "shape": "x".join(str(value) for value in shape),
            "rows": row_count,
            "hidden_size": hidden,
            "invocations": calls,
            "elementwise_affine": affine[profile],
            "tensor_bytes_per_call": tensor_bytes,
            "affine_bytes_per_call": affine_bytes,
            "partial_stat_bytes_per_call": partial_bytes,
            "scalar_broadcast_bytes_per_call": scalar_bytes,
            "vectors_per_bank": int(mapped[profile]["vectors_per_bank"]),
            "reduction_packets_per_call": int(mapped[profile]["packets"]),
            "bank_pcu_vectors_per_call": row_count * PARAMS["banks"] * math.ceil(hidden / (PARAMS["banks"] * PARAMS["bank_pcu_vector_elements"])),
            "partial_stat_transactions_per_call": row_count * PARAMS["banks"],
            "scalar_broadcast_transactions_per_call": row_count * PARAMS["banks"],
            "mapping_roundtrip_mismatches": int(mapped[profile]["roundtrip_mismatches"]),
            "source_classification": manifest["classification"],
        })
    return rows


def hierarchy_cycles(
    row: dict,
    clock_mhz: float,
    banks: int = 16,
    replay_write_cycles: int = 1,
    scalar_engines: int = 8,
    bank_skew_fraction: float = 0.0,
) -> float:
    lanes = PARAMS["reducer_lanes_per_bank"]
    reduce_vectors = math.ceil(row["hidden_size"] / (banks * lanes))
    bank_vectors = math.ceil(row["hidden_size"] / (banks * PARAMS["bank_pcu_vector_elements"]))
    reduction = (row["rows"] * reduce_vectors + PARAMS["reducer_pipeline_cycles"]) * (1.0 + bank_skew_fraction)
    scalar = math.ceil(row["rows"] / scalar_engines) + PARAMS["scalar_pipeline_cycles"]
    apply = row["rows"] * bank_vectors * PARAMS["layernorm_commands_per_bank_vector"]
    replay_write = row["rows"] * bank_vectors * replay_write_cycles * 2
    return reduction + scalar + apply + replay_write + PARAMS["mode_sync_cycles_per_call"]


def logic_cycles(row: dict) -> float:
    width = PARAMS["logic_pcus"] * PARAMS["logic_vector_lanes"]
    vectors = math.ceil(row["hidden_size"] / width)
    reduction = row["rows"] * vectors
    scalar = math.ceil(row["rows"] / PARAMS["scalar_engines"]) + PARAMS["scalar_pipeline_cycles"]
    apply = row["rows"] * vectors * PARAMS["logic_commands_per_vector"]
    return reduction + scalar + apply + PARAMS["mode_sync_cycles_per_call"]


def aggregate(rows: list[dict], gpu: dict, clock_mhz: float = 40) -> list[dict]:
    clock_ns = 1000.0 / clock_mhz
    gpu_us = float(gpu["total_projected_serial_latency_us"])
    logical_gpu = sum((2 * row["tensor_bytes_per_call"] + row["affine_bytes_per_call"]) * row["invocations"] for row in rows)
    bank_memory = sum((3 * row["tensor_bytes_per_call"] + row["affine_bytes_per_call"]) * row["invocations"] for row in rows)
    logic_memory = logical_gpu
    stat_link = sum((row["partial_stat_bytes_per_call"] + row["scalar_broadcast_bytes_per_call"]) * row["invocations"] for row in rows)
    logic_link = sum((2 * row["tensor_bytes_per_call"] + row["affine_bytes_per_call"]) * row["invocations"] for row in rows)
    h_cycles = sum(hierarchy_cycles(row, clock_mhz) * row["invocations"] for row in rows)
    l_cycles = sum(logic_cycles(row) * row["invocations"] for row in rows)
    h_link_ns = sum(
        (2 * PARAMS["ondie_one_way_latency_ns"] + transfer_ns(row["partial_stat_bytes_per_call"] + row["scalar_broadcast_bytes_per_call"], PARAMS["ondie_bandwidth_gbytes_per_s"])) * row["invocations"]
        for row in rows
    )
    offload_ns = sum(
        (2 * PARAMS["offload_one_way_latency_ns"] + PARAMS["gpu_scalar_batch_latency_ns"] + transfer_ns(row["partial_stat_bytes_per_call"] + row["scalar_broadcast_bytes_per_call"], PARAMS["offload_bandwidth_gbytes_per_s"])) * row["invocations"]
        for row in rows
    )
    logic_link_ns = sum(
        (2 * PARAMS["ondie_one_way_latency_ns"] + transfer_ns(2 * row["tensor_bytes_per_call"] + row["affine_bytes_per_call"], PARAMS["ondie_bandwidth_gbytes_per_s"])) * row["invocations"]
        for row in rows
    )
    hierarchical_us = (h_cycles * clock_ns + h_link_ns) / 1000.0
    logic_us = (l_cycles * clock_ns + logic_link_ns) / 1000.0
    bank_us = (h_cycles * clock_ns + offload_ns) / 1000.0
    return [
        {"architecture": "GPU", "latency_us": gpu_us, "memory_array_bytes": logical_gpu, "cross_domain_bytes": 0, "traffic_total_bytes": logical_gpu, "latency_evidence": "MEASURED_CUDA_EVENTS_PROJECTED_BY_CAPTURED_CALL_COUNT", "accuracy": "PYTORCH_GOLDEN", "implementation": "AVAILABLE"},
        {"architecture": "Bank-only PIM", "latency_us": bank_us, "memory_array_bytes": bank_memory, "cross_domain_bytes": stat_link, "traffic_total_bytes": bank_memory + stat_link, "latency_evidence": "MODELED_RTL_CYCLES_PLUS_ASSUMED_OFFLOAD", "accuracy": "UNVERIFIED", "implementation": "PARTIAL"},
        {"architecture": "Logic-only PIM", "latency_us": logic_us, "memory_array_bytes": logic_memory, "cross_domain_bytes": logic_link, "traffic_total_bytes": logic_memory + logic_link, "latency_evidence": "MODELED_VECTOR_THROUGHPUT_AND_ONDIE_LINK", "accuracy": "UNVERIFIED", "implementation": "MODEL_ONLY"},
        {"architecture": "Hierarchical PIM", "latency_us": hierarchical_us, "memory_array_bytes": bank_memory, "cross_domain_bytes": stat_link, "traffic_total_bytes": bank_memory + stat_link, "latency_evidence": "MODELED_FROM_RTL_STAGE_COUNTS_WITH_EXPLICIT_REPLAY_WRITEBACK", "accuracy": "FAIL_1_OF_6_PROFILES_PASS", "implementation": "REPLAY_WRITEBACK_NOT_PRODUCTION"},
    ]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = workload_rows()
    gpu = json.loads(GPU.read_text(encoding="utf-8"))
    with (OUT / "actual_workload_traffic.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    tensor_total = sum(row["tensor_bytes_per_call"] * row["invocations"] for row in rows)
    affine_total = sum(row["affine_bytes_per_call"] * row["invocations"] for row in rows)
    reduction_packets = sum(row["reduction_packets_per_call"] * row["invocations"] for row in rows)
    bank_vectors = sum(row["bank_pcu_vectors_per_call"] * row["invocations"] for row in rows)
    partial_transactions = sum(row["partial_stat_transactions_per_call"] * row["invocations"] for row in rows)
    scalar_transactions = sum(row["scalar_broadcast_transactions_per_call"] * row["invocations"] for row in rows)
    breakdown = []
    def add_breakdown(architecture: str, component: str, byte_count: int, transactions: int, domain: str, evidence: str) -> None:
        breakdown.append({"architecture": architecture, "component": component, "bytes": byte_count, "transactions": transactions, "transaction_bytes": byte_count / transactions if transactions else 0, "domain": domain, "evidence": evidence})
    gpu_calls = sum(row["invocations"] for row in rows)
    add_breakdown("GPU", "activation_read", tensor_total, sum(math.ceil(row["tensor_bytes_per_call"] / 32) * row["invocations"] for row in rows), "logical_memory", "DERIVED_32B_MINIMUM_TRANSACTION")
    add_breakdown("GPU", "output_write", tensor_total, sum(math.ceil(row["tensor_bytes_per_call"] / 32) * row["invocations"] for row in rows), "logical_memory", "DERIVED_32B_MINIMUM_TRANSACTION")
    add_breakdown("GPU", "gamma_beta", affine_total, sum(math.ceil(row["affine_bytes_per_call"] / 32) * row["invocations"] for row in rows), "logical_memory", "DERIVED_32B_MINIMUM_TRANSACTION")
    for architecture in ("Bank-only PIM", "Hierarchical PIM"):
        add_breakdown(architecture, "reduction_activation_read", tensor_total, reduction_packets, "bank_array", "DERIVED_FROM_EXACT_4_LANE_MAPPING")
        add_breakdown(architecture, "activation_replay", tensor_total, bank_vectors, "bank_array", "MODELED_256B_BANK_PCU_VECTOR")
        add_breakdown(architecture, "final_writeback", tensor_total, bank_vectors, "bank_array", "MODELED_256B_BANK_PCU_VECTOR")
        add_breakdown(architecture, "gamma_beta", affine_total, sum(math.ceil(row["affine_bytes_per_call"] / 32) * row["invocations"] for row in rows), "bank_array", "DERIVED_LOGICAL_PAYLOAD")
        add_breakdown(architecture, "partial_sum_sumsq", partial_transactions * PARAMS["partial_bytes_per_bank_row"], partial_transactions, "offload_link" if architecture.startswith("Bank-only") else "ondie_link", "RTL_INTERFACE_PAYLOAD")
        add_breakdown(architecture, "mean_inv_std_return", scalar_transactions * PARAMS["scalar_return_bytes_per_bank_row"], scalar_transactions, "offload_link" if architecture.startswith("Bank-only") else "ondie_link", "RTL_INTERFACE_PAYLOAD")
    add_breakdown("Logic-only PIM", "activation_bank_to_logic", tensor_total, sum(math.ceil(row["tensor_bytes_per_call"] / 32) * row["invocations"] for row in rows), "ondie_link", "MODELED_256B_TRANSFER")
    add_breakdown("Logic-only PIM", "output_logic_to_bank", tensor_total, sum(math.ceil(row["tensor_bytes_per_call"] / 32) * row["invocations"] for row in rows), "ondie_link", "MODELED_256B_TRANSFER")
    add_breakdown("Logic-only PIM", "gamma_beta_bank_to_logic", affine_total, sum(math.ceil(row["affine_bytes_per_call"] / 32) * row["invocations"] for row in rows), "ondie_link", "MODELED_256B_TRANSFER")
    with (OUT / "architecture_traffic_breakdown.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(breakdown[0]))
        writer.writeheader()
        writer.writerows(breakdown)
    comparison = aggregate(rows, gpu)
    gpu_latency = comparison[0]["latency_us"]
    for row in comparison:
        row["speedup_vs_gpu"] = gpu_latency / row["latency_us"]
        row["traffic_ratio_vs_gpu"] = row["traffic_total_bytes"] / comparison[0]["traffic_total_bytes"]
        row["energy"] = PARAMS["energy_status"]
    with (OUT / "architecture_comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(comparison[0]))
        writer.writeheader()
        writer.writerows(comparison)

    gpu_by_profile = {row["profile_id"]: row for row in gpu["profiles"]}
    per_profile = []
    for workload in rows:
        one = aggregate([workload], {"total_projected_serial_latency_us": gpu_by_profile[workload["profile_id"]]["projected_serial_latency_us"]})
        for result in one:
            per_profile.append({
                "profile_id": workload["profile_id"],
                "shape": workload["shape"],
                "invocations": workload["invocations"],
                "architecture": result["architecture"],
                "projected_latency_us": result["latency_us"],
                "traffic_total_bytes": result["traffic_total_bytes"],
                "speedup_vs_profile_gpu": one[0]["latency_us"] / result["latency_us"],
            })
    with (OUT / "per_profile_architecture_comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(per_profile[0]))
        writer.writeheader()
        writer.writerows(per_profile)

    sensitivity = []
    for clock in (40, 50, 100, 250, 500, 1000):
        result = aggregate(rows, gpu, clock)[3]
        sensitivity.append({"sweep": "clock_mhz", "value": clock, "hierarchical_latency_us": result["latency_us"], "speedup_vs_gpu": gpu_latency / result["latency_us"], "traffic_total_bytes": result["traffic_total_bytes"], "status": "MODELED" if clock <= 50 else "UNVERIFIED_FREQUENCY"})
    for banks in (4, 8, 16, 32):
        cycles = sum(hierarchy_cycles(row, PARAMS["reference_clock_mhz"], banks=banks) * row["invocations"] for row in rows)
        link_bytes = sum((row["rows"] * banks * (PARAMS["partial_bytes_per_bank_row"] + PARAMS["scalar_return_bytes_per_bank_row"])) * row["invocations"] for row in rows)
        link_ns = 2 * PARAMS["ondie_one_way_latency_ns"] * sum(row["invocations"] for row in rows) + transfer_ns(link_bytes, PARAMS["ondie_bandwidth_gbytes_per_s"])
        latency = (cycles * 1000 / PARAMS["reference_clock_mhz"] + link_ns) / 1000
        sensitivity.append({"sweep": "banks", "value": banks, "hierarchical_latency_us": latency, "speedup_vs_gpu": gpu_latency / latency, "traffic_total_bytes": "", "status": "MODELED"})
    for cycles_per_vector in (0, 1, 2, 4, 8):
        cycles = sum(hierarchy_cycles(row, PARAMS["reference_clock_mhz"], replay_write_cycles=cycles_per_vector) * row["invocations"] for row in rows)
        stat_bytes = sum((row["partial_stat_bytes_per_call"] + row["scalar_broadcast_bytes_per_call"]) * row["invocations"] for row in rows)
        link_ns = 2 * PARAMS["ondie_one_way_latency_ns"] * sum(row["invocations"] for row in rows) + transfer_ns(stat_bytes, PARAMS["ondie_bandwidth_gbytes_per_s"])
        latency = (cycles * 1000 / PARAMS["reference_clock_mhz"] + link_ns) / 1000
        sensitivity.append({"sweep": "replay_write_cycles_per_vector_each", "value": cycles_per_vector, "hierarchical_latency_us": latency, "speedup_vs_gpu": gpu_latency / latency, "traffic_total_bytes": comparison[3]["traffic_total_bytes"], "status": "MODELED"})
    total_calls = sum(row["invocations"] for row in rows)
    stat_bytes = sum((row["partial_stat_bytes_per_call"] + row["scalar_broadcast_bytes_per_call"]) * row["invocations"] for row in rows)
    base_cycles = sum(hierarchy_cycles(row, PARAMS["reference_clock_mhz"]) * row["invocations"] for row in rows)
    for bandwidth in (16, 32, 64, 128, 256, 512):
        link_ns = 2 * PARAMS["ondie_one_way_latency_ns"] * total_calls + transfer_ns(stat_bytes, bandwidth)
        latency = (base_cycles * 1000 / PARAMS["reference_clock_mhz"] + link_ns) / 1000
        sensitivity.append({"sweep": "ondie_bandwidth_gbytes_per_s", "value": bandwidth, "hierarchical_latency_us": latency, "speedup_vs_gpu": gpu_latency / latency, "traffic_total_bytes": comparison[3]["traffic_total_bytes"], "status": "MODELED"})
    for latency_ns in (10, 25, 50, 100, 250, 500):
        link_ns = 2 * latency_ns * total_calls + transfer_ns(stat_bytes, PARAMS["ondie_bandwidth_gbytes_per_s"])
        latency = (base_cycles * 1000 / PARAMS["reference_clock_mhz"] + link_ns) / 1000
        sensitivity.append({"sweep": "ondie_one_way_latency_ns", "value": latency_ns, "hierarchical_latency_us": latency, "speedup_vs_gpu": gpu_latency / latency, "traffic_total_bytes": comparison[3]["traffic_total_bytes"], "status": "MODELED"})
    for engines in (1, 2, 4, 8, 16):
        cycles = sum(hierarchy_cycles(row, PARAMS["reference_clock_mhz"], scalar_engines=engines) * row["invocations"] for row in rows)
        link_ns = 2 * PARAMS["ondie_one_way_latency_ns"] * total_calls + transfer_ns(stat_bytes, PARAMS["ondie_bandwidth_gbytes_per_s"])
        latency = (cycles * 1000 / PARAMS["reference_clock_mhz"] + link_ns) / 1000
        sensitivity.append({"sweep": "scalar_engines", "value": engines, "hierarchical_latency_us": latency, "speedup_vs_gpu": gpu_latency / latency, "traffic_total_bytes": comparison[3]["traffic_total_bytes"], "status": "MODELED_FROM_RTL_ENGINE_ARRAY"})
    for skew in (0.0, 0.02, 0.05, 0.10, 0.20):
        cycles = sum(hierarchy_cycles(row, PARAMS["reference_clock_mhz"], bank_skew_fraction=skew) * row["invocations"] for row in rows)
        link_ns = 2 * PARAMS["ondie_one_way_latency_ns"] * total_calls + transfer_ns(stat_bytes, PARAMS["ondie_bandwidth_gbytes_per_s"])
        latency = (cycles * 1000 / PARAMS["reference_clock_mhz"] + link_ns) / 1000
        sensitivity.append({"sweep": "bank_skew_fraction", "value": skew, "hierarchical_latency_us": latency, "speedup_vs_gpu": gpu_latency / latency, "traffic_total_bytes": comparison[3]["traffic_total_bytes"], "status": "MODELED_AS_REDUCTION_STALL"})
    no_reuse_affine = sum(row["affine_bytes_per_call"] * row["invocations"] for row in rows)
    ideal_profile_cache_affine = sum(row["affine_bytes_per_call"] for row in rows)
    tensor_and_stats = comparison[3]["traffic_total_bytes"] - no_reuse_affine
    sensitivity.append({"sweep": "gamma_beta_reuse", "value": "actual_module_schedule", "hierarchical_latency_us": comparison[3]["latency_us"], "speedup_vs_gpu": comparison[3]["speedup_vs_gpu"], "traffic_total_bytes": comparison[3]["traffic_total_bytes"], "status": "DERIVED_EACH_AFFINE_MODULE_CALLED_ONCE"})
    sensitivity.append({"sweep": "gamma_beta_reuse", "value": "ideal_once_per_profile", "hierarchical_latency_us": comparison[3]["latency_us"], "speedup_vs_gpu": comparison[3]["speedup_vs_gpu"], "traffic_total_bytes": tensor_and_stats + ideal_profile_cache_affine, "status": "MODELED_UPPER_BOUND_NOT_ACTUAL_MODULE_IDENTITY"})
    with (OUT / "sensitivity.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(sensitivity[0]))
        writer.writeheader()
        writer.writerows(sensitivity)

    h40 = comparison[3]["latency_us"]
    fixed_link_us = h40 - sum(hierarchy_cycles(row, 40) * row["invocations"] for row in rows) * 0.025
    total_cycles = sum(hierarchy_cycles(row, 40) * row["invocations"] for row in rows)
    available_compute_us = gpu_latency - fixed_link_us
    break_even_clock = total_cycles / available_compute_us if available_compute_us > 0 else math.inf
    decision = {
        "decision": "NO-GO",
        "mandatory_reasons": [
            "Current hierarchical BF16 RTL failed the pre-existing accuracy criterion on 5 of 6 representative profiles.",
            "At the 40 MHz modeled safe target, hierarchical latency is slower than measured RTX 4060 BF16 LayerNorm.",
            "Production replay/write-back RTL is absent; its modeled cost is already included and does not reverse the result.",
            "No comparable activity-calibrated energy or physical area result exists to justify expansion on another axis.",
        ],
        "modeled_latency_break_even_clock_mhz": break_even_clock,
        "break_even_clock_timing_status": "UNVERIFIED_AND_ABOVE_CURRENT_SKY130_TIMING_EVIDENCE",
        "accuracy_requirement": "Must pass max_abs <= 0.025 on all representative profiles before production expansion.",
        "reconsideration_conditions": [
            "Widen accumulation/scalar/apply precision and pass the accuracy gate.",
            "Timing-close the integrated datapath at or above the modeled latency break-even frequency.",
            "Measure replay/writeback latency and energy with production RTL and representative activity.",
            "Obtain full GR00T inference trace if gated backbone access and >=16 GB GPU become available.",
        ],
    }
    payload = {
        "scope": "captured pretrained GR00T action-head normalization only; synthetic boundary input; not full GR00T inference",
        "parameters": PARAMS,
        "gpu_measurement": {key: gpu[key] for key in ("device", "torch_version", "cuda_runtime", "timing_method", "total_projected_serial_latency_us")},
        "comparison": comparison,
        "decision_gate": decision,
    }
    (OUT / "architecture_comparison.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    (OUT / "actual_groot_architecture_parameters.json").write_text(json.dumps(PARAMS, indent=2), encoding="utf-8")
    (OUT / "decision_gate.json").write_text(json.dumps(decision, indent=2), encoding="utf-8")
    print(f"GROOT_ARCHITECTURE_COMPARISON PASS architectures=4 decision=NO-GO break_even_mhz={break_even_clock:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
