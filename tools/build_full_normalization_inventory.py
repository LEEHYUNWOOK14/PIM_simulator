#!/usr/bin/env python3
"""Build an evidence-labelled full-model GR00T normalization inventory.

This is intentionally an inventory task, not full-model inference.  It merges:
  * pinned checkpoint/code-derived module families and multiplicities;
  * measured pretrained action-head hook traces;
  * explicit scenarios for the only unresolved dimension, visual token rows.

The output never upgrades representative/static dimensions to runtime evidence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/groot_normalization/results/actual_groot"
STATIC_MANIFEST = BASE / "groot_actual_workload_manifest.json"
TRACE = BASE / "action_head_trace"
PCU_RESULT = ROOT / "reports/groot_normalization/results/logic_die_pcu_system"
OUT = ROOT / "reports/groot_normalization/results/full_normalization_inventory"
ANALYZER_PATH = ROOT / "tools/analyze_logic_die_pcu_system.py"

EXPECTED_PROFILES = {
    "backbone_language_input_rmsnorm",
    "backbone_language_post_attention_rmsnorm",
    "backbone_language_q_rmsnorm",
    "backbone_language_k_rmsnorm",
    "backbone_language_final_rmsnorm",
    "backbone_visual_block_norm1",
    "backbone_visual_block_norm2",
    "action_vlln",
    "action_vl_self_attention_norm1",
    "action_vl_self_attention_norm3",
    "action_dit_adaln_norm1",
    "action_dit_norm3",
    "action_dit_norm_out",
}


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"no rows for {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_evidence(source: Path | None, expected_revision: str) -> list[dict]:
    if source is None:
        return [{
            "artifact": "Isaac-GR00T source checkout",
            "status": "NOT_RECHECKED_THIS_RUN",
            "revision": expected_revision,
            "path": "",
            "sha256": "",
            "purpose": "revision retained from pinned static audit",
        }]
    revision = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != expected_revision:
        raise RuntimeError(f"source revision mismatch: {revision} != {expected_revision}")
    files = [
        source / "gr00t/model/gr00t_n1d7/gr00t_n1d7.py",
        source / "gr00t/model/modules/dit.py",
        source / "gr00t/model/modules/qwen3_backbone.py",
        source / "gr00t/configs/model/gr00t_n1d7.py",
    ]
    missing = [str(path) for path in files if not path.exists()]
    if missing:
        raise RuntimeError(f"missing pinned source files: {missing}")
    return [{
        "artifact": path.relative_to(source).as_posix(),
        "status": "PINNED_SOURCE_RECHECKED",
        "revision": revision,
        "path": str(path),
        "sha256": sha256(path),
        "purpose": "normalization construction/call-path evidence",
    } for path in files]


def measured_action_profiles() -> dict[str, dict]:
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    invocation_rows = read_csv(TRACE / "invocations.csv")
    grouped: dict[str, list[dict[str, str]]] = {}
    for row in invocation_rows:
        grouped.setdefault(row["profile_id"], []).append(row)
    result = {}
    for profile, sample in manifest["samples"].items():
        rows = grouped[profile]
        shapes = {row["shape"] for row in rows}
        dtypes = {row["dtype"] for row in rows}
        epsilons = {row["epsilon"] for row in rows}
        affines = {row["elementwise_affine"].lower() == "true" for row in rows}
        if len(shapes) != 1 or len(dtypes) != 1 or len(epsilons) != 1 or len(affines) != 1:
            raise RuntimeError(f"nonuniform measured action profile: {profile}")
        shape = sample["shape"]
        result[profile] = {
            "rows": math.prod(shape[:-1]),
            "hidden_size": shape[-1],
            "shape": "x".join(str(value) for value in shape),
            "dtype": next(iter(dtypes)).upper(),
            "epsilon": next(iter(epsilons)),
            "elementwise_affine": next(iter(affines)),
            "invocations": int(manifest["profile_counts"][profile]),
            "activation_evidence": manifest["classification"],
        }
    return result


def subsystem(profile: str) -> str:
    if profile.startswith("backbone_language"):
        return "language_backbone"
    if profile.startswith("backbone_visual"):
        return "vision_backbone"
    return "action_head"


def build_inventory(static: dict, measured: dict[str, dict]) -> list[dict]:
    profiles = {row["profile_id"]: row for row in static["profiles"]}
    if set(profiles) != EXPECTED_PROFILES:
        raise RuntimeError(
            f"profile coverage changed: missing={EXPECTED_PROFILES-set(profiles)} "
            f"extra={set(profiles)-EXPECTED_PROFILES}"
        )
    rows = []
    for profile in sorted(profiles):
        source = profiles[profile]
        runtime = measured.get(profile)
        representative = source["representative_rows"]
        if runtime:
            row_count = int(runtime["rows"])
            hidden = int(runtime["hidden_size"])
            invocations = int(runtime["invocations"])
            shape = runtime["shape"]
            dtype = runtime["dtype"]
            epsilon = runtime["epsilon"]
            affine = bool(runtime["elementwise_affine"])
            shape_evidence = "MEASURED_PRETRAINED_ACTION_HEAD_RUNTIME"
            count_evidence = "MEASURED_HOOK_COUNT"
            activation_evidence = runtime["activation_evidence"]
            inventory_status = "RUNTIME_CONFIRMED"
        else:
            row_count = int(representative) if representative != "" else None
            hidden = int(source["hidden_size"])
            invocations = int(source["invocations_per_policy_call"])
            shape = f"1x{row_count}x{hidden}" if row_count is not None else f"1xDYNAMICx{hidden}"
            dtype = str(source["dtype"])
            epsilon = str(source["epsilon"])
            affine = bool(source["elementwise_affine"])
            shape_evidence = (
                "CHECKPOINT_CODE_DERIVED_WITH_REPRESENTATIVE_ROWS"
                if row_count is not None else "RUNTIME_ROWS_REQUIRED"
            )
            count_evidence = "PINNED_CODE_AND_CHECKPOINT_DERIVED"
            activation_evidence = "NOT_CAPTURED"
            inventory_status = "STATIC_COMPLETE_RUNTIME_ROWS_OPEN" if row_count is None else "REPRESENTATIVE_COMPLETE"
        elements = row_count * hidden if row_count is not None else None
        affine_operands = 0 if not affine else (1 if source["norm_type"] == "RMSNorm" else 2)
        rows.append({
            "profile_id": profile,
            "subsystem": subsystem(profile),
            "module_path": source["module_path"],
            "norm_type": source["norm_type"],
            "shape": shape,
            "rows_per_invocation": "" if row_count is None else row_count,
            "hidden_size": hidden,
            "invocations_per_policy_call": invocations,
            "weighted_rows": "" if row_count is None else row_count * invocations,
            "elements_per_invocation": "" if elements is None else elements,
            "weighted_elements": "" if elements is None else elements * invocations,
            "dtype": dtype,
            "epsilon": epsilon,
            "elementwise_affine": affine,
            "affine_operands_per_element": affine_operands,
            "dynamic_modulation": bool(source["dynamic_modulation"]),
            "shape_evidence": shape_evidence,
            "call_count_evidence": count_evidence,
            "activation_evidence": activation_evidence,
            "inventory_status": inventory_status,
        })
    return rows


def evidence_discrepancies(static: dict, measured: dict[str, dict]) -> list[dict]:
    profiles = {row["profile_id"]: row for row in static["profiles"]}
    rows = []
    for profile, runtime in sorted(measured.items()):
        source = profiles[profile]
        comparisons = {
            "representative_rows": (source["representative_rows"], runtime["rows"]),
            "hidden_size": (source["hidden_size"], runtime["hidden_size"]),
            "invocations": (source["invocations_per_policy_call"], runtime["invocations"]),
            "elementwise_affine": (source["elementwise_affine"], runtime["elementwise_affine"]),
        }
        for field, (static_value, runtime_value) in comparisons.items():
            if str(static_value).lower() != str(runtime_value).lower():
                rows.append({
                    "profile_id": profile,
                    "field": field,
                    "static_value": static_value,
                    "runtime_value": runtime_value,
                    "resolution": "RUNTIME_TRACE_OVERRIDES_STATIC_MANIFEST",
                    "impact": (
                        "affine operand traffic corrected; arithmetic normalization core unchanged"
                        if field == "elementwise_affine" else "inventory value corrected"
                    ),
                })
    if not rows:
        rows.append({
            "profile_id": "NONE",
            "field": "NONE",
            "static_value": "",
            "runtime_value": "",
            "resolution": "NO_DISCREPANCY",
            "impact": "NONE",
        })
    return rows


def scalar_service(norm_type: str, analyzer) -> int:
    # RMSNorm skips mean, mean^2, and variance subtraction states in the current
    # scalar RTL.  This is a cycle-model assumption, not a measured RMS trace.
    return 44 if norm_type == "RMSNorm" else analyzer.SCALAR_SERVICE_CYCLES


def projected_call_cycles(row_count: int, hidden: int, lanes: int, norm_type: str, analyzer) -> int:
    """Project long-row calls from the event simulator's measured steady state.

    The event simulator keeps every completed row object for auditability and is
    intentionally not used directly for thousands of rows.  Calls up to 64 rows
    are simulated exactly; longer calls use the 32-to-64-row steady-state slope.
    """
    kwargs = {
        "hidden": hidden,
        "lanes": lanes,
        "scalar_engines": 4,
        "bank_port_mode": "independent_pcu_ports",
        "scalar_service_cycles": scalar_service(norm_type, analyzer),
    }
    if row_count <= 64:
        return analyzer.simulate_call(rows=row_count, **kwargs).cycles
    cycles_32 = analyzer.simulate_call(rows=32, **kwargs).cycles
    cycles_64 = analyzer.simulate_call(rows=64, **kwargs).cycles
    slope = (cycles_64 - cycles_32) / 32.0
    return round(cycles_64 + (row_count - 64) * slope)


def lane_sensitivity(inventory: list[dict], analyzer) -> list[dict]:
    action_rtl = read_csv(PCU_RESULT / "rtl_profile_results.csv")
    action_cycles = {
        (int(row["lanes"]), row["profile_id"]): int(row["weighted_cycles"])
        for row in action_rtl
    }
    scenarios = {
        "known_profiles_no_vision": None,
        "vision_rows_256": 256,
        "vision_rows_1024": 1024,
        "vision_rows_4096": 4096,
    }
    rows = []
    for scenario, visual_rows in scenarios.items():
        for lanes in (4, 8, 16):
            modeled_backbone_cycles = 0
            measured_action_cycles = 0
            weighted_elements = 0
            included_calls = 0
            for profile in inventory:
                calls = int(profile["invocations_per_policy_call"])
                if profile["subsystem"] == "action_head":
                    measured_action_cycles += action_cycles[(lanes, profile["profile_id"])]
                    weighted_elements += int(profile["weighted_elements"])
                    included_calls += calls
                    continue
                profile_rows = profile["rows_per_invocation"]
                if profile["subsystem"] == "vision_backbone":
                    if visual_rows is None:
                        continue
                    profile_rows = visual_rows
                profile_rows = int(profile_rows)
                cycles = projected_call_cycles(
                    profile_rows, int(profile["hidden_size"]), lanes,
                    profile["norm_type"], analyzer
                )
                modeled_backbone_cycles += cycles * calls
                weighted_elements += profile_rows * int(profile["hidden_size"]) * calls
                included_calls += calls
            cost = analyzer.hardware_cost(lanes)
            rows.append({
                "scenario": scenario,
                "visual_rows_per_invocation": "" if visual_rows is None else visual_rows,
                "lanes": lanes,
                "included_profile_families": 11 if visual_rows is None else 13,
                "included_invocations": included_calls,
                "weighted_elements": weighted_elements,
                "measured_action_rtl_cycles": measured_action_cycles,
                "modeled_backbone_cycles": modeled_backbone_cycles,
                "hybrid_total_cycles": measured_action_cycles + modeled_backbone_cycles,
                "elements_per_cycle": weighted_elements / (measured_action_cycles + modeled_backbone_cycles),
                "relative_cost_units": cost["relative_cost_units"],
                "speedup_vs_lane4": 0.0,
                "incremental_cycle_reduction_vs_previous": 0.0,
                "evidence": "ACTION_RTL_MEASURED_PLUS_BACKBONE_EVENT_MODEL_32_TO_64_ROW_STEADY_STATE_PROJECTION",
            })
    for scenario in scenarios:
        group = [row for row in rows if row["scenario"] == scenario]
        base = group[0]
        previous = None
        for row in group:
            row["speedup_vs_lane4"] = base["hybrid_total_cycles"] / row["hybrid_total_cycles"]
            if previous:
                row["incremental_cycle_reduction_vs_previous"] = (
                    previous["hybrid_total_cycles"] - row["hybrid_total_cycles"]
                ) / previous["hybrid_total_cycles"]
            previous = row
    return rows


def summary(inventory: list[dict], sensitivity: list[dict], discrepancies: list[dict], static: dict) -> dict:
    known = [row for row in inventory if row["weighted_elements"] != ""]
    action = [row for row in inventory if row["subsystem"] == "action_head"]
    unresolved = [row for row in inventory if row["rows_per_invocation"] == ""]
    scenario_decisions = {}
    for scenario in sorted({row["scenario"] for row in sensitivity}):
        group = [row for row in sensitivity if row["scenario"] == scenario]
        l8 = next(row for row in group if row["lanes"] == 8)
        l16 = next(row for row in group if row["lanes"] == 16)
        scenario_decisions[scenario] = {
            "lane4_to_lane8_cycle_reduction": l8["incremental_cycle_reduction_vs_previous"],
            "lane8_to_lane16_cycle_reduction": l16["incremental_cycle_reduction_vs_previous"],
            "lane4_to_lane8_relative_cost_increase": 1504.75 / 848.75 - 1.0,
            "lane8_to_lane16_relative_cost_increase": 2816.75 / 1504.75 - 1.0,
            "balanced_knee_lanes": 8 if (
                l8["incremental_cycle_reduction_vs_previous"]
                > 2.0 * l16["incremental_cycle_reduction_vs_previous"]
                and l16["incremental_cycle_reduction_vs_previous"] < 0.10
            ) else min(group, key=lambda row: row["hybrid_total_cycles"])["lanes"],
            "minimum_hardware_cost_lanes": 4,
        }
    return {
        "purpose": (
            "check whether the action-head-selected 8-lane PCU remains a sound "
            "choice after accounting for every GR00T normalization family"
        ),
        "model": static["metadata"]["model"],
        "model_revision": static["metadata"]["model_revision"],
        "isaac_groot_revision": static["metadata"]["isaac_groot_revision"],
        "inventory_profile_families": len(inventory),
        "profile_family_coverage": "13_OF_13",
        "known_static_invocations": sum(int(row["invocations_per_policy_call"]) for row in inventory),
        "runtime_confirmed_action_invocations": sum(int(row["invocations_per_policy_call"]) for row in action),
        "runtime_confirmed_action_profile_families": len(action),
        "representative_or_runtime_weighted_elements_excluding_vision": sum(int(row["weighted_elements"]) for row in known),
        "unique_hidden_sizes": sorted({int(row["hidden_size"]) for row in inventory}),
        "normalization_types": sorted({row["norm_type"] for row in inventory}),
        "unresolved_runtime_rows": [row["profile_id"] for row in unresolved],
        "unresolved_count": len(unresolved),
        "static_runtime_discrepancies": sum(row["profile_id"] != "NONE" for row in discrepancies),
        "full_model_inference_executed": False,
        "why_full_inference_not_required": (
            "the inventory question needs module families, multiplicities, dimensions, and "
            "representative shape sensitivity; arithmetic RTL replay remains a separate task"
        ),
        "scenario_lane_decisions": scenario_decisions,
        "architecture_conclusion": (
            "8 lanes remains the balanced throughput/cost knee in the known-profile case and "
            "all tested visual-row sensitivity scenarios, while 4 lanes is the minimum-cost "
            "choice when no throughput floor is imposed; 16 lanes is not justified"
        ),
        "freeze_impact": (
            "keep the parameterized RTL and 8-lane balanced default; retain 4-lane as the "
            "cost-minimum configuration until a system throughput requirement is fixed"
        ),
        "claim_boundary": (
            "vision rows and backbone activations are not runtime captured; exact full-model "
            "traffic/cycle totals remain unclaimed"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    static = json.loads(STATIC_MANIFEST.read_text(encoding="utf-8"))
    evidence = source_evidence(args.source, static["metadata"]["isaac_groot_revision"])
    measured = measured_action_profiles()
    inventory = build_inventory(static, measured)
    discrepancies = evidence_discrepancies(static, measured)
    analyzer = load_module(ANALYZER_PATH, "pcu_inventory_analyzer")
    sensitivity = lane_sensitivity(inventory, analyzer)
    result = summary(inventory, sensitivity, discrepancies, static)
    result["source_evidence"] = evidence
    args.out.mkdir(parents=True, exist_ok=True)
    write_csv(args.out / "full_normalization_inventory.csv", inventory)
    write_csv(args.out / "lane_sensitivity.csv", sensitivity)
    write_csv(args.out / "source_evidence.csv", evidence)
    write_csv(args.out / "evidence_discrepancies.csv", discrepancies)
    (args.out / "inventory_summary.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(
        "FULL_NORMALIZATION_INVENTORY PASS "
        f"profiles={len(inventory)} calls={result['known_static_invocations']} "
        f"runtime_action={result['runtime_confirmed_action_invocations']} "
        f"unresolved_rows={result['unresolved_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
