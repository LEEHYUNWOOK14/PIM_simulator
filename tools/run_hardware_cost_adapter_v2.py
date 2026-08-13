#!/usr/bin/env python3
"""Run the three-candidate, five-adapter Evidence Contract v2 comparison."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import compare_hardware_cost_revisions as compare
from generate_synthetic_hardware_cost_adapters import generate
from hardware_cost_adapter_contract import AXES, ROOT, build_snapshot


def run(output_root="output/hardware_cost_adapter_v2", report_path="reports/hardware_cost_adapter_v2"):
    output = Path(output_root) if Path(output_root).is_absolute() else ROOT / output_root
    reports = Path(report_path) if Path(report_path).is_absolute() else ROOT / report_path
    adapters_dir, revisions_dir = output / "adapters", output / "revisions"
    generate(output_path=str(adapters_dir))
    definitions = json.loads((ROOT / "hardware_cost" / "regression" / "synthetic_candidate_definitions.json").read_text(encoding="utf-8"))
    revisions_dir.mkdir(parents=True, exist_ok=True)
    for candidate in definitions["candidates"]:
        paths = [adapters_dir / candidate["id"] / f"{axis}.json" for axis in AXES]
        build_snapshot(paths, candidate["captured_at"], revisions_dir / f"{candidate['id']}.json")
    summary = compare.compare(str(revisions_dir), "synthetic_low_area", str(reports))
    print(f"HARDWARE_COST_ADAPTER_V2 PASS candidates={summary['revision_count']} report={reports}")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="output/hardware_cost_adapter_v2")
    parser.add_argument("--report", default="reports/hardware_cost_adapter_v2")
    args = parser.parse_args()
    run(args.output, args.report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
