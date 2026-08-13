#!/usr/bin/env python3
"""Independent audit of five adapters, three snapshots, and comparison outputs."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from hardware_cost_adapter_contract import AXES, ROOT, validate_adapter
from hardware_cost_evidence_contract import validate_snapshot


def validate(output_root="output/hardware_cost_adapter_v2", report_path="reports/hardware_cost_adapter_v2"):
    output = Path(output_root) if Path(output_root).is_absolute() else ROOT / output_root
    reports = Path(report_path) if Path(report_path).is_absolute() else ROOT / report_path
    definitions = json.loads((ROOT / "hardware_cost/regression/synthetic_candidate_definitions.json").read_text(encoding="utf-8"))
    expected = [x["id"] for x in definitions["candidates"]]
    checks = []
    def check(name, condition, detail):
        checks.append({"name": name, "pass": bool(condition), "detail": detail})

    adapter_errors, adapter_count = {}, 0
    for candidate in expected:
        for axis in AXES:
            path = output / "adapters" / candidate / f"{axis}.json"
            if not path.is_file():
                adapter_errors[f"{candidate}:{axis}"] = ["missing"]
                continue
            adapter_count += 1
            document = json.loads(path.read_text(encoding="utf-8"))
            adapter_errors[f"{candidate}:{axis}"] = validate_adapter(document)
    check("three candidates and fifteen adapters present", adapter_count == 15 and len(expected) == 3, {"candidates": expected, "adapters": adapter_count})
    check("all adapter schemas, calibration gates, hashes, and conservation rules pass", all(not x for x in adapter_errors.values()), adapter_errors)

    snapshots, snapshot_errors = {}, {}
    for candidate in expected:
        path = output / "revisions" / f"{candidate}.json"
        if path.is_file():
            snapshots[candidate] = json.loads(path.read_text(encoding="utf-8"))
            snapshot_errors[candidate] = validate_snapshot(snapshots[candidate])
        else:
            snapshot_errors[candidate] = ["missing"]
    check("three Evidence Contract v2 snapshots pass", len(snapshots) == 3 and all(not x for x in snapshot_errors.values()), snapshot_errors)
    check("each snapshot retains all five adapter sources", all({x["role"] for x in s["source_files"]} == {f"adapter:{axis}" for axis in AXES} for s in snapshots.values()), "five unique adapter roles per snapshot")
    check("architecture remains provisional", all(s["parameter_status"]["final_architecture_parameters_selected"] is False for s in snapshots.values()), expected)
    check("synthetic power does not produce Energy/op", all(s["workload"]["energy_per_op_J"] is None for s in snapshots.values()), "Energy/op is N/A")

    revision_table = reports / "paper_revision_table.csv"
    delta_table = reports / "paper_delta_table.csv"
    revision_rows = list(csv.DictReader(revision_table.open(newline="", encoding="utf-8"))) if revision_table.is_file() else []
    delta_rows = {x["revision"]: x for x in csv.DictReader(delta_table.open(newline="", encoding="utf-8"))} if delta_table.is_file() else {}
    check("comparison covers all three candidates", {x["revision"] for x in revision_rows} == set(expected), [x.get("revision") for x in revision_rows])
    required_axes = ("mapped_area_um2", "critical_path_ns", "total_power_W", "throughput_ops_s", "peak_temperature_K")
    check("comparison table exposes all five axes", all(all(row.get(key) not in (None, "") for key in required_axes) for row in revision_rows), required_axes)
    balanced = delta_rows.get("synthetic_balanced", {})
    expected_deltas = {"area_vs_baseline_pct": 25.0, "critical_path_vs_baseline_pct": -25.0, "throughput_vs_baseline_pct": 80.0}
    delta_ok = all(key in balanced and math.isclose(float(balanced[key]), value, abs_tol=1e-9) for key, value in expected_deltas.items())
    check("known synthetic deltas reproduced", delta_ok, {key: balanced.get(key) for key in expected_deltas})
    check("Energy/op comparison is unavailable", balanced.get("energy_vs_baseline_pct", "") == "" and balanced.get("energy_vs_baseline_policy") == "unavailable", {"value": balanced.get("energy_vs_baseline_pct"), "policy": balanced.get("energy_vs_baseline_policy")})
    required_outputs = ("paper_revision_table.csv", "paper_category_table.csv", "paper_delta_table.csv", "paper_regression_report.md", "paper_revision_overview.png", "paper_category_power.png", "paper_timing_throughput.png", "regression_summary.json", "validation_report.json")
    check("all comparison and validation artifacts exist", all((reports / name).is_file() and (reports / name).stat().st_size > 0 for name in required_outputs), required_outputs)

    report = {"status": "PASS" if all(x["pass"] for x in checks) else "FAIL", "checks": checks, "scope": "Synthetic five-adapter integration and comparison plumbing; no physical or architecture signoff."}
    reports.mkdir(parents=True, exist_ok=True)
    (reports / "adapter_validation_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    lines = ["# Hardware-cost adapter v2 validation", "", f"Status: **{report['status']}**", "", "|Check|Pass|Detail|", "|---|---|---|"]
    lines.extend(f"|{item['name']}|{item['pass']}|`{str(item['detail'])[:500]}`|" for item in checks)
    (reports / "adapter_validation_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="output/hardware_cost_adapter_v2")
    parser.add_argument("--report", default="reports/hardware_cost_adapter_v2")
    args = parser.parse_args()
    return 0 if validate(args.output, args.report)["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
