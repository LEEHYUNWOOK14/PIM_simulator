#!/usr/bin/env python3
"""Generate deterministic legal floorplans and rank proxy metrics without changing RTL."""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import math
import random
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np

import validate_logic_die_floorplan as validation

ROOT = Path(__file__).resolve().parents[1]
CHANNEL_RE = re.compile(r"dram\.channel\[(\d+)]")


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def load(path: str | Path) -> dict[str, Any]:
    return json.loads(absolute(path).read_text(encoding="utf-8-sig"))


def center(block: dict[str, Any]) -> tuple[float, float]:
    return float(block["x_um"]) + float(block["width_um"]) / 2, float(block["y_um"]) + float(block["height_um"]) / 2


def bundle_center(bundle: dict[str, Any]) -> tuple[float, float]:
    return (
        float(bundle["x_um"]) + (int(bundle["columns"]) - 1) * float(bundle["pitch_um"]) / 2,
        float(bundle["y_um"]) + (int(bundle["rows"]) - 1) * float(bundle["pitch_um"]) / 2,
    )


def hard_violations(doc: dict[str, Any]) -> list[str]:
    violations: list[str] = []
    die = validation.rectangle(doc["die"])
    block_rects: list[tuple[str, tuple[float, float, float, float]]] = []
    for block in doc["blocks"]:
        rect = validation.rectangle(block, float(block["halo_um"]))
        if not validation.contained(rect, die):
            violations.append(f"die_boundary:{block['instance']}")
        if block["allowed_region"] and not validation.contained(validation.rectangle(block), validation.rectangle(block["allowed_region"])):
            violations.append(f"allowed_region:{block['instance']}")
        block_rects.append((block["instance"], rect))
    for left in range(len(block_rects)):
        for right in range(left + 1, len(block_rects)):
            if validation.overlaps(block_rects[left][1], block_rects[right][1]):
                violations.append(f"block_overlap:{block_rects[left][0]}:{block_rects[right][0]}")
    for region in doc["reserved_regions"]:
        if region["blocks_prohibited"]:
            for name, rect in block_rects:
                if validation.overlaps(rect, validation.rectangle(region)):
                    violations.append(f"reserved_region:{name}:{region['region_id']}")
    for bundle in doc["tsv_bundles"]:
        radius = float(bundle["diameter_um"]) / 2 + float(bundle["keepout_um"])
        for x, y in validation.bundle_points(bundle):
            for name, rect in block_rects:
                if validation.circle_hits_rect(x, y, radius, rect):
                    violations.append(f"tsv_keepout:{name}:{bundle['bundle_id']}")
                    break
    return sorted(set(violations))


def endpoint_centers(doc: dict[str, Any], signal_class: str = "data") -> dict[int, tuple[float, float]]:
    result = {}
    for bundle in doc["tsv_bundles"]:
        if bundle["signal_class"] != signal_class:
            continue
        match = CHANNEL_RE.fullmatch(bundle["source"])
        if match:
            result[int(match.group(1))] = bundle_center(bundle)
    return result


def route_congestion_proxy(routes: list[tuple[tuple[float, float], tuple[float, float], float]], die_w: float, die_h: float) -> float:
    demand: dict[tuple[int, int], float] = defaultdict(float)
    nx, ny = 16, 24
    for (x0, y0), (x1, y1), weight in routes:
        samples = max(2, int((abs(x1 - x0) + abs(y1 - y0)) / 250.0))
        for index in range(samples + 1):
            fraction = index / samples
            if fraction <= 0.5:
                x, y = x0 + (x1 - x0) * fraction * 2, y0
            else:
                x, y = x1, y0 + (y1 - y0) * (fraction - 0.5) * 2
            gx = min(nx - 1, max(0, int(x / die_w * nx)))
            gy = min(ny - 1, max(0, int(y / die_h * ny)))
            demand[(gx, gy)] += weight / (samples + 1)
    return max(demand.values(), default=0.0)


