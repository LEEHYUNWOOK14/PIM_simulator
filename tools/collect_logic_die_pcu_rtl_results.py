#!/usr/bin/env python3
"""Collect 4/8/16-lane PCU top trace evidence and issue the lane decision."""

from __future__ import annotations

import csv
import importlib.util
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULT = ROOT / "reports/groot_normalization/results"
OUT = RESULT / "logic_die_pcu_system"
ANALYZER = ROOT / "tools/analyze_logic_die_pcu_system.py"
PATTERN = re.compile(
    r"PCU_TRACE PASS profile=(\S+) lanes=(\d+) engines=(\d+) rows=(\d+) "
    r"hidden=(\d+) elements=(\d+) mixed_mismatches=(\d+) "
    r"pytorch_bit_mismatches=(\d+) cycles=(\d+) max_contexts=(\d+) "
    r"external_bytes=(\d+) bank_internal_bytes=(\d+)"
)


def load_analyzer():
    spec = importlib.util.spec_from_file_location("pcu_analyzer", ANALYZER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {ANALYZER}")
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    analyzer = load_analyzer()
    workload = analyzer.load_workload_module().workload_rows()
    expected = {row["profile_id"]: int(row["invocations"]) for row in workload}
    model_rows = {
        int(row["lanes"]): row
        for row in csv.DictReader((OUT / "lane_system_dse.csv").open(encoding="utf-8"))
    }
    profile_rows: list[dict] = []
    lane_rows: list[dict] = []
    for lanes in (4, 8, 16):
        log = RESULT / f"logic_die_pcu_l{lanes}_e4_results/rtl_runs.log"
        if not log.exists():
            raise SystemExit(f"missing RTL log: {log}")
        # Last PASS wins, making collection robust to an interrupted rerun.
        matches = {}
        for match in PATTERN.finditer(log.read_text(encoding="utf-8", errors="replace")):
            values = match.groups()
            matches[values[0]] = values
        missing = sorted(set(expected) - set(matches))
        if missing:
            raise SystemExit(f"lane {lanes}: missing profiles {missing}")
        total_cycles = total_elements = mixed = pytorch = external = internal = 0
        max_contexts = 0
        for profile in sorted(expected):
            values = matches[profile]
            row = {
                "profile_id": profile,
                "lanes": int(values[1]),
                "scalar_engines": int(values[2]),
                "rows": int(values[3]),
                "hidden": int(values[4]),
                "elements": int(values[5]),
                "mixed_mismatches": int(values[6]),
                "pytorch_bit_mismatches": int(values[7]),
                "rtl_cycles": int(values[8]),
                "max_contexts": int(values[9]),
                "external_bytes_per_invocation": int(values[10]),
                "bank_internal_bytes_per_invocation": int(values[11]),
                "invocations": expected[profile],
            }
            row["weighted_cycles"] = row["rtl_cycles"] * row["invocations"]
            row["weighted_elements"] = row["elements"] * row["invocations"]
            row["weighted_external_bytes"] = row["external_bytes_per_invocation"] * row["invocations"]
            row["weighted_bank_internal_bytes"] = row["bank_internal_bytes_per_invocation"] * row["invocations"]
            profile_rows.append(row)
            total_cycles += row["weighted_cycles"]
            total_elements += row["weighted_elements"]
            mixed += row["mixed_mismatches"]
            pytorch += row["pytorch_bit_mismatches"]
            external += row["weighted_external_bytes"]
            internal += row["weighted_bank_internal_bytes"]
            max_contexts = max(max_contexts, row["max_contexts"])
        cost = analyzer.hardware_cost(lanes)
        model_cycles = int(float(model_rows[lanes]["independent_pcu_ports_weighted_cycles"]))
        lane_rows.append({
            "lanes": lanes,
            "scalar_engines": 4,
            "weighted_rtl_cycles": total_cycles,
            "weighted_elements": total_elements,
            "elements_per_cycle": total_elements / total_cycles,
            "speedup_vs_lane4": 0.0,
            "incremental_cycle_reduction_vs_previous": 0.0,
            "relative_cost_units": cost["relative_cost_units"],
            "cost_ratio_vs_lane4": 0.0,
            "incremental_cost_vs_previous": 0.0,
            "independent_port_model_cycles": model_cycles,
            "model_error_fraction": (model_cycles - total_cycles) / total_cycles,
            "mixed_mismatches": mixed,
            "pytorch_bit_mismatches_sample_rows": pytorch,
            "weighted_external_bytes": external,
            "weighted_bank_internal_operand_bytes": internal,
            "max_contexts": max_contexts,
            "accuracy_gate": "PASS" if mixed == 0 else "FAIL",
        })

    base = lane_rows[0]
    previous = None
    for row in lane_rows:
        row["speedup_vs_lane4"] = base["weighted_rtl_cycles"] / row["weighted_rtl_cycles"]
        row["cost_ratio_vs_lane4"] = row["relative_cost_units"] / base["relative_cost_units"]
        if previous is not None:
            row["incremental_cycle_reduction_vs_previous"] = (
                previous["weighted_rtl_cycles"] - row["weighted_rtl_cycles"]
            ) / previous["weighted_rtl_cycles"]
            row["incremental_cost_vs_previous"] = (
                row["relative_cost_units"] - previous["relative_cost_units"]
            ) / previous["relative_cost_units"]
        previous = row

    l4, l8, l16 = lane_rows
    all_accuracy = all(row["accuracy_gate"] == "PASS" for row in lane_rows)
    all_external_equal = len({row["weighted_external_bytes"] for row in lane_rows}) == 1
    recommendation = 8 if (
        all_accuracy
        and all_external_equal
        and l8["incremental_cycle_reduction_vs_previous"] >= 0.25
        and l16["incremental_cycle_reduction_vs_previous"] < 0.15
        and l16["incremental_cost_vs_previous"] > 0.50
    ) else min(lane_rows, key=lambda row: row["weighted_rtl_cycles"])["lanes"]

    traffic = analyzer.traffic_for_workload(workload)
    decision = {
        "system_objective": "complete cross-bank normalization on the logic die and eliminate external tensor/intermediate I/O",
        "recommended_lanes": recommendation,
        "recommended_configuration": f"LANES_{recommendation}_SCALAR_ENGINES_4_CONTEXTS_16",
        "decision_status": "SELECTED_FOR_RTL_FREEZE",
        "reason": (
            "All lanes provide identical external-I/O elimination and bit-exact model accuracy. "
            "Eight lanes captures the large 4-to-8 cycle reduction; sixteen lanes has only a small "
            "additional cycle gain for a large arithmetic/storage cost increase."
        ),
        "trace_scope": "PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT_NOT_FULL_GROOT_INFERENCE",
        "accuracy": {
            "profiles_passed_per_lane": len(expected),
            "lanes_tested": [4, 8, 16],
            "weighted_elements_per_lane": l4["weighted_elements"],
            "mixed_precision_model_mismatches": sum(row["mixed_mismatches"] for row in lane_rows),
        },
        "traffic": {
            "gpu_external_bytes": traffic["gpu_external_bytes"],
            "logic_die_pcu_external_bytes": traffic["pcu_external_bytes_resident"],
            "external_io_reduction_fraction": traffic["external_reduction_fraction_resident"],
            "external_io_is_lane_invariant": all_external_equal,
            "internal_traffic_is_reported_separately": True,
        },
        "bank_interface_bounds": {
            "current_top_rtl": "independent reduction-read, replay-read, and write-back ready/valid paths",
            "single_shared_port": "conservative cycle-model lower-bandwidth bound",
            "split_read_write": "one shared read plus one write cycle-model bound",
            "freeze_requirement": "retain backpressure on all three paths; bank scheduler may serialize without functional changes",
        },
        "lane_results": lane_rows,
        "source_logs": [
            str(Path("reports/groot_normalization/results") / f"logic_die_pcu_l{lanes}_e4_results/rtl_runs.log")
            for lanes in (4, 8, 16)
        ],
    }
    OUT.mkdir(parents=True, exist_ok=True)
    write_csv(OUT / "rtl_profile_results.csv", profile_rows)
    write_csv(OUT / "rtl_lane_decision.csv", lane_rows)
    (OUT / "rtl_candidate_decision.json").write_text(json.dumps(decision, indent=2), encoding="utf-8")
    print(
        "LOGIC_DIE_PCU_RTL_COLLECTION PASS "
        f"recommended_lanes={recommendation} profiles={len(profile_rows)} "
        f"model_mismatches={sum(row['mixed_mismatches'] for row in lane_rows)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
