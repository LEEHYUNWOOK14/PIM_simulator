#!/usr/bin/env python3
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "reports/groot_normalization/hbm_boundary_adapter"

expected_hbm = {
    (0, 128): dict(wall=523, adapter=521, act=16, read=48, write=16, pre=16, wait=166),
    (0, 2048): dict(wall=3509, adapter=3507, act=16, read=512, write=128, pre=16, wait=1056),
    (1, 128): dict(wall=511, adapter=509, act=16, read=48, write=16, pre=16, wait=166),
    (1, 2048): dict(wall=3497, adapter=3495, act=16, read=512, write=128, pre=16, wait=1056),
}
expected_abstract = {(0, 128): 130, (0, 2048): 167, (1, 128): 118, (1, 2048): 155}

checks = []


def record(name, passed, evidence):
    checks.append({"requirement": name, "status": "PASS" if passed else "FAIL", "evidence": evidence})


required = [
    ROOT / "rtl/normalization_hbm_boundary_adapter.sv",
    ROOT / "verification/groot_normalization/normalization_hbm_boundary_integration_tb.sv",
    REPORT / "01_command_credit_and_mapping.md",
    REPORT / "02_cycle_comparison.csv",
    REPORT / "03_validation_and_decision_report.md",
    REPORT / "04_adapter_queue_arbitration_assessment.md",
    REPORT / "05_completion_audit.md",
    REPORT / "hbm_boundary_regression.log",
    REPORT / "abstract_pcu_regression.log",
    REPORT / "yosys_adapter_check.log",
]
missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file() or path.stat().st_size == 0]
record("required artifacts", not missing, "all present" if not missing else f"missing={missing}")

hbm_text = (REPORT / "hbm_boundary_regression.log").read_text(encoding="utf-8", errors="replace")
hbm_pattern = re.compile(
    r"PASS width=(\d+) rms=(\d+) vectors=\d+ wall_cycles=(\d+) adapter_cycles=(\d+) "
    r"act=(\d+) read=(\d+) write=(\d+) pre=(\d+) wait=(\d+) "
    r"read_credit_peak=(\d+) read_credit_final=(\d+) timing_errors=(\d+)"
)
hbm_seen = {}
for match in hbm_pattern.finditer(hbm_text):
    width, rms, wall, adapter, act, read, write, pre, wait, peak, final, timing = map(int, match.groups())
    hbm_seen[(rms, width)] = dict(
        wall=wall, adapter=adapter, act=act, read=read, write=write,
        pre=pre, wait=wait, peak=peak, final=final, timing=timing,
    )
hbm_ok = set(hbm_seen) == set(expected_hbm)
for key, expected in expected_hbm.items():
    got = hbm_seen.get(key, {})
    hbm_ok &= all(got.get(field) == value for field, value in expected.items())
    hbm_ok &= got.get("peak") == 1 and got.get("final") == 0 and got.get("timing") == 0
record("timing-and-credit RTL integration", hbm_ok, {str(key): value for key, value in hbm_seen.items()})

abstract_text = (REPORT / "abstract_pcu_regression.log").read_text(encoding="utf-8", errors="replace")
abstract_pattern = re.compile(r"PASS lanes=8 rms=(\d+) width=(\d+) vectors=\d+ cycles=(\d+)")
abstract_seen = {(int(rms), int(width)): int(cycles) for rms, width, cycles in abstract_pattern.findall(abstract_text)}
record("abstract PCU cycle baseline", abstract_seen == expected_abstract, {str(key): value for key, value in abstract_seen.items()})

csv_rows = list(csv.DictReader((REPORT / "02_cycle_comparison.csv").open(encoding="utf-8")))
csv_seen = {}
for row in csv_rows:
    rms = 1 if row["mode"] == "RMSNorm" else 0
    csv_seen[(rms, int(row["hidden"]))] = (int(row["abstract_pcu_cycles"]), int(row["hbm_connected_cycles"]))
expected_csv = {key: (expected_abstract[key], expected_hbm[key]["wall"]) for key in expected_hbm}
record("abstract-versus-HBM cycle comparison", csv_seen == expected_csv, {str(key): value for key, value in csv_seen.items()})

yosys_text = (REPORT / "yosys_adapter_check.log").read_text(encoding="utf-8", errors="replace")
record(
    "adapter synthesizability",
    "Found and reported 0 problems." in yosys_text and "Number of cells:" in yosys_text,
    "Yosys check=0 problems and statistics emitted",
)

rtl_text = (ROOT / "rtl/normalization_hbm_boundary_adapter.sv").read_text(encoding="utf-8")
mapping_markers = ["DRAM_CMD_ACT", "DRAM_CMD_RD", "DRAM_CMD_WR", "DRAM_CMD_PRE", "x_base_q", "affine_base_q", "output_base_q"]
record("PCU-to-command RTL mapping", all(marker in rtl_text for marker in mapping_markers), mapping_markers)

optimization_text = (REPORT / "04_adapter_queue_arbitration_assessment.md").read_text(encoding="utf-8")
record(
    "queue/arbitration optimization decision",
    all(term in optimization_text for term in ["read queue depth 1", "credit 1", "x word slice reuse", "output coalescing"]),
    "credit-limited queue decision and accepted command-reduction optimizations documented",
)

decision_text = (REPORT / "03_validation_and_decision_report.md").read_text(encoding="utf-8")
record(
    "post-supply-floor PCU scheduler review",
    all(term in decision_text for term in ["공급률 하한", "8 lanes / 4 scalar engines / split-RW / contexts 8", "freeze는 유지"]),
    "scheduler reviewed after connected supply result; freeze retained with rationale",
)

passed = all(item["status"] == "PASS" for item in checks)
result = {"status": "PASS" if passed else "FAIL", "checks": checks}
print(json.dumps(result, ensure_ascii=False, indent=2, default=lambda value: str(value)))
raise SystemExit(0 if passed else 1)