def metrics(doc: dict[str, Any]) -> dict[str, float]:
    data = endpoint_centers(doc, "data")
    power_tsv = list(endpoint_centers(doc, "power").values())
    die_w, die_h = float(doc["die"]["width_um"]), float(doc["die"]["height_um"])
    weighted_wire = 0.0
    access_distances: list[float] = []
    timing_proxy = 0.0
    ir_proxy = 0.0
    routes = []
    total_weight = 0.0
    link_center = None
    for block in doc["blocks"]:
        block_center = center(block)
        total_power = float(block["dynamic_W"]) + float(block["leakage_W"])
        criticality = float(block["timing_criticality"])
        channels = [int(match.group(1)) for endpoint in block["traffic_endpoints"] if (match := CHANNEL_RE.fullmatch(endpoint))]
        targets = [data[channel] for channel in channels if channel in data]
        if not targets:
            targets = list(data.values())
        weight = (0.1 + total_power) * (0.5 + criticality)
        total_weight += weight * max(len(targets), 1)
        for target in targets:
            distance = abs(block_center[0] - target[0]) + abs(block_center[1] - target[1])
            weighted_wire += distance * weight
            timing_proxy += distance * criticality
            access_distances.append(distance)
            routes.append((block_center, target, weight))
        if power_tsv:
            ir_proxy += total_power * min(abs(block_center[0] - target[0]) + abs(block_center[1] - target[1]) for target in power_tsv)
        if block["module"] in {"logic_die_link_arbiter", "logic_die_dual_link_arbiter"}:
            link_center = block_center
    weighted_wire /= max(total_weight, 1e-12)
    timing_proxy /= max(sum(float(block["timing_criticality"]) * max(len(block["traffic_endpoints"]), 1) for block in doc["blocks"]), 1e-12)
    ir_proxy /= max(sum(float(block["dynamic_W"]) + float(block["leakage_W"]) for block in doc["blocks"]), 1e-12)

    # Smooth power on a coarse grid. This is a placement-sensitive thermal proxy,
    # not a substitute for the Phase 5 solver result.
    xs = np.linspace(0, die_w, 33)
    ys = np.linspace(0, die_h, 49)
    xx, yy = np.meshgrid(xs, ys)
    sigma = 1400.0
    field = np.zeros_like(xx)
    for block in doc["blocks"]:
        bx, by = center(block)
        power = float(block["dynamic_W"]) + float(block["leakage_W"])
        field += power * np.exp(-((xx - bx) ** 2 + (yy - by) ** 2) / (2 * sigma ** 2))
    smooth_peak = float(field.max())
    peak_temperature_proxy = 26.85 + 8.0 * smooth_peak
    overlap_score = 0.0
    for left, a in enumerate(doc["blocks"]):
        ax, ay = center(a)
        ap = float(a["dynamic_W"]) + float(a["leakage_W"])
        for b in doc["blocks"][left + 1:]:
            bx, by = center(b)
            bp = float(b["dynamic_W"]) + float(b["leakage_W"])
            overlap_score += ap * bp * math.exp(-math.hypot(ax - bx, ay - by) / 1800.0)
    if link_center is None:
        link_center = center(doc["blocks"][0])
    channel_distances = [abs(link_center[0] - x) + abs(link_center[1] - y) for x, y in data.values()]
    mean_channel = float(np.mean(channel_distances)) if channel_distances else 0.0
    channel_cv = float(np.std(channel_distances) / mean_channel) if mean_channel else 0.0
    keepout_area = sum(
        int(bundle["rows"]) * int(bundle["columns"]) * math.pi * (float(bundle["diameter_um"]) / 2 + float(bundle["keepout_um"])) ** 2
        for bundle in doc["tsv_bundles"]
    )
    corridor_area = sum(float(region["width_um"]) * float(region["height_um"]) for region in doc["routing_corridors"])
    congestion = route_congestion_proxy(routes, die_w, die_h)
    cost_proxy = (keepout_area + corridor_area) / (die_w * die_h) + weighted_wire * 1e-5 + congestion * 1e-3
    return {
        "peak_temperature_proxy_C": peak_temperature_proxy,
        "hotspot_overlap_score": overlap_score,
        "traffic_weighted_manhattan_um": weighted_wire,
        "tsv_access_distance_um": float(np.mean(access_distances)) if access_distances else 0.0,
        "tsv_channel_distance_cv": channel_cv,
        "global_route_congestion_proxy": congestion,
        "timing_distance_proxy_um": timing_proxy,
        "ir_drop_distance_proxy_Wum_per_W": ir_proxy,
        "keepout_lost_area_um2": keepout_area,
        "routing_corridor_area_um2": corridor_area,
        "tsv_microbump_count": float(sum(item["rows"] * item["columns"] for item in doc["tsv_bundles"] + doc["micro_bump_bundles"])),
        "normalized_cost_proxy_raw": cost_proxy,
    }


