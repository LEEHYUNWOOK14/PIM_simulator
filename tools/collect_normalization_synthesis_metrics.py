#!/usr/bin/env python3
"""Collect workload-independent Yosys cell/path evidence for normalization RTL."""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "reports" / "groot_normalization" / "results"
OUTPUT = RESULTS / "normalization_synthesis_metrics.csv"


def metrics(log: Path) -> tuple[int, int]:
    text = log.read_text(encoding="utf-8", errors="replace")
    if "Found and reported 0 problems." not in text or "End of script." not in text:
        raise RuntimeError(f"incomplete or failing synthesis evidence: {log}")
    sections = text.split("=== design hierarchy ===")
    cell = re.search(r"Number of cells:\s+(\d+)", sections[-1])
    paths = re.findall(r"Longest topological path.*?\(length=(\d+)\)", text)
    if not cell or not paths:
        raise RuntimeError(f"missing cell/path metric: {log}")
    return int(cell.group(1)), int(paths[-1])


def main() -> None:
    rows: list[dict[str, object]] = []
    for architecture, prefix, lanes in (
        ("combinational_tree", "bank_vector_reducer", (1, 2, 4, 8, 16)),
        ("pipelined_tree", "bank_pipelined_vector_reducer", (2, 4, 8, 16)),
    ):
        for data_format, suffix in (("FP16", ""), ("BF16", "_bf16")):
            for lane in lanes:
                log = RESULTS / f"{prefix}_l{lane}{suffix}_yosys.log"
                cells, path = metrics(log)
                rows.append({
                    "architecture": architecture,
                    "data_format": data_format,
                    "lanes": lane,
                    "generic_cells": cells,
                    "generic_path_length": path,
                    "technology_mapped_area_um2": "",
                    "critical_path_ns": "",
                    "slack_ns": "",
                    "evidence": "YOSYS_GENERIC_NOT_TIMING",
                    "log": log.relative_to(ROOT).as_posix(),
                })
    with OUTPUT.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"NORMALIZATION_SYNTHESIS_METRICS PASS rows={len(rows)} output={OUTPUT}")


if __name__ == "__main__":
    main()
