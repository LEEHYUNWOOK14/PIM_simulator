#!/usr/bin/env python3
"""Validate the final HTML, manifest, tables, relative links, and key artifacts."""
from html.parser import HTMLParser
import json
import re
from pathlib import Path

exp = Path(__file__).resolve().parent
report = exp / "b1_logic_die_experiment_report.html"
source = report.read_text(encoding="utf-8")
HTMLParser().feed(source)
manifest = json.loads((exp / "b1_baseline_manifest.json").read_text(encoding="utf-8"))
assert manifest["overall_disposition"] == "NOT_APPROVED"
assert len(manifest["gates"]) == 10
assert source.count("<h2>") == 9
links = re.findall(r'href="([^"]+)"', source)
missing = [link for link in links if not (exp / link).exists()]
assert not missing, f"missing report links: {missing}"
for required in (
    "metrics/hash_manifest.csv",
    "metrics/b1_gate_results.csv",
    "metrics/b1_synthesis_timing.csv",
    "metrics/b1_physical_metrics.csv",
    "metrics/b1_power_performance.csv",
    "artifacts/B1_generic.v",
    "orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.odb",
):
    assert (exp / required).is_file(), required
assert not (exp / "orfs/results/sky130hd/b1_logic_die_baseline/base/5_2_route.odb").exists()
print(f"VERIFY_PASS: {len(manifest['gates'])} gates, {len(links)} links, {report.stat().st_size} bytes")