def candidate_id(blocks: list[dict[str, Any]]) -> str:
    payload = [(b["instance"], round(float(b["x_um"]), 6), round(float(b["y_um"]), 6), b["orientation"]) for b in blocks]
    return "cand_" + hashlib.sha256(json.dumps(payload, separators=(",", ":")).encode()).hexdigest()[:12]


def candidate_from_assignment(base: dict[str, Any], slots: list[tuple[float, float]], permutation: list[int], jitter: list[tuple[float, float]], orientations: list[str]) -> dict[str, Any]:
    doc = copy.deepcopy(base)
    for block_index, block in enumerate(doc["blocks"]):
        slot_x, slot_y = slots[permutation[block_index]]
        dx, dy = jitter[block_index]
        block["x_um"], block["y_um"] = slot_x + dx, slot_y + dy
        block["orientation"] = orientations[block_index]
        block["placement_source"] = "deterministic_floorplan_candidate_generator"
        block["status"] = "provisional"
        block["classification"] = "modeled"
        block["confidence"] = "low"
    doc["manifest_id"] = candidate_id(doc["blocks"])
    return doc


def normalize(rows: list[dict[str, Any]], keys: list[str]) -> dict[str, tuple[float, float]]:
    ranges = {}
    for key in keys:
        values = [float(row[key]) for row in rows]
        ranges[key] = (min(values), max(values))
        for row in rows:
            row[f"norm_{key}"] = 0.0 if max(values) == min(values) else (float(row[key]) - min(values)) / (max(values) - min(values))
    return ranges


