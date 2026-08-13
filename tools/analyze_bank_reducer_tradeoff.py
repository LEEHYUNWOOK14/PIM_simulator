#!/usr/bin/env python3
"""Combine measured vector-reducer generic cells with the GR00T cycle model."""

from __future__ import annotations

import csv
import math
import re
from pathlib import Path

from groot_normalization_model import (
    cycles_to_ns,
    load_parameters,
    load_profiles,
    model_profile,
)

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "reports" / "groot_normalization" / "results"


def measured_synthesis(lanes: int, pipelined: bool = False) -> tuple[int, int]:
    prefix = "bank_pipelined_vector_reducer" if pipelined else "bank_vector_reducer"
    log = RESULTS / f"{prefix}_l{lanes}_yosys.log"
    text = log.read_text(encoding="utf-8", errors="replace")
    sections = text.split("=== design hierarchy ===")
    if len(sections) < 2 or "Found and reported 0 problems." not in text:
        raise RuntimeError(f"missing clean synthesis evidence: {log}")
    match = re.search(r"Number of cells:\s+(\d+)", sections[-1])
    if not match:
        raise RuntimeError(f"cell count not found: {log}")
    path_matches = re.findall(r"Longest topological path.*?\(length=(\d+)\)", text)
    if not path_matches:
        raise RuntimeError(f"logic path not found: {log}")
    return int(match.group(1)), int(path_matches[-1])


def projected_ms(case: str, lanes: int, profiles, ref: dict, pipeline_levels: int = 0,
                 overlap_rows: bool = False) -> float:
    total_ns = 0.0
    banks = int(ref["banks"])
    clock = float(ref["clock_mhz"])
    for profile in profiles:
        row = model_profile(profile, case, ref)
        old_local = float(row["local_reduce_ns"])
        # Rows cannot be packed into one vector transaction. A pipelined tree
        # additionally drains once per row because the current RTL holds one context.
        vectors_per_row = math.ceil(profile.hidden_size / (banks * lanes))
        new_cycles = profile.rows * vectors_per_row + (
            pipeline_levels if overlap_rows else profile.rows * pipeline_levels
        )
        new_local = cycles_to_ns(new_cycles, clock)
        per_call = float(row["latency_ns_per_call"]) - old_local + new_local
        total_ns += per_call * profile.invocations
    return total_ns / 1.0e6


def main() -> None:
    profiles = load_profiles()
    params = load_parameters()
    ref = params["reference_point"]
    banks = int(ref["banks"])
    if int(ref.get("logic_partial_input_ports", 1)) == 1:
        logic_array = params["rtl_measurements"]["logic_normalization_dispatcher"]
        logic_cells = dict(zip(logic_array["engines"],
                               logic_array["generic_cells_with_dispatcher"]))[
            int(ref["logic_pcus"])
        ]
    else:
        logic_array = params["rtl_measurements"]["logic_normalization_engine_array"]
        logic_cells = dict(zip(logic_array["engines"], logic_array["generic_cells"]))[
            int(ref["logic_pcus"])
        ]
    scalar_cells = int(params["rtl_measurements"]["bank_local_scalar_reducer_generic_cells_per_bank"]["value"])
    fixed = {}
    for case in ("gpu_full", "logic_only"):
        fixed[case] = sum(
            float(model_profile(p, case, ref)["projected_latency_ns"]) for p in profiles
        ) / 1.0e6
    rows = []
    scalar_hier = projected_ms("hierarchical", 1, profiles, ref)
    for lanes in (1, 2, 4, 8, 16):
        cells, path_length = measured_synthesis(lanes)
        pipe_cells, pipe_path_length = measured_synthesis(lanes, True) if lanes >= 2 else (0, 0)
        bank_ms = projected_ms("bank_only", lanes, profiles, ref)
        hier_ms = projected_ms("hierarchical", lanes, profiles, ref)
        pipe_hier_ms = (projected_ms("hierarchical", lanes, profiles, ref, int(math.log2(lanes)))
                        if lanes >= 2 else hier_ms)
        overlap_hier_ms = (projected_ms("hierarchical", lanes, profiles, ref,
                                        int(math.log2(lanes)), True)
                           if lanes == 4 else None)
        candidates = {
            "gpu_full": fixed["gpu_full"], "logic_only": fixed["logic_only"],
            "bank_only": bank_ms, "hierarchical": hier_ms,
        }
        pipelined_candidates = dict(candidates, hierarchical=pipe_hier_ms)
        rows.append({
            "lanes_per_bank": lanes,
            "elements_per_cycle_per_bank": lanes,
            "generic_cells_per_bank": cells,
            "generic_logic_path_length": path_length,
            "pipelined_generic_cells_per_bank": pipe_cells or None,
            "pipelined_generic_logic_path_length": pipe_path_length or None,
            "pipelined_latency_from_last_cycles": int(math.log2(lanes)) + 1 if lanes >= 2 else None,
            "generic_cells_16banks": cells * banks,
            "hierarchical_generic_cells_proxy": cells * banks + logic_cells,
            "area_multiplier_vs_scalar_reducer": round(cells / scalar_cells, 6),
            "throughput_per_1000_cells": round(lanes * 1000.0 / cells, 9),
            "bank_only_projected_ms": round(bank_ms, 6),
            "hierarchical_projected_ms": round(hier_ms, 6),
            "pipelined_hierarchical_projected_ms": round(pipe_hier_ms, 6),
            "multirow_pipelined_hierarchical_projected_ms": (
                round(overlap_hier_ms, 6) if overlap_hier_ms is not None else None),
            "hierarchical_speedup_vs_scalar": round(scalar_hier / hier_ms, 6),
            "logic_only_projected_ms": round(fixed["logic_only"], 6),
            "gpu_full_projected_ms": round(fixed["gpu_full"], 6),
            "overall_latency_winner": min(candidates, key=candidates.get),
            "pipelined_overall_latency_winner": min(pipelined_candidates,
                                                       key=pipelined_candidates.get),
            "cell_evidence": "RTL_MEASURED_GENERIC_SYNTHESIS",
            "latency_evidence": "RTL_THROUGHPUT_CALIBRATED_ANALYTICAL",
        })
    output = RESULTS / "bank_vector_reducer_tradeoff.csv"
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    assert all(row["generic_cells_per_bank"] > 0 for row in rows)
    assert all(rows[i]["hierarchical_projected_ms"] > rows[i+1]["hierarchical_projected_ms"]
               for i in range(len(rows)-1))
    print(f"BANK_REDUCER_TRADEOFF PASS rows={len(rows)} output={output}")


if __name__ == "__main__":
    main()
