#!/usr/bin/env python3
"""Reproducible GR00T-driven HBM2 logic-block placement exploration.

This is an early-stage comparative model. It combines measured local RTL/GDS
metrics with explicitly labeled package, power, and thermal assumptions.
"""

import argparse
import csv
import json
import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.sparse import lil_matrix
from scipy.sparse.linalg import factorized
from scipy.stats import spearmanr


METRICS = ("wire", "delay", "thermal", "tsv", "congestion", "power", "area", "reliability")


def value(group, key, scenario="base"):
    return float(group[key][scenario])


def load_config(path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def channel_points(cfg):
    geom = cfg["package_geometry"]
    count = int(value(geom, "hbm_channel_count"))
    width = value(geom, "dram_die_width_mm")
    xs = np.linspace(-width / 2 + width / (2 * count), width / 2 - width / (2 * count), count)
    return np.column_stack((xs, np.zeros(count)))


def tsv_points(cfg):
    geom = cfg["package_geometry"]
    xoff = value(geom, "tsv_x_offset_mm")
    height = value(geom, "dram_die_height_mm")
    ys = np.linspace(-0.42 * height, 0.42 * height, 16)
    return np.array([(side * xoff, y) for side in (-1, 1) for y in ys])


def candidate_is_feasible(x, y, cfg):
    geom = cfg["package_geometry"]
    block_w = cfg["measured_physical"]["rtl_die_width_um"] / 1000.0
    block_h = cfg["measured_physical"]["rtl_die_height_um"] / 1000.0
    die_w = value(geom, "base_die_width_mm")
    die_h = value(geom, "base_die_height_mm")
    margin = value(geom, "placement_margin_mm")
    if abs(x) + block_w / 2 + margin > die_w / 2:
        return False, "die_boundary"
    if abs(y) + block_h / 2 + margin > die_h / 2:
        return False, "die_boundary"

    xoff = value(geom, "tsv_x_offset_mm")
    band = value(geom, "phy_reserved_band_halfwidth_mm")
    if abs(abs(x) - xoff) < band + block_w / 2:
        return False, "phy_reserved_band"

    koz = value(geom, "tsv_keepout_radius_mm")
    for tx, ty in tsv_points(cfg):
        if abs(x - tx) < koz + block_w / 2 and abs(y - ty) < koz + block_h / 2:
            return False, "tsv_keepout"
    return True, ""


def candidate_grid(cfg, centers=None):
    geom = cfg["package_geometry"]
    analysis = cfg["analysis"]
    die_w = value(geom, "base_die_width_mm")
    die_h = value(geom, "base_die_height_mm")
    if centers is None:
        step = analysis["coarse_step_mm"]
        xs = np.arange(-die_w / 2, die_w / 2 + step / 2, step)
        ys = np.arange(-die_h / 2, die_h / 2 + step / 2, step)
    else:
        step = analysis["fine_step_mm"]
        radius = analysis["fine_radius_mm"]
        points = set()
        for cx, cy in centers:
            for x in np.arange(cx - radius, cx + radius + step / 2, step):
                for y in np.arange(cy - radius, cy + radius + step / 2, step):
                    points.add((round(float(x), 6), round(float(y), 6)))
        return sorted(p for p in points if candidate_is_feasible(p[0], p[1], cfg)[0])
    return [(round(float(x), 6), round(float(y), 6)) for x in xs for y in ys
            if candidate_is_feasible(float(x), float(y), cfg)[0]]


class ThermalModel:
    """Steady-state finite-volume compact RC model on the base-die plane."""

    def __init__(self, cfg):
        geom = cfg["package_geometry"]
        thermal = cfg["thermal"]
        self.cfg = cfg
        self.width = value(geom, "base_die_width_mm")
        self.height = value(geom, "base_die_height_mm")
        self.nx = int(thermal["grid_nx"])
        self.ny = int(thermal["grid_ny"])
        self.xs = np.linspace(-self.width / 2, self.width / 2, self.nx)
        self.ys = np.linspace(-self.height / 2, self.height / 2, self.ny)
        self.dx = self.xs[1] - self.xs[0]
        self.dy = self.ys[1] - self.ys[0]
        self.area = self.dx * self.dy
        self.ambient = value(thermal, "ambient_c")
        k_w_per_mk = value(thermal, "silicon_conductivity_w_per_mk")
        self.k_w_per_mmk = k_w_per_mk / 1000.0
        self.thickness = value(thermal, "logic_silicon_thickness_mm")
        self.h = value(thermal, "vertical_conductance_w_per_mm2k")
        self.tsv_gain = value(thermal, "tsv_vertical_conductance_gain")
        self._build_solver()

    def _build_solver(self):
        count = self.nx * self.ny
        matrix = lil_matrix((count, count), dtype=float)
        tsvs = tsv_points(self.cfg)
        for iy, y in enumerate(self.ys):
            for ix, x in enumerate(self.xs):
                index = iy * self.nx + ix
                near_tsv = np.min(np.hypot(tsvs[:, 0] - x, tsvs[:, 1] - y)) <= 0.16
                vertical_h = self.h * (self.tsv_gain if near_tsv else 1.0)
                diagonal = vertical_h * self.area
                for nx_, ny_, conductance in (
                    (ix - 1, iy, self.k_w_per_mmk * self.thickness * self.dy / self.dx),
                    (ix + 1, iy, self.k_w_per_mmk * self.thickness * self.dy / self.dx),
                    (ix, iy - 1, self.k_w_per_mmk * self.thickness * self.dx / self.dy),
                    (ix, iy + 1, self.k_w_per_mmk * self.thickness * self.dx / self.dy),
                ):
                    if 0 <= nx_ < self.nx and 0 <= ny_ < self.ny:
                        matrix[index, ny_ * self.nx + nx_] = -conductance
                        diagonal += conductance
                matrix[index, index] = diagonal
        self.solve_linear = factorized(matrix.tocsc())
        self.vertical_rhs = np.full(count, self.h * self.area * self.ambient)
        for iy, y in enumerate(self.ys):
            for ix, x in enumerate(self.xs):
                if np.min(np.hypot(tsvs[:, 0] - x, tsvs[:, 1] - y)) <= 0.16:
                    self.vertical_rhs[iy * self.nx + ix] *= self.tsv_gain

    def power_vector(self, candidate, logic_power, dram_power):
        geom = self.cfg["package_geometry"]
        thermal = self.cfg["thermal"]
        physical = self.cfg["measured_physical"]
        block_w = physical["rtl_die_width_um"] / 1000.0
        block_h = physical["rtl_die_height_um"] / 1000.0
        dram_w = value(geom, "dram_die_width_mm")
        dram_h = value(geom, "dram_die_height_mm")
        coupling = value(self.cfg["electrical"], "dram_heat_coupling_to_base")
        xx, yy = np.meshgrid(self.xs, self.ys)
        logic_mask = ((np.abs(xx - candidate[0]) <= block_w / 2) &
                      (np.abs(yy - candidate[1]) <= block_h / 2))
        dram_mask = (np.abs(xx) <= dram_w / 2) & (np.abs(yy) <= dram_h / 2)
        power = np.zeros_like(xx, dtype=float)
        power[logic_mask] += logic_power / max(np.count_nonzero(logic_mask), 1)
        power[dram_mask] += dram_power * coupling / max(np.count_nonzero(dram_mask), 1)
        return power.ravel()

    def evaluate(self, candidate, logic_power=None, dram_power=None):
        electrical = self.cfg["electrical"]
        if logic_power is None:
            logic_power = value(electrical, "logic_active_power_w")
        if dram_power is None:
            dram_power = value(electrical, "dram_stack_power_w")
        rhs = self.vertical_rhs + self.power_vector(candidate, logic_power, dram_power)
        field = self.solve_linear(rhs).reshape(self.ny, self.nx)
        gy, gx = np.gradient(field, self.dy, self.dx)
        return {
            "max_temp_c": float(np.max(field)),
            "mean_temp_c": float(np.mean(field)),
            "max_gradient_c_per_mm": float(np.max(np.hypot(gx, gy))),
            "field": field,
        }


def electrical_metrics(candidate, cfg):
    x, y = candidate
    geom = cfg["package_geometry"]
    channels = channel_points(cfg)
    distances = np.abs(channels[:, 0] - x) + np.abs(channels[:, 1] - y)
    average_mm = float(np.mean(distances))
    maximum_mm = float(np.max(distances))
    skew_mm = float(np.std(distances))
    tsvs = tsv_points(cfg)
    tsv_distance_mm = float(np.min(np.abs(tsvs[:, 0] - x) + np.abs(tsvs[:, 1] - y)))

    electrical = cfg["electrical"]
    r = value(electrical, "signal_resistance_kohm_per_um")
    c = value(electrical, "signal_capacitance_pf_per_um")
    longest_um = maximum_mm * 1000.0
    delay_ps = 1000.0 * 0.5 * r * c * longest_um ** 2
    average_um = average_mm * 1000.0
    cap_pf = c * average_um * len(channels)
    voltage = cfg["measured_physical"]["vdd_v"]
    frequency_hz = value(electrical, "frequency_mhz") * 1e6
    activity = value(electrical, "switching_activity")
    wire_power_mw = activity * cap_pf * 1e-12 * voltage ** 2 * frequency_hz * 1000.0
    convergence = float(np.sum(1.0 / (distances + 0.25)))
    congestion = min(0.99, 0.71 + 0.02 * convergence)
    corridor_area = (average_um * len(channels) *
                     value(electrical, "routing_corridor_pitch_um") / 1e6)
    block_area = (cfg["measured_physical"]["rtl_die_width_um"] *
                  cfg["measured_physical"]["rtl_die_height_um"] / 1e6)
    tsv_count = int(value(geom, "hbm_channel_count") * value(geom, "channel_data_width_bits"))
    koz_radius = value(geom, "tsv_keepout_radius_mm")
    physical_tsv_count = (2 * int(value(geom, "tsv_columns_per_side")) *
                          int(value(geom, "tsv_rows_per_column")))
    tsv_keepout_area = physical_tsv_count * math.pi * koz_radius ** 2
    return {
        "wire_um": average_um,
        "max_wire_um": longest_um,
        "wire_skew_um": skew_mm * 1000.0,
        "delay_ps": delay_ps,
        "tsv_distance_um": tsv_distance_mm * 1000.0,
        "congestion_ratio": congestion,
        "wire_power_mw": wire_power_mw,
        "area_proxy_mm2": block_area + corridor_area,
        "tsv_count": tsv_count,
        "tsv_keepout_area_mm2": tsv_keepout_area,
        "tsv_violation_penalty": 0.0,
    }


def raw_costs(row, cfg):
    ambient = value(cfg["thermal"], "ambient_c")
    limit = value(cfg["thermal"], "temperature_limit_c")
    max_rise = max(0.0, row["max_temp_c"] - ambient)
    mean_rise = max(0.0, row["mean_temp_c"] - ambient)
    exceedance = max(0.0, row["max_temp_c"] - limit)
    thermal = (max_rise + 0.25 * mean_rise +
               0.20 * row["max_gradient_c_per_mm"] + 4.0 * exceedance)
    reference = cfg["normalization"]
    tsv = 0.55 * row["tsv_distance_um"] / reference["tsv_distance_um"]
    tsv += 0.15 * row["tsv_count"] / reference["tsv_count"]
    tsv += 0.15 * row["tsv_keepout_area_mm2"] / reference["tsv_keepout_area_mm2"]
    tsv += 0.15 * row["tsv_violation_penalty"] / reference["tsv_violation_penalty"]
    reliability = math.exp((row["max_temp_c"] - 85.0) / 10.0)
    return {
        "wire": row["wire_um"],
        "delay": row["delay_ps"] + 0.10 * row["wire_skew_um"],
        "thermal": thermal,
        "tsv": tsv,
        "congestion": row["congestion_ratio"],
        "power": row["wire_power_mw"],
        "area": row["area_proxy_mm2"],
        "reliability": reliability,
    }


def normalize_rows(rows, cfg):
    reference = cfg["normalization"]
    scales = {
        "wire": reference["wire_um"],
        "delay": reference["delay_ps"],
        "thermal": reference["thermal_rise_plus_gradient_c"],
        "tsv": 1.0,
        "power": reference["wire_power_mw"],
        "area": reference["area_proxy_mm2"],
        "reliability": reference["reliability_proxy"],
    }
    for row in rows:
        row["norm"] = {}
        for metric in METRICS:
            raw = row["raw"][metric]
            if metric == "congestion":
                normalized = ((raw - reference["congestion_floor"]) /
                              reference["congestion_headroom"])
            else:
                normalized = raw / scales[metric]
            row["norm"][metric] = float(np.clip(normalized, 0.0, 1.0))


def score_rows(rows, profiles):
    for row in rows:
        row["scores"] = {
            name: sum(weights[metric] * row["norm"][metric] for metric in METRICS)
            for name, weights in profiles.items()
        }


def evaluate_candidates(candidates, cfg, thermal_model):
    rows = []
    for candidate in candidates:
        row = {"x_mm": candidate[0], "y_mm": candidate[1]}
        row.update(electrical_metrics(candidate, cfg))
        thermal = thermal_model.evaluate(candidate)
        row.update({key: val for key, val in thermal.items() if key != "field"})
        row["temperature_exceedance_c"] = max(
            0.0, row["max_temp_c"] - value(cfg["thermal"], "temperature_limit_c"))
        row["timing_exceedance_ps"] = max(
            0.0, row["delay_ps"] - cfg["measured_physical"]["clock_period_ns"] * 1000.0)
        violations = []
        if row["temperature_exceedance_c"] > 0.0:
            violations.append("temperature_limit")
        if row["timing_exceedance_ps"] > 0.0:
            violations.append("timing_limit")
        row["candidate_constraints_satisfied"] = not violations
        if cfg["measured_physical"]["clock_slack_ns"] < 0.0:
            violations.append("global_rtl_timing_not_closed")
        row["hard_constraints_satisfied"] = not violations
        row["hard_constraint_violations"] = ";".join(violations)
        row["raw"] = raw_costs(row, cfg)
        rows.append(row)
    normalize_rows(rows, cfg)
    score_rows(rows, cfg["cost_profiles"])
    return rows


def find_row(rows, x, y):
    return min(rows, key=lambda row: abs(row["x_mm"] - x) + abs(row["y_mm"] - y))


def pareto_rows(rows):
    objectives = np.array([[r["wire_um"], r["max_temp_c"], r["area_proxy_mm2"]] for r in rows])
    keep = np.ones(len(rows), dtype=bool)
    for index in range(len(rows)):
        if not keep[index]:
            continue
        dominates = np.all(objectives <= objectives[index], axis=1) & np.any(objectives < objectives[index], axis=1)
        if np.any(dominates):
            keep[index] = False
    return [row for row, selected in zip(rows, keep) if selected]


def scenario_rows(base_rows, cfg, parameter, factor):
    rows = []
    base_logic = value(cfg["electrical"], "logic_active_power_w")
    base_dram = value(cfg["electrical"], "dram_stack_power_w")
    base_h = value(cfg["thermal"], "vertical_conductance_w_per_mm2k")
    for original in base_rows:
        row = {key: val for key, val in original.items() if key not in ("raw", "norm", "scores")}
        if parameter == "logic_power":
            rise = original["max_temp_c"] - value(cfg["thermal"], "ambient_c")
            logic_share = base_logic / (base_logic + base_dram * value(cfg["electrical"], "dram_heat_coupling_to_base"))
            row["max_temp_c"] = original["max_temp_c"] + rise * logic_share * (factor - 1.0)
        elif parameter == "dram_power":
            rise = original["max_temp_c"] - value(cfg["thermal"], "ambient_c")
            logic_share = base_logic / (base_logic + base_dram * value(cfg["electrical"], "dram_heat_coupling_to_base"))
            row["max_temp_c"] = original["max_temp_c"] + rise * (1.0 - logic_share) * (factor - 1.0)
        elif parameter == "vertical_conductance":
            ambient = value(cfg["thermal"], "ambient_c")
            row["max_temp_c"] = ambient + (original["max_temp_c"] - ambient) / factor
            row["mean_temp_c"] = ambient + (original["mean_temp_c"] - ambient) / factor
            row["max_gradient_c_per_mm"] = original["max_gradient_c_per_mm"] / factor
        elif parameter == "switching_activity":
            row["wire_power_mw"] = original["wire_power_mw"] * factor
        elif parameter == "routing_pitch":
            block_area = (cfg["measured_physical"]["rtl_die_width_um"] *
                          cfg["measured_physical"]["rtl_die_height_um"] / 1e6)
            row["area_proxy_mm2"] = block_area + (original["area_proxy_mm2"] - block_area) * factor
        row["temperature_exceedance_c"] = max(
            0.0, row["max_temp_c"] - value(cfg["thermal"], "temperature_limit_c"))
        row["raw"] = raw_costs(row, cfg)
        rows.append(row)
    normalize_rows(rows, cfg)
    score_rows(rows, cfg["cost_profiles"])
    return rows


def sensitivity(base_rows, cfg):
    records = []
    parameters = ("logic_power", "dram_power", "vertical_conductance", "switching_activity", "routing_pitch")
    baseline = find_row(base_rows, 0.0, 0.0)
    for parameter in parameters:
        for delta in (-0.20, -0.10, 0.10, 0.20):
            rows = scenario_rows(base_rows, cfg, parameter, 1.0 + delta)
            winner = min(rows, key=lambda row: row["scores"]["balanced"])
            base = find_row(rows, baseline["x_mm"], baseline["y_mm"])
            records.append({
                "parameter": parameter,
                "delta_percent": int(delta * 100),
                "winner_x_mm": winner["x_mm"],
                "winner_y_mm": winner["y_mm"],
                "winner_score": winner["scores"]["balanced"],
                "baseline_score": base["scores"]["balanced"],
                "improvement_percent": 100.0 * (base["scores"]["balanced"] - winner["scores"]["balanced"]) /
                                       max(base["scores"]["balanced"], 1e-12),
            })
    return records


def climate_scenarios(base_rows, cfg):
    ambient_base = value(cfg["thermal"], "ambient_c")
    cases = {
        "low_power_strong_cooling": {"ambient": 20.0, "logic": 0.5, "dram": 0.5, "conductance": 2.0},
        "base": {"ambient": ambient_base, "logic": 1.0, "dram": 1.0, "conductance": 1.0},
        "high_power_weak_cooling": {"ambient": 45.0, "logic": 2.0, "dram": 1.5, "conductance": 0.5},
    }
    logic_base = value(cfg["electrical"], "logic_active_power_w")
    dram_base = (value(cfg["electrical"], "dram_stack_power_w") *
                 value(cfg["electrical"], "dram_heat_coupling_to_base"))
    records = []
    for name, case in cases.items():
        rows = []
        power_ratio = ((logic_base * case["logic"] + dram_base * case["dram"]) /
                       (logic_base + dram_base))
        for original in base_rows:
            row = {key: val for key, val in original.items() if key not in ("raw", "norm", "scores")}
            rise = original["max_temp_c"] - ambient_base
            mean_rise = original["mean_temp_c"] - ambient_base
            scale = power_ratio / case["conductance"]
            row["max_temp_c"] = case["ambient"] + rise * scale
            row["mean_temp_c"] = case["ambient"] + mean_rise * scale
            row["max_gradient_c_per_mm"] = original["max_gradient_c_per_mm"] * scale
            row["temperature_exceedance_c"] = max(
                0.0, row["max_temp_c"] - value(cfg["thermal"], "temperature_limit_c"))
            row["raw"] = raw_costs(row, cfg)
            rows.append(row)
        normalize_rows(rows, cfg)
        score_rows(rows, cfg["cost_profiles"])
        winner = min(rows, key=lambda row: row["scores"]["balanced"])
        baseline = find_row(rows, 0.0, 0.0)
        records.append({
            "scenario": name,
            "ambient_c": case["ambient"],
            "logic_power_factor": case["logic"],
            "dram_power_factor": case["dram"],
            "vertical_conductance_factor": case["conductance"],
            "winner_x_mm": winner["x_mm"],
            "winner_y_mm": winner["y_mm"],
            "winner_max_temp_c_unvalidated": winner["max_temp_c"],
            "winner_score": winner["scores"]["balanced"],
            "baseline_score": baseline["scores"]["balanced"],
        })
    return records


def monte_carlo(rows, cfg):
    rng = np.random.default_rng(int(cfg["analysis"]["random_seed"]))
    samples = int(cfg["analysis"]["monte_carlo_samples"])
    base_weights = np.array([cfg["cost_profiles"]["balanced"][metric] for metric in METRICS])
    normalized = np.array([[row["norm"][metric] for metric in METRICS] for row in rows])
    winners = np.zeros(len(rows), dtype=int)
    rank_sums = np.zeros(len(rows), dtype=float)
    top_k_counts = np.zeros(len(rows), dtype=int)
    top_k = int(cfg["analysis"]["robust_top_k"])
    correlations = {metric: [] for metric in METRICS}
    base_rank = np.argsort(np.argsort(normalized @ base_weights))
    for _ in range(samples):
        weights = rng.dirichlet(base_weights * 80.0)
        scale = np.ones(len(METRICS))
        scale[METRICS.index("thermal")] = rng.triangular(0.8, 1.0, 1.2)
        scale[METRICS.index("power")] = rng.triangular(0.5, 1.0, 2.0)
        scale[METRICS.index("area")] = rng.triangular(0.5, 1.0, 2.0)
        scores = (normalized * scale) @ weights
        winner = int(np.argmin(scores))
        winners[winner] += 1
        ranks = np.argsort(np.argsort(scores))
        rank_sums += ranks + 1
        top_k_counts += ranks < top_k
        for metric_index, metric in enumerate(METRICS):
            correlations[metric].append(float(spearmanr(normalized[:, metric_index], scores).statistic))
    records = []
    for index, count in enumerate(winners):
        rate = float(count / samples)
        center = (rate + 1.96 ** 2 / (2 * samples)) / (1 + 1.96 ** 2 / samples)
        half = (1.96 * math.sqrt(rate * (1 - rate) / samples +
                1.96 ** 2 / (4 * samples ** 2)) / (1 + 1.96 ** 2 / samples))
        records.append({
            "x_mm": rows[index]["x_mm"],
            "y_mm": rows[index]["y_mm"],
            "wins": int(count),
            "win_rate": rate,
            "win_rate_ci95_low": max(0.0, center - half),
            "win_rate_ci95_high": min(1.0, center + half),
            "mean_rank": float(rank_sums[index] / samples),
            "top_k": top_k,
            "top_k_rate": float(top_k_counts[index] / samples),
            "balanced_rank": int(base_rank[index] + 1),
        })
    records.sort(key=lambda record: (-record["wins"], record["mean_rank"]))
    mean_correlations = {metric: float(np.mean(values)) for metric, values in correlations.items()}
    return records, mean_correlations


def weight_sweep(rows, cfg):
    """Sweep one balanced weight and renormalize all remaining weights proportionally."""
    base = cfg["cost_profiles"]["balanced"]
    start = float(cfg["analysis"]["weight_sweep_min"])
    stop = float(cfg["analysis"]["weight_sweep_max"])
    step = float(cfg["analysis"]["weight_sweep_step"])
    records = []
    normalized = np.array([[row["norm"][metric] for metric in METRICS] for row in rows])
    baseline_index = rows.index(find_row(rows, 0.0, 0.0))
    for focus in METRICS:
        for focus_weight in np.arange(start, stop + step / 2.0, step):
            remaining_base = 1.0 - base[focus]
            weights = np.array([
                focus_weight if metric == focus else
                base[metric] * (1.0 - focus_weight) / remaining_base
                for metric in METRICS
            ])
            scores = normalized @ weights
            order = np.argsort(scores)
            winner_index = int(order[0])
            baseline_rank = int(np.where(order == baseline_index)[0][0] + 1)
            records.append({
                "focus_metric": focus,
                "focus_weight": float(round(focus_weight, 8)),
                "winner_x_mm": rows[winner_index]["x_mm"],
                "winner_y_mm": rows[winner_index]["y_mm"],
                "winner_score": float(scores[winner_index]),
                "baseline_score": float(scores[baseline_index]),
                "baseline_rank": baseline_rank,
                "winner_changed_from_balanced": bool(
                    winner_index != int(np.argmin(normalized @ np.array([base[m] for m in METRICS])))
                ),
            })
    return records


def manufacturing_cost_scenarios(cfg):
    """Partial early-stage cost model; excludes DRAM fabrication and vendor margin."""
    records = []
    for scenario in ("low", "base", "high"):
        geometry = cfg["package_geometry"]
        cost = cfg["manufacturing_cost"]
        die_area_mm2 = (value(geometry, "base_die_width_mm", scenario) *
                        value(geometry, "base_die_height_mm", scenario))
        wafer_diameter = value(cost, "wafer_diameter_mm", scenario)
        gross_dies = max(1.0, (math.pi * (wafer_diameter / 2.0) ** 2 / die_area_mm2 -
                               math.pi * wafer_diameter / math.sqrt(2.0 * die_area_mm2)))
        defect_density = value(cost, "defect_density_per_cm2", scenario)
        poisson_yield = math.exp(-defect_density * die_area_mm2 / 100.0)
        good_dies = gross_dies * poisson_yield
        logic_die_cost = value(cost, "wafer_cost_usd", scenario) / good_dies
        assembly_yield = value(cost, "stack_assembly_yield", scenario)
        kgd_yield = value(cost, "known_good_die_yield", scenario)
        package_cost = value(cost, "package_cost_usd", scenario)
        partial_stack_cost = (logic_die_cost + package_cost) / (assembly_yield * kgd_yield)
        records.append({
            "scenario": scenario,
            "base_logic_die_area_mm2": die_area_mm2,
            "gross_dies_per_wafer_analytical": gross_dies,
            "poisson_logic_die_yield": poisson_yield,
            "good_logic_dies_per_wafer": good_dies,
            "logic_die_cost_usd": logic_die_cost,
            "package_cost_usd": package_cost,
            "partial_logic_plus_package_cost_usd": partial_stack_cost,
            "excludes": "HBM_DRAM_die_cost;test_cost;NRE;vendor_margin",
            "status": "placeholder_not_vendor_quote",
        })
    return records


def workload_summary(cfg):
    workload = cfg["workload"]
    bytes_total = value(workload, "aggregate_read_write_bytes")
    cycles = value(workload, "normalization_cycles")
    frequency_hz = value(cfg["electrical"], "frequency_mhz") * 1e6
    runtime_s = cycles / frequency_hz
    return {
        "model": cfg["model"]["name"],
        "checkpoint_revision": cfg["model"]["checkpoint_revision"],
        "scope": "seven unique LayerNorm/RMSNorm profiles projected to 333 calls",
        "full_model_inference": False,
        "dtype_official": cfg["model"]["dtype_official"],
        "dtype_simulated": cfg["model"]["dtype_simulated"],
        "projected_cycles": int(cycles),
        "minimum_input_plus_output_bytes": int(bytes_total),
        "minimum_arithmetic_intensity_ops_per_byte": None,
        "projected_runtime_at_constraint_s": runtime_s,
        "minimum_aggregate_bandwidth_gbps": bytes_total / runtime_s / 1e9,
        "limitations": [
            "Excludes affine parameters, reductions, intermediates, cache effects and protocol traffic.",
            "Uses deterministic synthetic FP16 tensors, not pretrained BF16 activation traces.",
            "Does not measure channel request rate or PCU utilization; those remain assumptions."
        ],
        "source_ids": ["S1", "S2", "S3", "L1", "A4"]
    }


def infer_unit(key):
    explicit = {
        "switching_activity": "fraction", "pcu_utilization": "fraction",
        "dram_heat_coupling_to_base": "fraction", "stack_assembly_yield": "fraction",
        "known_good_die_yield": "fraction", "phy_area_fraction": "fraction",
        "power_grid_area_fraction": "fraction", "clock_tree_area_fraction": "fraction",
        "tsv_vertical_conductance_gain": "ratio", "dram_die_count": "dies",
        "hbm_channel_count": "channels", "channel_data_width_bits": "bits_per_channel",
        "tsv_rows_per_column": "rows", "tsv_columns_per_side": "columns",
    }
    if key in explicit:
        return explicit[key]
    suffixes = (
        ("_mreq_per_s", "million_requests_per_second"), ("_gbps", "GB_per_second"),
        ("_w_per_mm2k", "W_per_mm2K"), ("_w_per_mk", "W_per_mK"),
        ("_kohm_per_um", "kohm_per_um"), ("_pf_per_um", "pF_per_um"),
        ("_per_cm2", "per_cm2"), ("_j_per_k", "J_per_K"),
        ("_um2", "um2"), ("_mm2", "mm2"), ("_um", "um"), ("_mm", "mm"),
        ("_mhz", "MHz"), ("_ns", "ns"), ("_ps", "ps"), ("_bytes", "bytes"),
        ("_cycles", "cycles"), ("_w", "W"), ("_v", "V"), ("_c", "degC"),
        ("_usd", "USD"), ("_bits", "bits"), ("_count", "count"),
    )
    for suffix, unit in suffixes:
        if key.endswith(suffix):
            return unit
    return "dimensionless_or_count"


def input_assumption_records(cfg):
    records = []
    groups = ("workload", "package_geometry", "electrical", "thermal",
              "reserved_areas", "manufacturing_cost")
    for group_name in groups:
        for key, entry in cfg[group_name].items():
            if not isinstance(entry, dict) or "base" not in entry:
                continue
            low, base, high = entry["low"], entry["base"], entry["high"]
            distribution = entry.get(
                "distribution", "fixed" if low == base == high else "triangular_low_base_high")
            records.append({
                "group": group_name,
                "parameter": key,
                "minimum": low,
                "base": base,
                "maximum": high,
                "unit": entry.get("unit", infer_unit(key)),
                "distribution_or_sweep": distribution,
                "status": entry["status"],
                "source_ids": ";".join(entry["source_ids"]),
            })
    return records


def routing_rc_records(cfg):
    records = []
    for layer, entry in cfg["routing_layer_rc"].items():
        if layer == "via_resistance_kohm":
            for via, resistance in entry.items():
                if via not in ("status", "source_ids"):
                    records.append({"layer_or_via": via, "kind": "via",
                                    "resistance_kohm_per_um": "",
                                    "capacitance_pf_per_um": "",
                                    "via_resistance_kohm": resistance,
                                    "status": entry["status"],
                                    "source_ids": ";".join(entry["source_ids"])})
        else:
            records.append({"layer_or_via": layer, "kind": "routing_layer",
                            "resistance_kohm_per_um": entry["resistance_kohm_per_um"],
                            "capacitance_pf_per_um": entry["capacitance_pf_per_um"],
                            "via_resistance_kohm": "", "status": entry["status"],
                            "source_ids": ";".join(entry["source_ids"])})
    return records


def write_csv(path, records, fields):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)