def pareto(rows: list[dict[str, Any]], keys: list[str]) -> list[dict[str, Any]]:
    frontier = []
    for row in rows:
        dominated = False
        for other in rows:
            if other is row:
                continue
            no_worse = all(float(other[key]) <= float(row[key]) + 1e-12 for key in keys)
            strictly_better = any(float(other[key]) < float(row[key]) - 1e-12 for key in keys)
            if no_worse and strictly_better:
                dominated = True
                break
        row["pareto_optimal"] = not dominated
        if not dominated:
            frontier.append(row)
    return frontier


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str] | None = None) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    selected = fields or list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=selected, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def optimize(manifest_path: str, objectives_path: str, output_dir: str, seed: int, samples: int) -> dict[str, Any]:
    base = load(manifest_path)
    objectives = load(objectives_path)
    output = absolute(output_dir)
    candidates_dir = output / "candidates"
    candidates_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)
    slots = [(float(block["x_um"]), float(block["y_um"])) for block in base["blocks"]]
    documents: dict[str, dict[str, Any]] = {}
    origins: dict[str, str] = {}
    rejected: list[dict[str, Any]] = []

    identity = list(range(len(base["blocks"])))
    manual = candidate_from_assignment(base, slots, identity, [(0.0, 0.0)] * len(identity), [block["orientation"] for block in base["blocks"]])
    documents[manual["manifest_id"]] = manual
    origins[manual["manifest_id"]] = "manual_baseline"
    jitter_values = [-75.0, 0.0, 75.0]
    for index in range(samples):
        permutation = identity.copy()
        rng.shuffle(permutation)
        # Most samples explore legal slot permutations/orientations; a smaller
        # subset probes nearby coordinates so rejection causes remain visible.
        jitter = ([(0.0, 0.0)] * len(identity) if index % 10 < 7 else
                  [(rng.choice(jitter_values), rng.choice(jitter_values)) for _ in identity])
        orientations = [rng.choice(["N", "S", "FN", "FS"]) for _ in identity]
        doc = candidate_from_assignment(base, slots, permutation, jitter, orientations)
        violations = hard_violations(doc)
        if violations:
            rejected.append({"attempt": index, "candidate_id": doc["manifest_id"], "reason": ";".join(violations)})
            continue
        documents.setdefault(doc["manifest_id"], doc)
        origins.setdefault(doc["manifest_id"], "seeded_permutation_jitter")

    rows = []
    for identifier, doc in documents.items():
        row = {"candidate_id": identifier, "origin": origins[identifier], "seed": seed, "evidence_class": "modeled", **metrics(doc)}
        rows.append(row)
    if len(rows) < 4:
        raise RuntimeError("fewer than four feasible candidates; increase samples or revise legal slots")
    score_keys = {
        "thermal": "peak_temperature_proxy_C",
        "wirelength": "traffic_weighted_manhattan_um",
        "congestion": "global_route_congestion_proxy",
        "timing": "timing_distance_proxy_um",
        "ir_drop": "ir_drop_distance_proxy_Wum_per_W",
        "area_cost": "normalized_cost_proxy_raw",
    }
    ranges = normalize(rows, list(score_keys.values()))
    for profile, weights in objectives["profiles"].items():
        for row in rows:
            row[f"score_{profile}"] = sum(float(weights[group]) * float(row[f"norm_{metric}"]) for group, metric in score_keys.items())
    frontier = pareto(rows, ["peak_temperature_proxy_C", "traffic_weighted_manhattan_um", "global_route_congestion_proxy", "timing_distance_proxy_um", "ir_drop_distance_proxy_Wum_per_W", "normalized_cost_proxy_raw"])
    rows.sort(key=lambda row: row["candidate_id"])

    selections = {
        "manual_baseline": next(row for row in rows if row["origin"] == "manual_baseline"),
        "wirelength_first": min(rows, key=lambda row: (row["traffic_weighted_manhattan_um"], row["candidate_id"])),
        "thermal_first": min(rows, key=lambda row: (row["score_thermal_first"], row["candidate_id"])),
        "balanced": min(rows, key=lambda row: (row["score_balanced"], row["candidate_id"])),
        "cost_first": min(rows, key=lambda row: (row["score_cost_first"], row["candidate_id"])),
    }
    selected_records = []
    for strategy, row in selections.items():
        doc = copy.deepcopy(documents[row["candidate_id"]])
        doc["manifest_id"] = f"{strategy}_{row['candidate_id']}"
        path = candidates_dir / f"{strategy}.json"
        path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
        # Full schema/geometry validation is authoritative for exported candidates.
        validation.validate(str(path), "design/floorplan/logic_die_floorplan.schema.json", None)
        selected_records.append({"strategy": strategy, **row, "manifest": display_path(path)})

    sensitivity = []
    perturbations = objectives["weight_sensitivity"]["relative_perturbations"]
    for profile, base_weights in objectives["profiles"].items():
        for varied_group in base_weights:
            for delta in perturbations:
                weights = dict(base_weights)
                weights[varied_group] *= 1 + float(delta)
                scale = sum(weights.values())
                weights = {key: value / scale for key, value in weights.items()}
                best = min(rows, key=lambda row: (sum(weights[group] * float(row[f"norm_{metric}"]) for group, metric in score_keys.items()), row["candidate_id"]))
                sensitivity.append({"profile": profile, "varied_group": varied_group, "relative_delta": delta, "selected_candidate_id": best["candidate_id"], "selected_is_pareto": best["pareto_optimal"]})

    write_csv(output / "placement_candidates.csv", rows)
    write_csv(output / "pareto_frontier.csv", sorted(frontier, key=lambda row: row["candidate_id"]))
    write_csv(output / "rejected_candidates.csv", rejected)
    write_csv(output / "selected_candidates.csv", selected_records)
    write_csv(output / "weight_sensitivity.csv", sensitivity)
    summary = {
        "status": "PASS", "seed": seed, "attempted_random_candidates": samples,
        "feasible_unique_candidates": len(rows), "rejected_candidates": len(rejected),
        "pareto_candidates": len(frontier), "selected": {key: row["candidate_id"] for key, row in selections.items()},
        "normalization_ranges": {key: {"min": value[0], "max": value[1]} for key, value in ranges.items()},
        "weights": objectives["profiles"],
        "power_input_W": sum(float(block["dynamic_W"]) + float(block["leakage_W"]) for block in base["blocks"]),
        "evidence": {"candidate_metrics": "modeled analytical proxies", "geometry": "illustrative/provisional", "timing_congestion_ir_drop": "proxy only until OpenROAD Phase 4", "temperature": "proxy only until solver Phase 5"},
        "disclaimer": "Candidate ranking is pre-physical exploration, not timing, routability, PI, thermal or manufacturing signoff."
    }
    (output / "optimization_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"FLOORPLAN_OPTIMIZATION PASS feasible={len(rows)} rejected={len(rejected)} pareto={len(frontier)} seed={seed}")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="design/floorplan/logic_die_floorplan.json")
    parser.add_argument("--objectives", default="design/floorplan/placement_objectives.json")
    parser.add_argument("--output", default="output/floorplan_optimization/exploration")
    parser.add_argument("--seed", type=int, default=235)
    parser.add_argument("--samples", type=int, default=400)
    args = parser.parse_args()
    optimize(args.manifest, args.objectives, args.output, args.seed, args.samples)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
