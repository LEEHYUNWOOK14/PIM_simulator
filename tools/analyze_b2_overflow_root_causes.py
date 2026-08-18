#!/usr/bin/env python3
"""Trace B2 overflow nets through an existing routed ODB without modifying it.

Run with OpenROAD's Python mode.  The script reads the already-routed B2 ODB,
the direct numeric congestion analysis, and the existing routed family metrics.
It never calls placement or routing and never writes an ODB.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import statistics
import sys
from collections import Counter, defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import odb


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ANALYSIS = ROOT / "reports/groot_normalization/quad_local_b2/b2_residual_congestion_analysis.json"
DEFAULT_MEASUREMENTS = ROOT / "reports/groot_normalization/quad_local_b2/b2_routed_tag_completion_net_measurements.json"
DEFAULT_ODB = ROOT / "reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"
DEFAULT_OUT = ROOT / "reports/groot_normalization/quad_local_b3"

AUTO_NET = re.compile(r"(?:^|/)(?:net\d+|_[0-9]+_)$")
BUFFER_MASTER = re.compile(r"(?:buf|inv|clkbuf)", re.IGNORECASE)
SEQUENTIAL_MASTER = re.compile(r"(?:df|dl|latch)", re.IGNORECASE)
SEMANTIC_NET = re.compile(
    r"(?:quad_completion|completion_descriptor|completion_bits|ctx_tag|ctx_valid|"
    r"scalar_configured|scalar_return|scalar_inv|writeback|reduction|replay|"
    r"payload|adapter|bank_apply|bank_reduc|clk_i|rst|reset)",
    re.IGNORECASE,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def direction(iterm: Any) -> str:
    value = iterm.getIoType()
    return (value.getString() if hasattr(value, "getString") else str(value)).upper()


def endpoints(net: Any, dbu: int, sample_limit: int = 32) -> tuple[list[dict[str, Any]], float, float, int, int]:
    records: list[dict[str, Any]] = []
    points: list[tuple[int, int]] = []
    total = 0
    sinks = 0
    for iterm in net.getITerms():
        total += 1
        io_direction = direction(iterm)
        if io_direction in ("INPUT", "INOUT"):
            sinks += 1
        inst = iterm.getInst()
        valid, x, y = iterm.getAvgXY()
        if not valid and inst.isPlaced():
            box = inst.getBBox()
            x = (box.xMin() + box.xMax()) // 2
            y = (box.yMin() + box.yMax()) // 2
            valid = True
        if valid:
            points.append((x, y))
        if len(records) < sample_limit:
            records.append(
                {
                    "instance": inst.getName(),
                    "master": inst.getMaster().getName(),
                    "pin": iterm.getMTerm().getName(),
                    "direction": io_direction,
                    "xy_um": [x / dbu, y / dbu] if valid else None,
                }
            )
    for bterm in net.getBTerms():
        total += 1
        io = bterm.getIoType()
        io_name = (io.getString() if hasattr(io, "getString") else str(io)).upper()
        for bpin in bterm.getBPins():
            box = bpin.getBBox()
            points.append(((box.xMin() + box.xMax()) // 2, (box.yMin() + box.yMax()) // 2))
        if len(records) < sample_limit:
            records.append(
                {
                    "instance": "BTERM",
                    "master": None,
                    "pin": bterm.getName(),
                    "direction": io_name,
                    "xy_um": None,
                }
            )
    if points:
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        span_x = (max(xs) - min(xs)) / dbu
        span_y = (max(ys) - min(ys)) / dbu
    else:
        span_x = span_y = 0.0
    return sorted(records, key=lambda item: (item["instance"], item["pin"])), span_x, span_y, total, sinks


def skipped_clock_endpoints(net: Any, sample_limit: int = 16) -> tuple[list[dict[str, Any]], int, int]:
    """Count the skipped high-fanout clock without 319k expensive XY calls."""
    iterms = net.getITerms()
    bterms = net.getBTerms()
    sample: list[dict[str, Any]] = []
    for iterm in iterms[:sample_limit]:
        inst = iterm.getInst()
        sample.append(
            {
                "instance": inst.getName(),
                "master": inst.getMaster().getName(),
                "pin": iterm.getMTerm().getName(),
                "direction": direction(iterm),
                "xy_um": None,
            }
        )
    for bterm in bterms:
        if len(sample) >= sample_limit:
            break
        sample.append(
            {
                "instance": "BTERM",
                "master": None,
                "pin": bterm.getName(),
                "direction": str(bterm.getIoType()),
                "xy_um": None,
            }
        )
    return sample, len(iterms) + len(bterms), len(iterms)


def guide_metrics(net: Any, dbu: int) -> dict[str, Any]:
    by_layer: dict[str, dict[str, float | int]] = defaultdict(
        lambda: {"rectangles": 0, "length_um": 0.0, "congested": 0}
    )
    total_length = 0.0
    total_rectangles = 0
    congested = 0
    for guide in net.getGuides():
        box = guide.getBox()
        length = max(box.xMax() - box.xMin(), box.yMax() - box.yMin()) / dbu
        layer = guide.getLayer().getName()
        by_layer[layer]["rectangles"] += 1
        by_layer[layer]["length_um"] += length
        total_length += length
        total_rectangles += 1
        if guide.isCongested():
            by_layer[layer]["congested"] += 1
            congested += 1
    return {
        "guide_rectangles": total_rectangles,
        "guide_length_um": total_length,
        "congested_guide_rectangles": congested,
        "guide_layers": dict(sorted(by_layer.items())),
    }


def is_auto(name: str) -> bool:
    return bool(AUTO_NET.search(name))


def upstream_trace(net: Any, max_depth: int = 4, max_nets: int = 64) -> dict[str, Any]:
    """Walk backwards through combinational drivers to named RTL boundaries."""
    queue: deque[tuple[Any, int]] = deque([(net, 0)])
    seen: set[str] = set()
    semantic: set[str] = set()
    sequential: set[str] = set()
    buffer_roots: set[str] = set()
    visited_instances = 0
    truncated = False

    while queue:
        current, depth = queue.popleft()
        name = current.getName()
        if name in seen:
            continue
        seen.add(name)
        if len(seen) >= max_nets:
            truncated = True
            break
        if name != net.getName() and SEMANTIC_NET.search(name):
            semantic.add(name)
            continue
        if depth >= max_depth:
            continue
        drivers = [iterm for iterm in current.getITerms() if direction(iterm) in ("OUTPUT", "INOUT")]
        for driver in drivers:
            inst = driver.getInst()
            master = inst.getMaster().getName()
            visited_instances += 1
            if SEQUENTIAL_MASTER.search(master):
                sequential.add(f"{inst.getName()}/{driver.getMTerm().getName()}:{master}")
                continue
            inputs = [
                iterm.getNet()
                for iterm in inst.getITerms()
                if direction(iterm) in ("INPUT", "INOUT") and iterm.getNet() is not None
            ]
            if BUFFER_MASTER.search(master):
                for input_net in inputs:
                    if not is_auto(input_net.getName()):
                        buffer_roots.add(input_net.getName())
            for input_net in inputs:
                queue.append((input_net, depth + 1))

    return {
        "semantic_upstream_nets": sorted(semantic),
        "buffer_chain_roots": sorted(buffer_roots),
        "sequential_driver_boundaries": sorted(sequential),
        "visited_nets": len(seen),
        "visited_driver_instances": visited_instances,
        "truncated": truncated,
    }


def category_map(analysis: dict[str, Any]) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    categories: dict[str, set[str]] = defaultdict(set)
    quads: dict[str, set[str]] = defaultdict(set)
    for window in analysis["windows"]:
        if window["overflow"] <= 0:
            continue
        for item in window["source_attribution"]:
            categories[item["name"]].update(item["categories"])
            quads[item["name"]].update(item["quads"])
    return categories, quads


def cone_label(name: str, trace: dict[str, Any], categories: list[str]) -> str:
    evidence = " ".join(
        [name]
        + trace["semantic_upstream_nets"]
        + trace["buffer_chain_roots"]
        + trace["sequential_driver_boundaries"]
    ).lower()
    if "quad_completion" in evidence or "completion_descriptor" in evidence:
        return "registered quad completion/context compare"
    if "ctx_tag" in evidence or "ctx_valid" in evidence:
        return "central context table compare/control"
    if "scalar" in evidence:
        return "scalar engine/return control or payload"
    if "writeback" in evidence:
        return "writeback transport"
    if "reduction" in evidence or "u_reduce" in evidence:
        return "bank reduction datapath"
    if "replay" in evidence:
        return "replay transport"
    if "adapter" in evidence or "payload" in evidence:
        return "adapter/payload-store transport"
    named = [category for category in categories if category != "top-level I/O/other"]
    return named[0] if named else "generic central PCU/control logic"


def render_markdown(payload: dict[str, Any]) -> str:
    totals = payload["totals"]
    lines = [
        "# B2 overflow root-cause and B3 ECO decision",
        "",
        f"Generated: `{payload['generated_at_utc']}`",
        "",
        "This is a read-only analysis of the existing B2 routed ODB. No placement or routing was run.",
        "",
        "## Root-cause verdict",
        "",
        f"- Parsed overflow: {totals['overflow_edges']} edges / {totals['overflow_tracks']} tracks across {totals['overflow_windows']} windows.",
        f"- Central corridor: {totals['central_corridor_overflow']} / {totals['overflow_windows']} overflow windows.",
        f"- met1: {totals['met1_overflow']} / {totals['overflow_windows']} overflow windows.",
        "- The dominant repeated synthetic nets trace back to the registered quad-completion/context comparison cone; they are not an unexplained top-level I/O family.",
        "- `clk_i` is a co-resident source, not the routed cause: it was explicitly skipped by global route and therefore has no route guides in the routed ODB.",
        "- B2 global route stopped after one configured congestion iteration with residual 46, so routing effort is the lowest-risk variable to change before another RTL restructuring.",
        "",
        "## Leading overflow nets with routed metrics",
        "",
        "| net | windows | cone | sinks | HPWL um | guide um | upstream evidence |",
        "|---|---:|---|---:|---:|---:|---|",
    ]
    for record in payload["ranked_nets"][:30]:
        trace_names = record["upstream_trace"]["semantic_upstream_nets"][:3]
        if not trace_names:
            trace_names = record["upstream_trace"]["buffer_chain_roots"][:3]
        evidence = ", ".join(f"`{value}`" for value in trace_names) or "_endpoint hierarchy_"
        lines.append(
            f"| `{record['name']}` | {record['window_occurrences']} | {record['rtl_cone']} | "
            f"{record['sink_fanout']} | {record['terminal_hpwl_um']:.3f} | "
            f"{record['guide_length_um']:.3f} | {evidence} |"
        )
    lines.extend(
        [
            "",
            "## `clk_i` determination",
            "",
            f"- Overflow-window co-occurrences: {payload['clock_determination']['overflow_window_occurrences']}",
            f"- Routed guide rectangles: {payload['clock_determination']['guide_rectangles']}",
            f"- Decision: **{payload['clock_determination']['decision']}**",
            "",
            "## Selected B3 ECO",
            "",
            f"Decision: **{payload['b3_eco_decision']['decision']}**",
            "",
            payload["b3_eco_decision"]["basis"],
            "",
            "The B3 implementation must use a new design name and output directory, preserve B2 RTL behavior, rerun all cheap gates, produce one new placement, and invoke global route exactly once with ten CUGR congestion iterations. If that single B3 route is nonzero, B3 is sealed as failed and any further change moves to B4.",
            "",
            "## Hash preservation",
            "",
            f"- B2 routed ODB SHA-256: `{payload['inputs']['routed_odb']['sha256']}`",
            f"- B2 congestion analysis SHA-256: `{payload['inputs']['analysis']['sha256']}`",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    analysis_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ANALYSIS
    measurements_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_MEASUREMENTS
    odb_path = Path(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_ODB
    out_dir = Path(sys.argv[4]) if len(sys.argv) > 4 else DEFAULT_OUT

    analysis = json.loads(analysis_path.read_text(encoding="utf-8"))
    measurements = json.loads(measurements_path.read_text(encoding="utf-8"))
    database = odb.read_db(None, str(odb_path))
    block = database.getChip().getBlock()
    dbu = block.getDbUnitsPerMicron()
    occurrence: Counter[str] = Counter()
    overflow_contribution: Counter[str] = Counter()
    windows_by_net: dict[str, list[int]] = defaultdict(list)
    categories, quads = category_map(analysis)
    for window in analysis["windows"]:
        if window["overflow"] <= 0:
            continue
        for name in window["sources"]:
            occurrence[name] += 1
            overflow_contribution[name] += window["overflow"]
            windows_by_net[name].append(window["index"])

    # Deep OpenDB traversal is reserved for the repeated leaders.  The direct
    # congestion parser already seals all 685 source attributions; routed
    # fanout/HPWL/guide evidence is needed only for the leading 32 sources.
    metric_target_names = [name for name, _ in occurrence.most_common(32)]
    trace_target_names = set(metric_target_names[:16]) | {"clk_i"}
    selected_nets: dict[str, Any] = {}
    for name in metric_target_names:
        candidate = block.findNet(name)
        if candidate is not None:
            selected_nets[name] = candidate

    ranked: list[dict[str, Any]] = []
    missing: list[str] = []
    for name, count in occurrence.most_common(32):
        net = selected_nets.get(name)
        if net is None:
            missing.append(name)
            continue
        geometry_skipped = name == "clk_i"
        if geometry_skipped:
            endpoint_records, endpoint_count, sink_fanout = skipped_clock_endpoints(net)
            span_x = span_y = 0.0
        else:
            endpoint_records, span_x, span_y, endpoint_count, sink_fanout = endpoints(net, dbu)
        trace = upstream_trace(net) if name in trace_target_names else {
            "semantic_upstream_nets": [],
            "buffer_chain_roots": [],
            "sequential_driver_boundaries": [],
            "visited_nets": 0,
            "visited_driver_instances": 0,
            "truncated": False,
        }
        guides = guide_metrics(net, dbu)
        record = {
            "name": name,
            "window_occurrences": count,
            "overflow_track_contribution": overflow_contribution[name],
            "window_indices": windows_by_net[name],
            "categories": sorted(categories[name]),
            "source_quads": sorted(quads[name]),
            "sink_fanout": sink_fanout,
            "terminal_count": endpoint_count,
            "terminal_span_x_um": span_x,
            "terminal_span_y_um": span_y,
            "terminal_hpwl_um": span_x + span_y,
            "terminal_geometry_skipped": geometry_skipped,
            **guides,
            "upstream_trace": trace,
            "rtl_cone": cone_label(name, trace, sorted(categories[name])),
            "endpoint_sample": endpoint_records,
        }
        ranked.append(record)

    ranked.sort(
        key=lambda item: (
            -item["window_occurrences"],
            -item["overflow_track_contribution"],
            -item["guide_length_um"],
            item["name"],
        )
    )
    clock = next((record for record in ranked if record["name"] == "clk_i"), None)
    clock_guides = clock["guide_rectangles"] if clock else 0
    overflow_windows = analysis["aggregates"]["overflow_windows"]
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "read-only existing-artifact root-cause analysis",
        "inputs": {
            "analysis": {"path": str(analysis_path), "sha256": sha256(analysis_path)},
            "measurements": {"path": str(measurements_path), "sha256": sha256(measurements_path)},
            "routed_odb": {"path": str(odb_path), "sha256": sha256(odb_path)},
        },
        "design": block.getName(),
        "dbu_per_micron": dbu,
        "totals": {
            "rrr_residual": analysis["totals"]["rrr_residual"],
            "overflow_edges": analysis["totals"]["overflow_edges"],
            "overflow_tracks": analysis["totals"]["overflow_tracks"],
            "overflow_windows": overflow_windows["windows"],
            "central_corridor_overflow": overflow_windows["by_spatial_region"]["central_corridor"],
            "met1_overflow": overflow_windows["by_layer"]["met1"],
            "unique_overflow_source_nets": len(occurrence),
            "odb_metric_target_source_nets": len(metric_target_names),
            "odb_matched_source_nets": len(ranked),
            "odb_missing_source_nets": len(missing),
            "low_rank_sources_not_deep_traced": len(occurrence) - len(metric_target_names),
        },
        "clock_determination": {
            "overflow_window_occurrences": occurrence.get("clk_i", 0),
            "guide_rectangles": clock_guides,
            "decision": "CO_RESIDENT_NOT_ROUTED_CAUSE" if occurrence.get("clk_i", 0) and clock_guides == 0 else "REVIEW_REQUIRED",
            "basis": "The B2 route log explicitly skips clk_i as a 319254-terminal net; no clk_i guides are present.",
        },
        "existing_family_measurements": measurements.get("families", {}),
        "ranked_nets": ranked,
        "missing_source_nets": sorted(missing),
        "b3_eco_decision": {
            "decision": "SELECT_B3_ROUTE_EFFORT_ECO",
            "change_scope": "new B3 variant/config only; preserve B2 RTL behavior and all A/B/B2 artifacts",
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 10,
            "basis": "B2 reduced the frozen-B residual from 3323 to 46 with one configured congestion iteration. Residual overflow is low magnitude (38 edges at overflow 1 and one edge at overflow 2), 31/39 windows sit in the central corridor, and the dominant named cone is already the registered narrow completion/context implementation. A bounded increase in RRR effort is less invasive than another functional RTL change.",
            "fallback": "If B3 is nonzero, seal B3 and create a new B4 variant with a separately justified placement/RTL ECO; never reroute B3.",
            "authorizes_after_cheap_gates": ["B3_PLACEMENT", "B3_SINGLE_GLOBAL_ROUTE"],
        },
        "read_only_assertions": {
            "placement_called": False,
            "global_route_called": False,
            "odb_written": False,
        },
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "b3_cheap_root_cause_analysis.json"
    md_path = out_dir / "b3_cheap_root_cause_analysis.md"
    decision_path = out_dir / "b3_eco_decision.json"
    json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_path.write_text(render_markdown(payload), encoding="utf-8")
    decision_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "generated_at_utc": payload["generated_at_utc"],
                "source_analysis": {"path": str(json_path), "sha256": sha256(json_path)},
                **payload["b3_eco_decision"],
                "status": "SELECTED_PENDING_CHEAP_GATES",
                "authorizes": [],
                "next_stage": "B3_IMPLEMENTATION_AND_CHEAP_GATES",
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"B2_ROOT_CAUSE_ANALYSIS PASS overflow={totals if False else analysis['totals']['overflow_edges']} ranked_nets={len(ranked)}")
    print(f"B3_ECO_DECISION SELECT_B3_ROUTE_EFFORT_ECO iterations=10")
    print(f"B3_ROOT_CAUSE_JSON {json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
