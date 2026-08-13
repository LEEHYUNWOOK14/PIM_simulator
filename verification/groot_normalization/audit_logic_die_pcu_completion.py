#!/usr/bin/env python3
"""Requirement-level completion audit for the logic-die PCU goal."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RESULT = ROOT / "reports/groot_normalization/results/logic_die_pcu_system"
REPORT = ROOT / "reports/groot_normalization/logic_die_pcu_system"


def rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def main() -> int:
    required_reports = [
        REPORT / "00_system_objective_reclassification.md",
        REPORT / "01_hierarchical_traffic_and_cycle_model.md",
        REPORT / "02_pcu_top_rtl_and_lane_decision.md",
        REPORT / "03_completion_audit.md",
    ]
    required_sources = [
        ROOT / "tools/analyze_logic_die_pcu_system.py",
        ROOT / "tools/collect_logic_die_pcu_rtl_results.py",
        ROOT / "rtl/logic_die_normalization_pcu_top.sv",
        ROOT / "verification/groot_normalization/groot_logic_die_pcu_trace_tb.sv",
    ]
    missing = [str(path) for path in required_reports + required_sources if not path.exists()]
    assert not missing, f"missing artifacts: {missing}"

    profiles = rows(RESULT / "rtl_profile_results.csv")
    lanes = rows(RESULT / "rtl_lane_decision.csv")
    traffic = rows(RESULT / "hierarchical_traffic.csv")
    decision = json.loads((RESULT / "rtl_candidate_decision.json").read_text(encoding="utf-8"))
    boundaries = {row["boundary"]: int(row["bytes"]) for row in traffic}
    internal = sum(
        boundaries[name]
        for name in (
            "bank_array_reduction_read",
            "bank_array_replay_read",
            "bank_array_affine_read",
            "bank_array_writeback",
        )
    )

    assert len(profiles) == 18
    assert len({(int(row["lanes"]), row["profile_id"]) for row in profiles}) == 18
    assert all(int(row["mixed_mismatches"]) == 0 for row in profiles)
    assert {int(row["lanes"]) for row in lanes} == {4, 8, 16}
    assert all(row["accuracy_gate"] == "PASS" for row in lanes)
    assert all(int(row["weighted_bank_internal_operand_bytes"]) == internal for row in lanes)
    assert len({int(row["weighted_external_bytes"]) for row in lanes}) == 1
    assert decision["recommended_lanes"] == 8
    assert decision["traffic"]["external_io_is_lane_invariant"] is True
    assert decision["traffic"]["external_io_reduction_fraction"] > 0.999

    print(
        "COMPLETION_AUDIT PASS "
        f"profiles={len(profiles)} internal_bytes={internal} "
        f"external_bytes={decision['traffic']['logic_die_pcu_external_bytes']} "
        f"recommended_lanes={decision['recommended_lanes']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