def flattened_row(row):
    flat = {key: value_ for key, value_ in row.items() if key not in ("raw", "norm", "scores")}
    for prefix in ("raw", "norm", "scores"):
        for key, value_ in row[prefix].items():
            flat[prefix + "_" + key] = value_
    return flat


def save_figure(fig, output_dir, name):
    fig.savefig(output_dir / (name + ".png"), dpi=180, bbox_inches="tight")
    fig.savefig(output_dir / (name + ".svg"), bbox_inches="tight")
    plt.close(fig)


def make_plots(rows, pareto, sensitivity_records, weight_records, mc_records,
               cost_records, provisional, thermal_model, output_dir):
    xs = sorted(set(row["x_mm"] for row in rows))
    ys = sorted(set(row["y_mm"] for row in rows))
    grid = np.full((len(ys), len(xs)), np.nan)
    for row in rows:
        grid[ys.index(row["y_mm"]), xs.index(row["x_mm"])] = row["scores"]["balanced"]
    fig, ax = plt.subplots(figsize=(8, 6))
    image = ax.imshow(grid, origin="lower", extent=(min(xs), max(xs), min(ys), max(ys)), aspect="auto", cmap="viridis_r")
    ax.scatter([0], [0], marker="+", s=100, color="white", label="Center baseline")
    ax.scatter([provisional["x_mm"]], [provisional["y_mm"]], marker="*", s=140, color="red", label="Provisional MC mode")
    ax.set(xlabel="Logic block X (mm)", ylabel="Logic block Y (mm)", title="Balanced normalized placement cost")
    ax.legend()
    fig.colorbar(image, ax=ax, label="Normalized cost (lower is better)")
    save_figure(fig, output_dir, "placement_cost_heatmap")

    thermal = thermal_model.evaluate((provisional["x_mm"], provisional["y_mm"]))
    fig, ax = plt.subplots(figsize=(8, 6))
    image = ax.imshow(thermal["field"], origin="lower",
                      extent=(-thermal_model.width / 2, thermal_model.width / 2,
                              -thermal_model.height / 2, thermal_model.height / 2),
                      aspect="auto", cmap="inferno")
    ax.scatter([provisional["x_mm"]], [provisional["y_mm"]], marker="s", facecolors="none", edgecolors="cyan", label="Provisional logic block center")
    ax.set(xlabel="X (mm)", ylabel="Y (mm)", title="Uncalibrated compact-model steady-state temperature")
    ax.legend()
    fig.colorbar(image, ax=ax, label="Temperature (degC, assumption-dependent)")
    save_figure(fig, output_dir, "provisional_temperature_map")

    top = sorted(rows, key=lambda row: row["scores"]["balanced"])[:8]
    fig, ax = plt.subplots(figsize=(10, 5))
    bottom = np.zeros(len(top))
    labels = ["({:.1f},{:.1f})".format(row["x_mm"], row["y_mm"]) for row in top]
    weights = thermal_model.cfg["cost_profiles"]["balanced"]
    for metric in METRICS:
        values = np.array([row["norm"][metric] * weights[metric] for row in top])
        ax.bar(labels, values, bottom=bottom, label=metric)
        bottom += values
    ax.set(ylabel="Balanced weighted normalized cost", xlabel="Candidate (X mm, Y mm)", title="Top candidate cost composition")
    ax.tick_params(axis="x", rotation=35)
    ax.legend(ncol=4, fontsize=8)
    save_figure(fig, output_dir, "top_candidate_components")

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.scatter([r["wire_um"] for r in rows], [r["max_temp_c"] for r in rows], s=15, alpha=0.35, label="Feasible candidates")
    ax.scatter([r["wire_um"] for r in pareto], [r["max_temp_c"] for r in pareto], s=35, color="red", label="3-objective Pareto set")
    ax.set(xlabel="Mean channel Manhattan wire proxy (um)", ylabel="Peak temperature (degC)", title="Wire-temperature Pareto projection")
    ax.legend()
    save_figure(fig, output_dir, "pareto_wire_temperature")

    deltas = {}
    for record in sensitivity_records:
        deltas.setdefault(record["parameter"], []).append(record["improvement_percent"])
    labels = list(deltas)
    spans = [max(values) - min(values) for values in deltas.values()]
    fig, ax = plt.subplots(figsize=(8, 5))
    order = np.argsort(spans)
    ax.barh(np.array(labels)[order], np.array(spans)[order], color="#3f7ea6")
    ax.set(xlabel="Range of baseline-to-winner improvement (percentage points)", title="OAT sensitivity tornado (+/-10%, +/-20%)")
    save_figure(fig, output_dir, "sensitivity_tornado")

    fig, ax = plt.subplots(figsize=(10, 6))
    for metric in METRICS:
        selected = [record for record in weight_records if record["focus_metric"] == metric]
        ax.plot([record["focus_weight"] for record in selected],
                [record["baseline_rank"] for record in selected], marker="o", label=metric)
    ax.invert_yaxis()
    ax.set(xlabel="Focused metric weight", ylabel="Center baseline rank (1 is best)",
           title="One-weight sweep with proportional renormalization")
    ax.legend(ncol=4, fontsize=8)
    save_figure(fig, output_dir, "weight_sweep_baseline_rank")

    fig, ax = plt.subplots(figsize=(8, 5))
    top_mc = mc_records[:12]
    ax.bar(["({:.1f},{:.1f})".format(r["x_mm"], r["y_mm"]) for r in top_mc],
           [100 * r["win_rate"] for r in top_mc], color="#31a36c")
    ax.set(xlabel="Candidate (X mm, Y mm)", ylabel="Monte Carlo winner rate (%)", title="Rank stability under weight/input uncertainty")
    ax.tick_params(axis="x", rotation=35)
    save_figure(fig, output_dir, "monte_carlo_rank_stability")

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.bar([record["scenario"] for record in cost_records],
           [record["partial_logic_plus_package_cost_usd"] for record in cost_records],
           color=["#3f7ea6", "#31a36c", "#c24747"])
    ax.set(xlabel="Input scenario", ylabel="Partial cost estimate (USD)",
           title="Unquoted logic-die plus package cost range")
    ax.text(0.5, -0.22, "Excludes HBM DRAM dies, test, NRE and vendor margin",
            transform=ax.transAxes, ha="center", fontsize=9)
    save_figure(fig, output_dir, "manufacturing_cost_scenarios")

    replay_path = output_dir / "gr00t_scheduler_replay.csv"
    if replay_path.exists():
        with replay_path.open(encoding="utf-8", newline="") as stream:
            replay = list(csv.DictReader(stream))
        labels = [record["scenario"] for record in replay]
        compute = [100.0 * float(record["compute_lane_utilization"]) for record in replay]
        service = [100.0 * float(record["service_lane_utilization"]) for record in replay]
        x = np.arange(len(labels))
        fig, ax = plt.subplots(figsize=(8, 5))
        ax.bar(x - 0.18, compute, width=0.36, label="Compute occupancy")
        ax.bar(x + 0.18, service, width=0.36, label="Compute/transfer service occupancy")
        ax.set_xticks(x, labels)
        ax.set(xlabel="Tensor-call arrival scenario", ylabel="Two-lane utilization (%)",
               title="GR00T normalization trace replay on LogicDieScheduler")
        ax.set_ylim(0, 105)
        ax.legend()
        save_figure(fig, output_dir, "scheduler_replay_utilization")


