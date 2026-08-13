#!/usr/bin/env python3
"""Integrate physical, thermal, and existing hardware-cost evidence by candidate."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rows(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as stream: return list(csv.DictReader(stream))


def keyed(path: Path) -> dict[str, dict]: return {row["strategy"]: row for row in rows(path)}


def number(row: dict, key: str) -> float: return float(row[key])


def dominates(a: dict, b: dict, keys: tuple[str, ...]) -> bool:
    return all(a[key] <= b[key] + 1e-12 for key in keys) and any(a[key] < b[key] - 1e-12 for key in keys)


def compare(output_dir: str = "output/floorplan_optimization") -> list[dict]:
    output = ROOT / output_dir
    selected = keyed(output / "exploration/selected_candidates.csv")
    physical = keyed(output / "openroad_proxy/openroad_proxy_metrics.csv")
    thermal = keyed(output / "thermal_results.csv")
    hotspot = keyed(output / "hotspot_results.csv")
    threedice = keyed(output / "3dice_results.csv")
    strategies = ["manual_baseline", "wirelength_first", "thermal_first", "balanced", "cost_first"]
    if any(set(source) != set(strategies) for source in (selected, physical, thermal, hotspot, threedice)):
        raise RuntimeError("candidate sets differ across evidence sources")
    manifest = json.loads((ROOT / selected["manual_baseline"]["manifest"]).read_text(encoding="utf-8"))
    die_area = float(manifest["die"]["width_um"]) * float(manifest["die"]["height_um"]) / 1e6
    block_area = sum(float(block["width_um"]) * float(block["height_um"]) for block in manifest["blocks"]) / 1e6
    tsv_count = sum(int(bundle["rows"]) * int(bundle["columns"]) for bundle in manifest["tsv_bundles"])
    bump_count = sum(int(bundle["rows"]) * int(bundle["columns"]) for bundle in manifest["micro_bump_bundles"])
    baseline_wire = number(physical["manual_baseline"], "global_route_wirelength_um")
    max_overflow = max(number(row, "global_route_overflow_sum") for row in physical.values())
    # Existing HBM2 8Hi cost revision is constant across coordinate-only candidates.
    cost_revision = rows(ROOT / "output/hbm2_hardware_cost/design_comparison.csv")
    base_cost = next(row for row in cost_revision if row["scenario"] == "hbm2_8hi_1stack")
    integrated = []
    for strategy in strategies:
        s, p, t, h, d = selected[strategy], physical[strategy], thermal[strategy], hotspot[strategy], threedice[strategy]
        wire_index = number(p, "global_route_wirelength_um") / baseline_wire
        overflow_index = 1.0 + number(p, "global_route_overflow_sum") / max_overflow if max_overflow else 1.0
        candidate_cost = 0.80 * float(base_cost["combined_cost_index"]) + 0.15 * wire_index + 0.05 * overflow_index
        integrated.append({
            "strategy": strategy, "candidate_id": s["candidate_id"], "provisional": "YES",
            "die_area_mm2": die_area, "conceptual_block_area_mm2": block_area,
            "tsv_count": tsv_count, "micro_bump_count": bump_count,
            "tsv_keepout_lost_area_mm2": number(s, "keepout_lost_area_um2") / 1e6,
            "routing_corridor_area_mm2": number(s, "routing_corridor_area_um2") / 1e6,
            "analytical_wirelength_um": number(s, "traffic_weighted_manhattan_um"),
            "openroad_global_route_wirelength_um": number(p, "global_route_wirelength_um"),
            "global_route_overflow_sum": number(p, "global_route_overflow_sum"),
            "reference_peak_temperature_C": number(t, "peak_temperature_C"),
            "reference_max_gradient_K_per_mm": number(t, "max_logic_gradient_K_per_mm"),
            "hotspot_2d_peak_temperature_C": number(h, "peak_temperature_C"),
            "three_dice_peak_temperature_C": number(d, "peak_temperature_C"),
            "base_hbm2_8hi_cost_index": float(base_cost["combined_cost_index"]),
            "candidate_structural_cost_proxy": candidate_cost,
            "cost_formula": "0.80*fixed_HBM_cost+0.15*route_WL/manual+0.05*(1+overflow/max_overflow)",
            "timing": p["setup_wns_ns"], "static_ir_drop": p["static_ir_drop_mV"],
            "physical_evidence": p["evidence_class"], "thermal_evidence": t["evidence_class"],
            "cost_evidence": "estimated_normalized_proxy_not_vendor_price", "signoff": "NO",
        })
    pareto_keys = ("reference_peak_temperature_C", "openroad_global_route_wirelength_um", "global_route_overflow_sum", "candidate_structural_cost_proxy")
    for candidate in integrated:
        candidate["physical_thermal_cost_pareto"] = not any(dominates(other, candidate, pareto_keys) for other in integrated if other is not candidate)
    with (output / "candidate_comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=integrated[0]); writer.writeheader(); writer.writerows(integrated)
    pareto = [row for row in integrated if row["physical_thermal_cost_pareto"]]
    with (output / "cost_thermal_pareto.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=integrated[0]); writer.writeheader(); writer.writerows(pareto)
    sensitivity = []
    for fixed_weight in (0.70, 0.80, 0.90):
        for overflow_weight in (0.0, 0.05, 0.10):
            route_weight = 1.0 - fixed_weight - overflow_weight
            scores = {}
            for strategy in strategies:
                p = physical[strategy]
                scores[strategy] = fixed_weight + route_weight * number(p, "global_route_wirelength_um") / baseline_wire + overflow_weight * (1 + number(p, "global_route_overflow_sum") / max_overflow)
            winner = min(scores, key=scores.get)
            sensitivity.append({"fixed_cost_weight": fixed_weight, "route_weight": route_weight, "overflow_weight": overflow_weight, "winner": winner, "winner_score": scores[winner]})
    with (output / "cost_weight_sensitivity.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=sensitivity[0]); writer.writeheader(); writer.writerows(sensitivity)
    print(f"FLOORPLAN_CANDIDATE_COMPARISON PASS candidates={len(integrated)} pareto={len(pareto)}")
    return integrated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--output-dir", default="output/floorplan_optimization")
    args = parser.parse_args(); compare(args.output_dir); return 0


if __name__ == "__main__": raise SystemExit(main())
