#!/usr/bin/env python3
"""Collect generic synthesis size and logic-depth metrics for mixed RTL."""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "reports/groot_normalization/results/mixed_precision_synthesis"
OUT = LOGS / "mixed_precision_synthesis_metrics.csv"
TOPS = (
    "fp32_add", "fp32_mul", "fp32_to_bf16_rne", "fp32_add_pipe4", "mixed_precision_bank_reducer4", "mixed_precision_bank_reducer4_interleaved",
    "mixed_precision_global_reducer16", "mixed_precision_global_reducer16_pipe", "mixed_precision_scalar_nr2",
    "mixed_precision_bank_apply4", "mixed_precision_normalization_datapath",
)


def section(text: str, top: str) -> str:
    matches = list(re.finditer(rf"=== {re.escape(top)} ===\n(.*?)(?=\n=== |\Z)", text, re.S))
    if not matches:
        raise RuntimeError(f"missing stat section {top}")
    return matches[-1].group(1)


def integer(block: str, label: str) -> int:
    match = re.search(rf"{re.escape(label)}:\s+(\d+)", block)
    if not match:
        raise RuntimeError(f"missing {label}")
    return int(match.group(1))


def main() -> int:
    rows=[]
    for top in TOPS:
        path=LOGS/f"{top}_yosys.log";text=path.read_text(encoding="utf-8",errors="replace")
        try:block=section(text,"design hierarchy")
        except RuntimeError:block=section(text,top)
        depths=[int(value) for value in re.findall(rf"Longest topological path in {re.escape(top)} \(length=(\d+)\)",text)]
        rows.append({
            "top":top,"generic_cells":integer(block,"Number of cells"),"wires":integer(block,"Number of wires"),
            "wire_bits":integer(block,"Number of wire bits"),"longest_topological_path_cells":depths[-1] if depths else "NOT_RUN_FOR_FULL_TOP",
            "synthesis_status":"YOSYS_CHECK_ASSERT_PASS","physical_area":"UNAVAILABLE_GENERIC_CELLS_ONLY","source":path.relative_to(ROOT).as_posix(),
        })
    with OUT.open("w",newline="",encoding="utf-8") as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    (LOGS/"mixed_precision_synthesis_metrics.json").write_text(json.dumps({"metrics":rows,"warning":"Generic cells and topological cell count are not mapped area or STA."},indent=2),encoding="utf-8")
    print(f"MIXED_PRECISION_SYNTHESIS_METRICS PASS tops={len(rows)} full_top_cells={rows[-1]['generic_cells']}")
    return 0


if __name__=="__main__":raise SystemExit(main())