def placement_json(row, kind, cfg):
    return {
        "kind": kind,
        "logic_block_x_um": round(row["x_mm"] * 1000.0, 3),
        "logic_block_y_um": round(row["y_mm"] * 1000.0, 3),
        "balanced_score": row["scores"]["balanced"],
        "max_temp_c_unvalidated": row["max_temp_c"],
        "mean_channel_wire_um": row["wire_um"],
        "hard_constraints_satisfied": bool(row["hard_constraints_satisfied"]),
        "hard_constraint_violations": row["hard_constraint_violations"],
        "assumptions_file": "assumptions.json",
        "analysis_seed": cfg["analysis"]["random_seed"],
    }


def run(args):
    root = Path(__file__).resolve().parent
    cfg = load_config(args.assumptions or root / "assumptions.json")
    output_dir = args.output or root / "results"
    output_dir.mkdir(parents=True, exist_ok=True)
    for legacy in ("recommended_placement.json", "recommended_temperature_map.png",
                   "recommended_temperature_map.svg"):
        legacy_path = output_dir / legacy
        if legacy_path.exists():
            legacy_path.unlink()

    thermal_model = ThermalModel(cfg)
    coarse = evaluate_candidates(candidate_grid(cfg), cfg, thermal_model)
    centers = []
    for profile in cfg["cost_profiles"]:
        winner = min(coarse, key=lambda row: row["scores"][profile])
        centers.append((winner["x_mm"], winner["y_mm"]))
    fine_points = candidate_grid(cfg, centers)
    all_points = sorted(set((row["x_mm"], row["y_mm"]) for row in coarse) | set(fine_points))
    rows = evaluate_candidates(all_points, cfg, thermal_model)

    baseline = find_row(rows, 0.0, 0.0)
    eligible_rows = [row for row in rows if row["candidate_constraints_satisfied"]]
    if not eligible_rows:
        raise RuntimeError("No candidate satisfies all hard constraints")
    winners = {profile: min(eligible_rows, key=lambda row: row["scores"][profile])
               for profile in cfg["cost_profiles"]}
    pareto = pareto_rows(eligible_rows)
    sensitivity_records = sensitivity(rows, cfg)
    scenario_records = climate_scenarios(rows, cfg)
    mc_records, correlations = monte_carlo(rows, cfg)
    weight_records = weight_sweep(rows, cfg)
    cost_records = manufacturing_cost_scenarios(cfg)
    assumption_records = input_assumption_records(cfg)
    rc_records = routing_rc_records(cfg)

    robust_key = (mc_records[0]["x_mm"], mc_records[0]["y_mm"])
    provisional = find_row(rows, robust_key[0], robust_key[1])
    flat_rows = [flattened_row(row) for row in rows]
    write_csv(output_dir / "candidate_metrics.csv", flat_rows, list(flat_rows[0]))
    flat_pareto = [flattened_row(row) for row in pareto]
    write_csv(output_dir / "pareto_candidates.csv", flat_pareto, list(flat_pareto[0]))
    write_csv(output_dir / "sensitivity_oat.csv", sensitivity_records, list(sensitivity_records[0]))
    write_csv(output_dir / "power_cooling_scenarios.csv", scenario_records, list(scenario_records[0]))
    write_csv(output_dir / "monte_carlo_rank_stability.csv", mc_records, list(mc_records[0]))
    write_csv(output_dir / "weight_sweep.csv", weight_records, list(weight_records[0]))
    write_csv(output_dir / "manufacturing_cost_scenarios.csv", cost_records,
              list(cost_records[0]))
    write_csv(output_dir / "input_assumptions.csv", assumption_records,
              list(assumption_records[0]))
    write_csv(output_dir / "routing_layer_rc.csv", rc_records, list(rc_records[0]))
    with (output_dir / "gr00t_workload_summary.json").open("w", encoding="utf-8") as stream:
        json.dump(workload_summary(cfg), stream, indent=2)

    with (output_dir / "baseline_placement.json").open("w", encoding="utf-8") as stream:
        json.dump(placement_json(baseline, "center_baseline", cfg), stream, indent=2)
    provisional_data = placement_json(provisional, "provisional_monte_carlo_mode", cfg)
    provisional_data["final_recommendation"] = False
    provisional_data["reason"] = "RTL/PPA and thermal/package calibration are not stable"
    provisional_data["monte_carlo_mode_win_rate"] = mc_records[0]["win_rate"]
    provisional_data["monte_carlo_mode_win_rate_ci95"] = [
        mc_records[0]["win_rate_ci95_low"], mc_records[0]["win_rate_ci95_high"]]
    provisional_data["monte_carlo_top_k_rate"] = mc_records[0]["top_k_rate"]
    with (output_dir / "provisional_placement.json").open("w", encoding="utf-8") as stream:
        json.dump(provisional_data, stream, indent=2)

    observed_improvement = (
        baseline["scores"]["balanced"] - winners["balanced"]["scores"]["balanced"]
    ) / baseline["scores"]["balanced"]
    robustness_passed = (
        mc_records[0]["top_k_rate"] >= cfg["analysis"]["minimum_robust_top_k_rate"] and
        observed_improvement >= cfg["analysis"]["minimum_cost_improvement_fraction"] and
        winners["balanced"]["hard_constraints_satisfied"]
    )
    summary = {
        "candidate_count": len(rows),
        "candidate_constraint_feasible_count": len(eligible_rows),
        "signoff_hard_constraint_feasible_count": sum(
            row["hard_constraints_satisfied"] for row in rows),
        "pareto_count": len(pareto),
        "baseline": placement_json(baseline, "center_baseline", cfg),
        "final_recommendation_status": "withheld_pending_rtl_and_model_calibration",
        "provisional_monte_carlo_mode": provisional_data,
        "profile_winners": {
            name: placement_json(row, name, cfg) for name, row in winners.items()
        },
        "monte_carlo_samples": cfg["analysis"]["monte_carlo_samples"],
        "weight_sweep_cases": len(weight_records),
        "manufacturing_cost_scenarios": cost_records,
        "power_cooling_scenarios": scenario_records,
        "monte_carlo_top": mc_records[:10],
        "rank_stability_best_mean_rank": min(
            mc_records, key=lambda record: record["mean_rank"]),
        "mean_spearman_cost_correlations": correlations,
        "robustness_gate": {
            "required_top_k_rate": cfg["analysis"]["minimum_robust_top_k_rate"],
            "observed_top_k_rate": mc_records[0]["top_k_rate"],
            "required_cost_improvement_fraction": cfg["analysis"]["minimum_cost_improvement_fraction"],
            "observed_balanced_improvement_fraction": observed_improvement,
            "passed": robustness_passed
        },
        "warnings": [
            "Temperature is from an uncalibrated compact RC model, not signoff thermal analysis.",
            "TSV, microbump, PHY, package dimensions, and power are explicit assumptions.",
            "The GDS is a reduced logic block and has negative setup slack at the current 10 ns constraint.",
            "GR00T experiment uses deterministic synthetic FP16 normalization inputs, not full BF16 inference activations."
        ]
    }
    with (output_dir / "summary.json").open("w", encoding="utf-8") as stream:
        json.dump(summary, stream, indent=2)
    recommendation_status = {
        "date": cfg["analysis_date"],
        "status": summary["final_recommendation_status"],
        "final_recommendation": False,
        "authoritative_summary": "results/summary.json",
        "provisional_coordinate_only": provisional_data,
        "signoff_hard_constraint_feasible_count": summary["signoff_hard_constraint_feasible_count"],
        "robustness_gate": summary["robustness_gate"],
        "reason": [
            "Global RTL timing is not closed.",
            "The balanced optimum does not improve on the center baseline.",
            "Package, power and thermal inputs are not calibrated."
        ]
    }
    with (root / "recommendation.json").open("w", encoding="utf-8") as stream:
        json.dump(recommendation_status, stream, indent=2)

    make_plots(rows, pareto, sensitivity_records, weight_records, mc_records,
               cost_records, provisional, thermal_model, output_dir)
    print(json.dumps(summary, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assumptions", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
