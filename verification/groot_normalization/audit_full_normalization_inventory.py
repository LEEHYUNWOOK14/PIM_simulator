#!/usr/bin/env python3
"""Requirement-level audit for the full normalization workload inventory."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "reports/groot_normalization/results/full_normalization_inventory"
REPORT = ROOT / "reports/groot_normalization/full_normalization_inventory/01_full_normalization_workload_inventory_report.md"


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUT / name).open(encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def main() -> int:
    inventory = read_csv("full_normalization_inventory.csv")
    sensitivity = read_csv("lane_sensitivity.csv")
    evidence = read_csv("source_evidence.csv")
    discrepancies = read_csv("evidence_discrepancies.csv")
    summary = json.loads((OUT / "inventory_summary.json").read_text(encoding="utf-8"))
    report = REPORT.read_text(encoding="utf-8")

    assert len(inventory) == 13
    assert len({row["profile_id"] for row in inventory}) == 13
    assert sum(int(row["invocations_per_policy_call"]) for row in inventory) == 382
    assert sum(
        int(row["invocations_per_policy_call"])
        for row in inventory if row["subsystem"] == "action_head"
    ) == 269
    assert {int(row["hidden_size"]) for row in inventory} == {128, 1024, 1536, 2048}
    assert {row["norm_type"] for row in inventory} == {"LayerNorm", "RMSNorm", "AdaLayerNorm"}
    assert {
        row["profile_id"] for row in inventory if not row["rows_per_invocation"]
    } == {"backbone_visual_block_norm1", "backbone_visual_block_norm2"}
    assert len(sensitivity) == 12
    scenarios = {row["scenario"] for row in sensitivity}
    assert scenarios == {
        "known_profiles_no_vision", "vision_rows_256", "vision_rows_1024", "vision_rows_4096"
    }
    assert all(
        value["balanced_knee_lanes"] == 8 and value["minimum_hardware_cost_lanes"] == 4
        for value in summary["scenario_lane_decisions"].values()
    )
    assert len(evidence) == 4
    assert all(row["status"] == "PINNED_SOURCE_RECHECKED" for row in evidence)
    actual_discrepancies = [row for row in discrepancies if row["profile_id"] != "NONE"]
    assert len(actual_discrepancies) == 1
    assert actual_discrepancies[0]["profile_id"] == "action_dit_norm3"
    assert actual_discrepancies[0]["field"] == "elementwise_affine"
    assert "## 1. 왜 이 작업을 수행했는가" in report
    assert "## 2. “전체 normalization workload inventory 확인”의 구체 작업" in report
    assert "원격 checkpoint header" in report
    assert "8-lane" in report and "4-lane" in report and "16-lane" in report

    print(
        "FULL_NORMALIZATION_INVENTORY_AUDIT PASS "
        f"profiles={len(inventory)} calls={summary['known_static_invocations']} "
        f"scenarios={len(scenarios)} discrepancies={len(actual_discrepancies)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
