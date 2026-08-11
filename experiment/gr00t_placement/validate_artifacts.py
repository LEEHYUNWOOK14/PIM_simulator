#!/usr/bin/env python3
"""Validate generated pre-RTL placement artifacts and source traceability."""

import csv
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"
METRICS = ("wire", "delay", "thermal", "tsv", "congestion", "power", "area", "reliability")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def collect_source_ids(value):
    found = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "source_ids":
                found.update(child)
            else:
                found.update(collect_source_ids(child))
    elif isinstance(value, list):
        for child in value:
            found.update(collect_source_ids(child))
    return found


def validate():
    assumptions = load_json(ROOT / "assumptions.json")
    sources = load_json(ROOT / "sources.json")
    summary = load_json(RESULTS / "summary.json")
    provisional = load_json(RESULTS / "provisional_placement.json")
    recommendation = load_json(ROOT / "recommendation.json")
    manifest = load_json(RESULTS / "reproduction_manifest.json")

    known_sources = {source["id"] for source in sources["sources"]}
    unknown_sources = collect_source_ids(assumptions) - known_sources
    assert not unknown_sources, "unknown source IDs: {}".format(sorted(unknown_sources))

    with (RESULTS / "candidate_metrics.csv").open(encoding="utf-8", newline="") as stream:
        candidates = list(csv.DictReader(stream))
    assert len(candidates) == summary["candidate_count"]
    for metric in METRICS:
        assert "raw_" + metric in candidates[0]
        assert "norm_" + metric in candidates[0]
    assert sum(row["candidate_constraints_satisfied"] == "True" for row in candidates) == \
        summary["candidate_constraint_feasible_count"]
    assert sum(row["hard_constraints_satisfied"] == "True" for row in candidates) == \
        summary["signoff_hard_constraint_feasible_count"]

    with (RESULTS / "input_assumptions.csv").open(encoding="utf-8", newline="") as stream:
        input_rows = list(csv.DictReader(stream))
    assert input_rows
    assert all(row["unit"] and row["distribution_or_sweep"] and row["source_ids"]
               for row in input_rows)

    with (RESULTS / "weight_sweep.csv").open(encoding="utf-8", newline="") as stream:
        weight_rows = list(csv.DictReader(stream))
    assert len(weight_rows) == summary["weight_sweep_cases"] == 80

    with (RESULTS / "gr00t_scheduler_replay.csv").open(encoding="utf-8", newline="") as stream:
        replay_rows = list(csv.DictReader(stream))
    with (RESULTS / "gr00t_scheduler_replay_base_trace.csv").open(
            encoding="utf-8", newline="") as stream:
        replay_trace = list(csv.DictReader(stream))
    assert [row["scenario"] for row in replay_rows] == ["low", "base", "high"]
    assert len(replay_trace) == 333
    assert all(int(row["total_requests"]) == 333 for row in replay_rows)
    assert all(int(row["total_transfer_bytes"]) == 232939520 for row in replay_rows)
    utilizations = [float(row["service_lane_utilization"]) for row in replay_rows]
    assert utilizations[0] < utilizations[1] < utilizations[2] <= 1.0

    assert provisional["final_recommendation"] is False
    assert recommendation["final_recommendation"] is False
    assert recommendation["signoff_hard_constraint_feasible_count"] == 0
    assert recommendation["robustness_gate"] == summary["robustness_gate"]
    assert summary["final_recommendation_status"].startswith("withheld_")
    assert summary["robustness_gate"]["passed"] is False
    assert summary["signoff_hard_constraint_feasible_count"] == 0
    assert manifest["final_recommendation"] is False

    plot_names = (
        "placement_cost_heatmap", "provisional_temperature_map",
        "top_candidate_components", "pareto_wire_temperature",
        "sensitivity_tornado", "weight_sweep_baseline_rank",
        "monte_carlo_rank_stability", "manufacturing_cost_scenarios",
        "scheduler_replay_utilization",
    )
    for name in plot_names:
        png = RESULTS / (name + ".png")
        svg = RESULTS / (name + ".svg")
        assert png.is_file() and svg.is_file(), name
        width, height = Image.open(png).size
        assert width >= 800 and height >= 500, (name, width, height)

    for report in (ROOT.parent / "report_96_gr00t_pre_rtl_placement_sensitivity.md",
                   ROOT.parent / "report_97_gr00t_placement_uncertainty_and_cost_v2.md"):
        text = report.read_text(encoding="utf-8")
        assert "\ufffd" not in text, report

    return {
        "candidate_count": len(candidates),
        "candidate_constraint_feasible_count": summary["candidate_constraint_feasible_count"],
        "signoff_hard_constraint_feasible_count": summary["signoff_hard_constraint_feasible_count"],
        "input_assumption_count": len(input_rows),
        "weight_sweep_cases": len(weight_rows),
        "scheduler_replay_scenarios": len(replay_rows),
        "scheduler_trace_requests": len(replay_trace),
        "plot_pairs": len(plot_names),
        "final_recommendation": False,
    }


if __name__ == "__main__":
    print(json.dumps(validate(), indent=2))
