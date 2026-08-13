#!/usr/bin/env python3
"""Collect existing Sky130 adapter/PCU evidence into the hardware-cost gate."""
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

from physical_feasibility_contract import ROOT, digest, require_valid_physical_feasibility


DEFAULT_EVIDENCE = ROOT / "reports" / "groot_normalization" / "physical_feasibility"
DEFAULT_OUTPUT = ROOT / "reports" / "hardware_cost_physical_feasibility" / "physical_feasibility.json"
DEFAULT_REPORT = ROOT / "reports" / "hardware_cost_physical_feasibility" / "physical_feasibility_report.md"
LOGIC_DIE_BUDGET_UM2 = 91_800_000.0


def locator(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def source(path: Path, role: str) -> dict:
    return {"role": role, "path": locator(path), "sha256": digest(path), "bytes": path.stat().st_size, "claim_class": "derived"}


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def file_ends_with(path: Path, suffix: bytes) -> bool:
    if not path.is_file() or path.stat().st_size < len(suffix):
        return False
    with path.open("rb") as stream:
        stream.seek(-len(suffix), 2)
        return stream.read() == suffix


def last_float(pattern: str, value: str):
    matches = re.findall(pattern, value, re.MULTILINE | re.IGNORECASE)
    return float(matches[-1]) if matches else None


def last_int(pattern: str, value: str):
    result = last_float(pattern, value)
    return int(result) if result is not None else None


def max_float(pattern: str, value: str):
    matches = re.findall(pattern, value, re.MULTILINE | re.IGNORECASE)
    return max((float(item) for item in matches), default=None)


def mapped_cells(value: str):
    matches = re.findall(r"^\s*(\d+)\s+[0-9.E+\-]+\s+cells\s*$", value, re.MULTILINE)
    return int(matches[-1]) if matches else None


def mapping(top: str, yosys: str, sta: str = "", reference_period: float | None = None) -> dict:
    completed = "End of script." in yosys and "Found and reported 0 problems." in yosys
    area = last_float(r"Chip area for (?:top )?module '[^']+':\s*([0-9.]+)", yosys)
    sequential = last_float(r"used for sequential elements:\s*([0-9.]+)", yosys)
    slack = last_float(r"^worst slack(?:\s+max)?\s+(-?[0-9.]+)", sta)
    critical = max_float(r"^\s*([0-9.]+)\s+data arrival time\s*$", sta)
    clock_period = max_float(r"^\s*([0-9.]+)\s+[0-9.]+\s+clock clk \(rise edge\)", sta)
    startpoints = re.findall(r"^Startpoint:\s*(.+)$", sta, re.MULTILINE)
    endpoints = re.findall(r"^Endpoint:\s*(.+)$", sta, re.MULTILINE)
    unconstrained_sections = re.findall(r"PHYS_FEAS_UNCONSTRAINED_BEGIN\s*(.*?)\s*PHYS_FEAS_UNCONSTRAINED_END", sta, re.DOTALL)
    setup_sections = re.findall(r"PHYS_FEAS_CHECK_SETUP_BEGIN\s*(.*?)\s*PHYS_FEAS_CHECK_SETUP_END", sta, re.DOTALL)
    if unconstrained_sections:
        unconstrained_text = unconstrained_sections[-1].strip()
        count_match = re.search(r"There (?:are|is)\s+(\d+)\s+unconstrained endpoints?", unconstrained_text, re.IGNORECASE)
        # Legacy logs used report_checks -unconstrained here.  That option
        # includes unconstrained paths but does not select only those paths;
        # a normal MET path therefore must not be counted as unconstrained.
        if count_match:
            unconstrained = int(count_match.group(1))
        elif not unconstrained_text or "No paths found" in unconstrained_text:
            unconstrained = 0
        elif setup_sections and not setup_sections[-1].strip():
            unconstrained = 0
        else:
            unconstrained = None
    else:
        unconstrained = 0 if setup_sections and not setup_sections[-1].strip() else None
    structural = 0 if completed else None
    quantitative_complete = all(value is not None for value in (mapped_cells(yosys), area, critical))
    return {
        "status": "PASS" if completed and quantitative_complete and (not sta or unconstrained == 0) else "PENDING",
        "calibration": "technology_mapped" if completed else "unavailable",
        "top": top, "completed": completed, "mapped_cells": mapped_cells(yosys), "mapped_area_um2": area,
        "sequential_area_um2": sequential, "unmapped_cells": structural, "blackboxes": structural,
        "inferred_latches": structural, "combinational_loops": structural,
        "clock_period_ns": clock_period, "critical_path_ns": critical, "worst_slack_ns": slack,
        "timing_target_met": None if slack is None else slack >= 0, "unconstrained_path_count": unconstrained,
        "reference_clock_period_ns": reference_period,
        "reference_timing_target_met": None if critical is None or reference_period is None else critical <= reference_period,
        "critical_startpoint": startpoints[0] if startpoints else None, "critical_endpoint": endpoints[0] if endpoints else None,
    }


def parse_high_fanout(route: str) -> list[dict]:
    found = {}
    for net, fanout in re.findall(r"Net\s+(.+?)\s+has a large fanout of\s+(\d+)\s+terminals", route):
        found[net] = max(found.get(net, 0), int(fanout))
    return [{"net": net, "fanout": fanout} for net, fanout in sorted(found.items(), key=lambda item: (-item[1], item[0]))]


def parse_skipped_fanout(route: str) -> list[dict]:
    result = []
    for net, fanout in re.findall(r"Skipping net\s+(.+?)\s+with\s+(\d+)\s+terminals", route):
        allowlisted = net in {"clk_i", "rst_ni"} or net.endswith("/one_")
        result.append({"net": net, "fanout": int(fanout), "allowlisted": allowlisted})
    return sorted(result, key=lambda item: (-item["fanout"], item["net"]))


def critical_path_cells(sta: str) -> list[str]:
    sections = re.findall(r"PHYS_FEAS_MAX_PATH_BEGIN\s*(.*?)\s*PHYS_FEAS_MAX_PATH_END", sta, re.DOTALL)
    if not sections or "Startpoint:" not in sections[-1]:
        return []
    first_path = sections[-1].split("Startpoint:", 1)[1].split("Startpoint:", 1)[0]
    result = []
    for cell_type in re.findall(r"\((sky130_fd_sc_hd__[^)]+)\)", first_path):
        if not result or result[-1] != cell_type:
            result.append(cell_type)
    return result


def congestion_hotspots(value: str) -> dict:
    """Summarize only the violation blocks captured in a CUGR report."""
    directions: Counter[str] = Counter()
    layers: Counter[str] = Counter()
    categories: Counter[str] = Counter()
    banks: Counter[int] = Counter()
    tiles: Counter[tuple[int, int]] = Counter()
    category_patterns = {
        "pcu_apply": r"(?:/|\.)u_apply/",
        "pcu_reduction": r"(?:reduction_data|/u_(?:reduction|reduce)/)",
        "bank_interface": r"(?:read_data_i|reduction_data|replay_(?:x|gamma|beta)|cmd_|write|wb_)",
        "adapter_buffer": r"u_adapter/(?:x_word_q|affine_word_q|wb_word_q)",
        "wide_mux_select": r"(?:replay_|mux|shift|select|read_data_i)",
        "clock": r"net:clk_i(?:\s|$)",
    }
    blocks = re.findall(
        r"^violation type:\s*(.*?)\n(.*?)(?=^violation type:|\Z)",
        value,
        re.MULTILINE | re.DOTALL,
    )
    for violation_type, body in blocks:
        direction = violation_type.removesuffix(" congestion").strip().lower()
        directions[direction] += 1
        source_match = re.search(r"^\s*srcs:\s*(.*)$", body, re.MULTILINE)
        sources = source_match.group(1) if source_match else ""
        layer_match = re.search(r"\bon Layer\s+(\S+)", body)
        if layer_match:
            layers[layer_match.group(1)] += 1
        for name, pattern in category_patterns.items():
            if re.search(pattern, sources, re.IGNORECASE):
                categories[name] += 1
        for bank in re.findall(r"g_bank\\?\[(\d+)\\?\]", sources):
            banks[int(bank)] += 1
        bbox = re.search(
            r"bbox\s*=\s*\(([0-9.]+),\s*([0-9.]+)\)\s*-\s*\(([0-9.]+),\s*([0-9.]+)\)",
            body,
        )
        if bbox:
            x_center = (float(bbox.group(1)) + float(bbox.group(3))) / 2.0
            y_center = (float(bbox.group(2)) + float(bbox.group(4))) / 2.0
            tiles[(int(x_center // 500) * 500, int(y_center // 500) * 500)] += 1
    return {
        "analysis_scope": "captured_congestion_report",
        "captured_violation_blocks": len(blocks),
        "direction_block_counts": dict(sorted(directions.items())),
        "layer_block_counts": dict(sorted(layers.items())),
        "category_block_counts": dict(sorted(categories.items())),
        "top_bank_source_mentions": [
            {"bank": bank, "source_net_mentions": count}
            for bank, count in banks.most_common(8)
        ],
        "top_500um_tiles": [
            {"x_min_um": x, "y_min_um": y, "violation_blocks": count}
            for (x, y), count in tiles.most_common(8)
        ],
    }


def latest_completed_route(evidence_dir: Path) -> tuple[str, Path, Path, Path, Path]:
    """Select the newest terminal route attempt; never promote a partial run."""
    variants = (
        ("v5", "V5_ROUTE_PASS", "run_normalization_hbm_v5_route.sh"),
        ("v4", "V4_ROUTE_PASS", "run_normalization_hbm_v4_route.sh"),
        ("v3", "V3_ROUTE_PASS", "run_normalization_hbm_v3_route.sh"),
        ("v2", "V2_ROUTE_PASS", "run_normalization_hbm_v2_route.sh"),
    )
    for revision, marker, runner in variants:
        route = evidence_dir / f"logic_die_normalization_hbm_top_{revision}_route.log"
        guide = evidence_dir / f"logic_die_normalization_hbm_top_{revision}.route_guide"
        congestion = evidence_dir / f"logic_die_normalization_hbm_top_{revision}.congestion.rpt"
        route_text = text(route)
        route_measurement_complete = marker in route_text or (
            "Iterative RRR finished with congestion remaining" in route_text
            and file_ends_with(guide, b")\n")
        )
        if (
            route_measurement_complete
            and guide.is_file() and guide.stat().st_size > 0
            and congestion.is_file() and congestion.stat().st_size > 0
        ):
            return revision, route, guide, congestion, ROOT / "verification/groot_normalization" / runner
    # Preserve the established v2 result if no newer attempt is terminal.
    return (
        "v2",
        evidence_dir / "logic_die_normalization_hbm_top_v2_route.log",
        evidence_dir / "logic_die_normalization_hbm_top_v2.route_guide",
        evidence_dir / "logic_die_normalization_hbm_top_v2.congestion.rpt",
        ROOT / "verification/groot_normalization/run_normalization_hbm_v2_route.sh",
    )


def collect(evidence_dir=DEFAULT_EVIDENCE) -> dict:
    evidence_dir = Path(evidence_dir)
    route_revision, route_path, guide_path, congestion_path, route_flow_path = latest_completed_route(evidence_dir)
    paths = {
        "pf0": ROOT / "reports/groot_normalization/hbm_boundary_adapter/05_completion_audit.md",
        "adapter_rtl": ROOT / "rtl/normalization_hbm_boundary_adapter.sv",
        "integrated_rtl": ROOT / "rtl/logic_die_normalization_hbm_top.sv",
        "adapter_yosys": evidence_dir / "normalization_hbm_boundary_adapter_sky130_yosys.log",
        "adapter_netlist": evidence_dir / "normalization_hbm_boundary_adapter_sky130.v",
        "adapter_sta": evidence_dir / "normalization_hbm_boundary_adapter_sky130_sta.log",
        "integrated_yosys": evidence_dir / "logic_die_normalization_hbm_top_sky130_yosys.log",
        "integrated_netlist": evidence_dir / "logic_die_normalization_hbm_top_sky130.v",
        "integrated_sta": evidence_dir / "logic_die_normalization_hbm_top_sky130_sta.log",
        "placement": evidence_dir / "logic_die_normalization_hbm_top_v2_repair_legalize.log",
        "placed_db": evidence_dir / "logic_die_normalization_hbm_top_v2_repaired_legal.odb",
        "placed_sdc": evidence_dir / "logic_die_normalization_hbm_top_v2_repaired_legal.sdc",
        "postrepair_fanout": evidence_dir / "logic_die_normalization_hbm_top_v2_postrepair_audit.log",
        "constraint_audit": evidence_dir / "logic_die_normalization_hbm_top_constraint_audit.log",
        "route": route_path,
        "guide": guide_path,
        "congestion": congestion_path,
        "config": ROOT / "flow/designs/sky130hd/normalization_hbm_feasibility_v2/config.mk",
        "sdc": ROOT / "flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc",
        "adapter_flow": ROOT / "verification/groot_normalization/run_normalization_adapter_sky130_feasibility.sh",
        "mapping_flow": ROOT / "verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh",
        "placement_flow": ROOT / "verification/groot_normalization/run_normalization_hbm_v2_repair_legalize.sh",
        "route_flow": route_flow_path,
        "proposal": ROOT / "hardware_cost/hardware_cost_pipeline_revision_proposal_physical_feasibility_gate.md",
    }
    values = {name: text(path) for name, path in paths.items()}
    reference_period = last_float(r"create_clock[^\n]*-period\s+([0-9.]+)", values["sdc"])
    adapter = mapping("normalization_hbm_boundary_adapter", values["adapter_yosys"], values["adapter_sta"], reference_period)
    integrated = mapping("logic_die_normalization_hbm_top", values["integrated_yosys"], values["integrated_sta"], reference_period)
    placement_text = values["placement"]
    route = values["route"]
    route_metrics = route + "\n" + values["congestion"]
    integrated_netlist_hash = digest(paths["integrated_netlist"]) if paths["integrated_netlist"].is_file() else None
    sta_hash_marker = last_match(r"^PF_SOURCE_NETLIST_SHA256=([0-9a-f]{64})$", values["integrated_sta"])
    sta_matches = None if not paths["integrated_sta"].is_file() else sta_hash_marker == integrated_netlist_hash
    placed_db_hash = digest(paths["placed_db"]) if paths["placed_db"].is_file() else None
    placed_sdc_hash = digest(paths["placed_sdc"]) if paths["placed_sdc"].is_file() else None
    postrepair_db_marker = last_match(r"^PF_V2_POSTREPAIR_SOURCE_DB_SHA256=([0-9a-f]{64})$", values["postrepair_fanout"])
    postrepair_sdc_marker = last_match(r"^PF_V2_POSTREPAIR_SOURCE_SDC_SHA256=([0-9a-f]{64})$", values["postrepair_fanout"])
    postrepair_matches_placement = (
        None if not values["postrepair_fanout"] else
        postrepair_db_marker == placed_db_hash and postrepair_sdc_marker == placed_sdc_hash
    )
    route_db_marker = last_match(r"^PF_V\d+_SOURCE_DB_SHA256=([0-9a-f]{64})$", values["route"])
    route_sdc_marker = last_match(r"^PF_V\d+_SOURCE_SDC_SHA256=([0-9a-f]{64})$", values["route"])
    placement_hash = digest(paths["placement"]) if paths["placement"].is_file() else None
    placement_fresh = paths["placement"].stat().st_mtime >= paths["integrated_netlist"].stat().st_mtime if paths["placement"].is_file() and paths["integrated_netlist"].is_file() else None
    route_matches_placement = None if not paths["route"].is_file() else route_db_marker == placed_db_hash and route_sdc_marker == placed_sdc_hash
    route_fresh = None if not paths["route"].is_file() else route_matches_placement is True and placement_fresh is True
    stale_evidence = []
    if paths["integrated_sta"].is_file() and sta_matches is not True:
        stale_evidence.append("integrated_sta")
    if paths["placement"].is_file() and placement_fresh is not True:
        stale_evidence.append("placement")
    if paths["route"].is_file() and route_fresh is not True:
        stale_evidence.append("global_routing")
    if values["postrepair_fanout"] and postrepair_matches_placement is not True:
        stale_evidence.append("postrepair_fanout")
    high_fanout = parse_high_fanout(route)
    skipped_fanout = parse_skipped_fanout(route)
    fanout_skip_threshold = last_int(r"^PF_(?:V\d+_)?SKIPPED_FANOUT_THRESHOLD=(\d+)$", route)
    initial_violations = last_int(r"^\s*0\s*\|\s*(\d+)\s*\|", placement_text)
    final_violations = last_int(r"^\s*\d+\s*\|\s*(0)\s*\|\s*0\s*\|", placement_text)
    placement_completed = ("V2_REPAIR_LEGAL_PASS" in placement_text or "REPAIR_LEGAL_PASS" in placement_text) and final_violations == 0
    routing_completed = bool(re.search(r"^(?:V\d+_ROUTE_PASS|ROUTE_FROM_LEGAL_PASS|COARSE_ROUTE_PASS)$", route, re.MULTILINE)) or (
        "Iterative RRR finished with congestion remaining" in route
        and paths["guide"].is_file() and paths["guide"].stat().st_size > 0
        and paths["congestion"].is_file() and paths["congestion"].stat().st_size > 0
        and file_ends_with(paths["guide"], b")\n")
    )
    route_exit_code = last_int(r"^PF_V\d+_OPENROAD_EXIT_CODE=(\d+)$", route)
    route_execution_clean = None if route_exit_code is None else route_exit_code == 0
    all_skipped_allowlisted = all(item["allowlisted"] for item in skipped_fanout) if skipped_fanout else (True if routing_completed else None)
    total_congestion = re.findall(r"^Total\s+\d+\s+\d+\s+[0-9.]+%\s+\d+\s*/\s*\d+\s*/\s*(\d+)\s*$", route_metrics, re.MULTILINE)
    overflow_matches = re.findall(r"(?:total\s+)?overflow[^0-9]*(\d+)", route_metrics, re.IGNORECASE)
    overflow = int(total_congestion[-1]) if total_congestion else (int(overflow_matches[-1]) if overflow_matches else None)
    congestion_violation_count = len(re.findall(r"^violation type:", values["congestion"], re.MULTILINE))
    hotspot_summary = congestion_hotspots(values["congestion"])
    max_local_overuse = max(
        (int(item) for item in re.findall(r"congestion:\s*(\d+)", values["congestion"])),
        default=None,
    )
    if overflow is None and routing_completed and paths["congestion"].is_file():
        overflow = congestion_violation_count
    congestion_remaining = last_int(r"congestion remaining\s*\((\d+)\)", route)
    prior_route_log = text(evidence_dir / "logic_die_normalization_hbm_top_v2_route.log")
    prior_congestion_text = text(evidence_dir / "logic_die_normalization_hbm_top_v2.congestion.rpt")
    prior_residual = last_int(r"congestion remaining\s*\((\d+)\)", prior_route_log) if route_revision != "v2" else None
    prior_violation_count = len(re.findall(r"^violation type:", prior_congestion_text, re.MULTILINE)) if route_revision != "v2" and prior_congestion_text else None
    residual_reduction_pct = (
        100.0 * (prior_residual - congestion_remaining) / prior_residual
        if prior_residual and congestion_remaining is not None else None
    )
    layer_usage = [float(item) for item in re.findall(r"^(?:li1|met\d+)\s+\d+\s+\d+\s+([0-9.]+)%", route_metrics, re.MULTILINE)]
    max_layer_usage = max(layer_usage, default=None)
    routed_nets = last_int(r"Routed nets:\s*(\d+)", route)
    severe_congestion = None if overflow is None else overflow > 0
    repair_area_increase = last_float(r"^\s*final\s*\|\s*\+([0-9.]+)%", placement_text)
    repair_resized = last_int(r"Resized\s+(\d+)\s+instances", placement_text)
    repair_buffers = last_int(r"Inserted\s+(\d+)\s+buffers", placement_text)
    repair_nets = last_int(r"Inserted\s+\d+\s+buffers\s+in\s+(\d+)\s+nets", placement_text)
    remaining_slew = last_int(r"Found\s+(\d+)\s+slew violations", placement_text)
    remaining_fanout = last_int(r"Found\s+(\d+)\s+fanout violations", placement_text)
    remaining_cap = last_int(r"Found\s+(\d+)\s+capacitance violations", placement_text)
    repair_audited = repair_buffers is not None
    postrepair_max_fanout = last_int(r"POSTREPAIR_MAX_DATA_FANOUT\s+(\d+)", values["postrepair_fanout"]) if postrepair_matches_placement is True else None
    postrepair_max_net = last_match(r"^POSTREPAIR_MAX_DATA_FANOUT\s+\d+\s+(.+)$", values["postrepair_fanout"]) if postrepair_matches_placement is True else None

    pf0_pass = paths["pf0"].is_file() and "PASS" in values["pf0"]
    pf1_pass = adapter["status"] == "PASS"
    pf2_pass = integrated["status"] == "PASS" and sta_matches is True
    pf3_pass = placement_completed and placement_fresh is True
    guide_available = paths["guide"].is_file() and paths["guide"].stat().st_size > 0
    congestion_available = paths["congestion"].is_file() and paths["congestion"].stat().st_size > 0
    pf4_pass = routing_completed and route_execution_clean is True and route_fresh is True and guide_available and congestion_available and overflow == 0 and severe_congestion is False and all_skipped_allowlisted is True
    pf4_fail = routing_completed and overflow not in (None, 0)

    if pf2_pass:
        pf2_blockers = []
    elif sta_matches is False:
        pf2_blockers = ["Integrated STA evidence predates the current mapped netlist."]
    elif integrated["unconstrained_path_count"] not in (0,):
        pf2_blockers = ["Integrated STA has missing or non-zero unconstrained-endpoint evidence."]
    else:
        pf2_blockers = ["Integrated mapping or constrained STA evidence is incomplete."]

    gates = {
        "PF-0": {"status": "PASS" if pf0_pass else "PENDING", "criterion": "RTL behavior, protocol, backpressure, and generic structural checks pass.", "evidence": [locator(paths["pf0"])] if paths["pf0"].is_file() else [], "blockers": [] if pf0_pass else ["PF-0 completion audit is unavailable or incomplete."]},
        "PF-1": {"status": "PASS" if pf1_pass else "PENDING", "criterion": "Standalone adapter maps to Sky130 and exposes a constrained STA path with no unconstrained paths.", "evidence": [locator(paths[x]) for x in ("adapter_yosys", "adapter_sta") if paths[x].is_file()], "blockers": [] if pf1_pass else ["Standalone mapping or constrained STA evidence is incomplete."]},
        "PF-2": {"status": "PASS" if pf2_pass else "PENDING", "criterion": "Integrated PCU plus adapter maps and has an integrated constrained-path audit.", "evidence": [locator(paths[x]) for x in ("integrated_yosys", "integrated_sta") if paths[x].is_file()], "blockers": pf2_blockers},
        "PF-3": {"status": "PASS" if pf3_pass else "PENDING", "criterion": "Coarse detailed placement from the current mapped netlist converges to zero legalization violations.", "evidence": [locator(paths["placement"])] if paths["placement"].is_file() else [], "blockers": [] if pf3_pass else (["Placement evidence predates the current integrated mapped netlist."] if placement_completed and placement_fresh is False else ["Legal placement has not converged or its result is unavailable."])},
        "PF-4": {"status": "PASS" if pf4_pass else ("FAIL" if pf4_fail else "PENDING"), "criterion": "Global routing completes with a guide, congestion report, and zero overflow.", "evidence": [locator(paths[x]) for x in ("route", "guide", "congestion") if paths[x].is_file()], "blockers": [] if pf4_pass else ([f"Global routing completed with overflow={overflow}."] if pf4_fail else ["Global routing has no terminal PASS marker and complete route artifacts yet."])},
    }
    blockers = []
    risks = []
    if not pf2_pass:
        blockers.extend(pf2_blockers)
    if not pf4_pass:
        blockers.append(
            f"Global routing completed but severe congestion remains ({congestion_remaining or overflow} reported residual; "
            f"{congestion_violation_count} detailed violations captured)."
            if routing_completed and overflow not in (None, 0)
            else "Global-routing completion, congestion, and overflow evidence are incomplete."
        )
    if routing_completed and route_execution_clean is not True:
        blockers.append(
            "The latest route measurement produced a complete guide/congestion report but did not emit a clean OpenROAD exit code."
        )
    if stale_evidence:
        blockers.append("Revision coherence failed for: " + ", ".join(stale_evidence) + ".")
    if adapter["reference_timing_target_met"] is False:
        risks.append(f"Standalone adapter misses the {reference_period:g} ns project reference: critical path {adapter['critical_path_ns']:.2f} ns. Timing closure is outside this gate.")
    if integrated["reference_timing_target_met"] is False:
        risks.append(f"Integrated PCU+adapter misses the {reference_period:g} ns project reference: critical path {integrated['critical_path_ns']:.2f} ns. Timing closure is outside this gate.")
    if high_fanout:
        risks.append(f"High-fanout routing risk is observed; maximum reported fanout is {high_fanout[0]['fanout']} terminals.")
    if repair_audited and any(value for value in (remaining_slew, remaining_fanout, remaining_cap)):
        risks.append(
            "Coarse repair leaves "
            f"{remaining_slew or 0} slew, {remaining_fanout or 0} fanout, and "
            f"{remaining_cap or 0} capacitance violations; closure is outside this gate."
        )
    risks.append(
        "The documented 145,852 generic wire bits indicate wide-datapath connectivity pressure, "
        "but are not a direct routing-congestion measurement."
    )
    statuses = [gate["status"] for gate in gates.values()]
    status = "FAIL" if "FAIL" in statuses else ("PENDING" if "PENDING" in statuses else "PASS")
    freeze = status == "PASS" and integrated["unconstrained_path_count"] == 0 and overflow == 0
    mapped_area = integrated["mapped_area_um2"]
    core_area = last_float(r"Core area:\s*([0-9.]+)\s*um\^2", placement_text)
    adapter_dffs = last_int(r"^\s*(\d+)\s+[0-9.E+\-]+\s+sky130_fd_sc_hd__dfrtp_1", values["adapter_yosys"])
    dff_cell_area = adapter["sequential_area_um2"] / adapter_dffs if adapter_dffs and adapter["sequential_area_um2"] else None
    buffer_bits = 3 * 16 * 256
    buffer_area = buffer_bits * dff_cell_area if dff_cell_area is not None else None
    # The wide-interface risk belongs to the integrated PCU-adapter cone, not
    # merely to the standalone adapter path.
    path_cells = critical_path_cells(values["integrated_sta"])
    document = {
        "schema_version": 1, "status": status, "rtl_freeze_allowed": freeze, "production_signoff": "NOT_TARGETED",
        "status_matrix": {"RTL_FEASIBILITY": gates["PF-0"]["status"], "LOGICAL_SYNTHESIS": gates["PF-0"]["status"],
                          "ADAPTER_TECH_MAPPING": gates["PF-1"]["status"], "INTEGRATED_TECH_MAPPING": gates["PF-2"]["status"],
                          "COARSE_PLACEMENT": gates["PF-3"]["status"], "GLOBAL_ROUTING": gates["PF-4"]["status"],
                          "PHYSICAL_FEASIBILITY": status, "PRODUCTION_SIGNOFF": "NOT_TARGETED"},
        "claim_boundary": (
            "Lightweight Sky130 technology-mapping, coarse-placement, and global-routing feasibility only; "
            "not CTS, detailed route, extraction, IR/EM, DRC/LVS, power, thermal, or silicon signoff."
            if pf4_pass else
            "Lightweight Sky130 technology-mapping and legal coarse placement only. Global-routing "
            "feasibility remains unestablished until PF-4 passes; this is not CTS, detailed route, "
            "extraction, IR/EM, DRC/LVS, power, thermal, or silicon signoff."
        ),
        "calibration": "global_routed" if pf4_pass else ("placed" if pf3_pass else ("technology_mapped" if pf1_pass else "unavailable")),
        "claim_class": "derived",
        "toolchain": {"pdk": "sky130", "library": "sky130_fd_sc_hd", "process_corner": "tt", "voltage_V": 1.8, "temperature_C": 25.0,
                      "yosys": last_match(r"^(Yosys .+)$", values["adapter_yosys"]), "openroad": last_match(r"^(OpenROAD .+)$", values["adapter_sta"])},
        "revision_coherence": {"status": "PASS" if not stale_evidence and integrated_netlist_hash else "PENDING",
                               "integrated_netlist_sha256": integrated_netlist_hash,
                               "integrated_sta_matches_netlist": sta_matches,
                               "placement_log_sha256": placement_hash,
                               "placement_newer_than_mapping": placement_fresh,
                               "postrepair_fanout_matches_placement": postrepair_matches_placement,
                               "global_route_matches_placement": route_matches_placement,
                               "global_route_newer_than_mapping": route_fresh,
                               "stale_evidence": stale_evidence},
        "gates": gates, "adapter_mapping": adapter, "integrated_mapping": integrated,
        "placement": {"status": "PASS" if pf3_pass else "PENDING", "calibration": "placed" if placement_completed else "unavailable",
                      "completed": placement_completed, "core_area_um2": last_float(r"Core area:\s*([0-9.]+)\s*um\^2", placement_text),
                      "movable_area_um2": last_float(r"Movable instances area:\s*([0-9.]+)", placement_text),
                      "fixed_area_um2": last_float(r"Fixed instances area within core:\s*([0-9.]+)", placement_text),
                      "utilization_pct": last_float(r"Utilization:\s*([0-9.]+)%", placement_text), "initial_violations": initial_violations,
                      "final_violations": final_violations, "average_displacement_um": last_float(r"average displacement\s+([0-9.]+)\s+u", placement_text),
                      "max_displacement_um": last_float(r"max displacement\s+([0-9.]+)\s+u", placement_text)},
        "global_routing": {"status": gates["PF-4"]["status"], "calibration": "global_routed" if routing_completed else ("placed" if placement_completed else "unavailable"),
                           "route_revision": route_revision,
                           "pin_model": last_match(r"^PF_V\d+_PIN_MODEL=(.+)$", route),
                           "signal_layers": last_match(r"^PF_V\d+_SIGNAL_LAYERS=(.+)$", route),
                           "congestion_iterations": last_int(r"^PF_V\d+_CONGESTION_ITERATIONS=(\d+)$", route),
                           "global_router": last_match(r"^PF_V\d+_GLOBAL_ROUTER=(.+)$", route),
                           "openroad_exit_code": route_exit_code,
                           "execution_clean": route_execution_clean,
                           "prior_route_comparison": {
                               "revision": "v2" if prior_residual is not None else None,
                               "congestion_remaining": prior_residual,
                               "congestion_violation_count": prior_violation_count,
                               "residual_reduction_pct": residual_reduction_pct,
                           },
                           "completed": routing_completed, "overflow_count": overflow, "max_layer_usage_pct": max_layer_usage,
                           "congestion_violation_count": congestion_violation_count if congestion_available else None,
                           "max_local_overuse": max_local_overuse, "congestion_remaining": congestion_remaining,
                           "routed_nets": routed_nets, "severe_congestion": severe_congestion,
                           "congestion_report_available": congestion_available, "guide_available": guide_available,
                           "fanout_skip_threshold": fanout_skip_threshold, "skipped_large_fanout_nets": skipped_fanout,
                           "all_skipped_nets_allowlisted": all_skipped_allowlisted,
                           "max_observed_fanout": max([postrepair_max_fanout or 0] + [item["fanout"] for item in high_fanout] + [item["fanout"] for item in skipped_fanout]) or None,
                           "high_fanout_nets": high_fanout,
                           "congestion_hotspots": hotspot_summary},
        "structural": {"status": "PASS" if integrated["completed"] and integrated["unconstrained_path_count"] == 0 else "PENDING",
                       "unmapped_cells": integrated["unmapped_cells"], "unresolved_blackboxes": integrated["blackboxes"],
                       "unintended_latches": integrated["inferred_latches"], "combinational_loops": integrated["combinational_loops"],
                       "unconstrained_paths": integrated["unconstrained_path_count"]},
        "fanout": {"status": "PASS" if postrepair_max_fanout is not None or high_fanout or skipped_fanout or repair_audited else "PENDING",
                   "max_fanout": postrepair_max_fanout if postrepair_max_fanout is not None else (high_fanout[0]["fanout"] if high_fanout else (skipped_fanout[0]["fanout"] if skipped_fanout else None)),
                   "max_fanout_net": postrepair_max_net if postrepair_max_fanout is not None else (high_fanout[0]["net"] if high_fanout else (skipped_fanout[0]["net"] if skipped_fanout else None)),
                   "source_stage": "postrepair_data_fanout_audit" if postrepair_max_fanout is not None else ("global_route_initialization" if high_fanout or skipped_fanout else ("repair_design" if repair_audited else None)),
                   "repair_area_increase_pct": repair_area_increase,
                   "repair_resized_instances": repair_resized, "repair_inserted_buffers": repair_buffers,
                   "repair_repaired_nets": repair_nets, "remaining_slew_violations": remaining_slew,
                   "remaining_fanout_violations": remaining_fanout,
                   "remaining_capacitance_violations": remaining_cap},
        "wide_interface": {"adapter_port_bits": last_int(r"^\s*(\d+)\s+- port bits", values["adapter_yosys"]),
                           "generic_wire_bits": 145852, "generic_wire_bits_is_direct_congestion_metric": False,
                           "largest_interface_bits": 2048, "largest_interface_name": "replay_x_o/replay_gamma_o/replay_beta_o",
                           "maximum_fanin": None, "critical_cone_cell_count": len(path_cells) or None,
                           "logic_depth": len(path_cells) or None, "critical_path_cell_sequence": path_cells,
                           "risk": "HIGH" if high_fanout else "MEDIUM"},
        "buffer_implementation": {"logical_bits": buffer_bits, "implementation_type": "register_array",
                                  "memory_macro_inferred": False, "mapped_register_count": buffer_bits,
                                  "top_sequential_cells": adapter_dffs, "mapped_area_um2": buffer_area,
                                  "share_of_adapter_area_pct": 100.0 * buffer_area / adapter["mapped_area_um2"] if buffer_area and adapter["mapped_area_um2"] else None,
                                  "share_of_integrated_area_pct": 100.0 * buffer_area / mapped_area if buffer_area and mapped_area else None,
                                  "risk": "HIGH"},
        "logic_die_budget": {"assumed_usable_area_um2": LOGIC_DIE_BUDGET_UM2, "mapped_area_um2": mapped_area,
                             "mapped_utilization_pct": 100.0 * mapped_area / LOGIC_DIE_BUDGET_UM2 if mapped_area is not None else None,
                             "placed_core_area_um2": core_area,
                             "placed_footprint_utilization_pct": 100.0 * core_area / LOGIC_DIE_BUDGET_UM2 if core_area is not None else None,
                             "within_budget": core_area <= LOGIC_DIE_BUDGET_UM2 if core_area is not None else None},
        "evidence": [source(path, role) for role, path in paths.items() if path.is_file() and path.stat().st_size > 0], "blockers": blockers, "risks": risks,
        "notes": ["Timing closure is intentionally not performed; the project-reference timing miss is retained as a risk, not as a PF0-PF4 freeze blocker.",
                  "Buffer area is the derived storage-cell-only area: 12,288 mapped DFF bits times the mapped DFF cell area. It excludes buffer mux/control logic, clock-tree, placement whitespace, and routing.",
                  "The 40 ns project timing target is reported as a risk metric only; target clock closure is outside this lightweight gate.",
                  "The 91.8 mm^2 logic-die value is an explicit project proxy from the flow configuration, not a vendor die-area disclosure."],
    }
    require_valid_physical_feasibility(document)
    return document


def last_match(pattern: str, value: str):
    matches = re.findall(pattern, value, re.MULTILINE)
    return matches[-1].strip() if matches else None


def write_report(document: dict, path: Path) -> None:
    def show(value, digits=None):
        if value is None:
            return "unavailable"
        return f"{value:.{digits}f}" if digits is not None else str(value)

    gates = "\n".join(f"| {name} | {gate['status']} | {gate['criterion']} |" for name, gate in document["gates"].items())
    blockers = "\n".join(f"- {item}" for item in document["blockers"]) or "- None"
    risks = "\n".join(f"- {item}" for item in document["risks"]) or "- None"
    adapter, integrated, placement, routing, budget = (document[key] for key in ("adapter_mapping", "integrated_mapping", "placement", "global_routing", "logic_die_budget"))
    report = f"""# Hardware-cost Physical Feasibility Gate

Overall status: **{document['status']}**  
RTL freeze allowed: **{str(document['rtl_freeze_allowed']).lower()}**  
Production signoff: **{document['production_signoff']}**

| Gate | Status | Criterion |
|---|---|---|
{gates}

## Quantitative evidence

| Metric | Adapter | Integrated PCU + adapter |
|---|---:|---:|
| Mapped cells | {adapter['mapped_cells']} | {integrated['mapped_cells']} |
| Mapped area (um^2) | {adapter['mapped_area_um2']} | {integrated['mapped_area_um2']} |
| Sequential area (um^2) | {adapter['sequential_area_um2']} | {integrated['sequential_area_um2']} |
| Critical path (ns) | {adapter['critical_path_ns']} | {show(integrated['critical_path_ns'])} |
| Captured STA period (ns) | {adapter['clock_period_ns']} | {show(integrated['clock_period_ns'])} |
| Captured STA worst slack (ns) | {adapter['worst_slack_ns']} | {show(integrated['worst_slack_ns'])} |
| Project reference period (ns) | {adapter['reference_clock_period_ns']} | {integrated['reference_clock_period_ns']} |
| Meets project reference | {adapter['reference_timing_target_met']} | {show(integrated['reference_timing_target_met'])} |
| Unconstrained paths | {adapter['unconstrained_path_count']} | {show(integrated['unconstrained_path_count'])} |

- Legal placement: {placement['completed']}; final violations: {placement['final_violations']}; core area: {placement['core_area_um2']} um^2; utilization: {placement['utilization_pct']}%.
- Global routing revision: {routing['route_revision']}; completed measurement: {routing['completed']}; clean exit: {routing['execution_clean']}; OpenROAD exit code: {show(routing['openroad_exit_code'])}; signal layers: {show(routing['signal_layers'])}; iterations: {show(routing['congestion_iterations'])}.
- Global routing overflow: {routing['overflow_count']}; max layer usage: {show(routing['max_layer_usage_pct'])}%; routed nets: {show(routing['routed_nets'])}; maximum observed fanout: {routing['max_observed_fanout']}.
- CUGR congestion remaining: {show(routing['congestion_remaining'])}; detailed violations captured: {show(routing['congestion_violation_count'])}; maximum local overuse: {show(routing['max_local_overuse'])}.
- Prior-route comparison: {routing['prior_route_comparison']}.
- Captured congestion hotspot categories: {routing['congestion_hotspots']['category_block_counts']}; top bank source mentions: {routing['congestion_hotspots']['top_bank_source_mentions']}; top 500 um tiles: {routing['congestion_hotspots']['top_500um_tiles']}.
- Logic-die proxy budget: {show(budget['assumed_usable_area_um2'])} um^2; mapped utilization: {show(budget['mapped_utilization_pct'], 3)}%; placed-footprint utilization: {show(budget['placed_footprint_utilization_pct'], 3)}%.
- Buffer implementation: {document['buffer_implementation']['logical_bits']} logical bits lowered to {document['buffer_implementation']['mapped_register_count']} standard-cell registers; storage-cell-only area {show(document['buffer_implementation']['mapped_area_um2'], 3)} um^2 ({show(document['buffer_implementation']['share_of_adapter_area_pct'], 3)}% of adapter mapped area).
- Coarse fanout/wire repair: {show(document['fanout']['repair_inserted_buffers'])} inserted buffers across {show(document['fanout']['repair_repaired_nets'])} nets; area increase {show(document['fanout']['repair_area_increase_pct'])}%; remaining slew/fanout/capacitance violations {show(document['fanout']['remaining_slew_violations'])}/{show(document['fanout']['remaining_fanout_violations'])}/{show(document['fanout']['remaining_capacitance_violations'])}.
- Generic connectivity baseline: {document['wide_interface']['generic_wire_bits']:,} wire bits. This is a structural pressure indicator, not a direct congestion measurement.

## Freeze blockers

{blockers}

## Non-gating risks

{risks}

## Claim boundary

{document['claim_boundary']}
"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(report, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", default=str(DEFAULT_EVIDENCE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--report", default=str(DEFAULT_REPORT))
    args = parser.parse_args()
    document = collect(args.evidence_dir)
    output, report = Path(args.output), Path(args.report)
    output = output if output.is_absolute() else ROOT / output
    report = report if report.is_absolute() else ROOT / report
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, indent=2), encoding="utf-8")
    write_report(document, report)
    print(f"PHYSICAL_FEASIBILITY {document['status']} freeze={document['rtl_freeze_allowed']} output={output}")
    # FAIL is a valid measured gate outcome, not a collection/contract error.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
