#!/usr/bin/env python3
"""Analyze the existing B2 congestion report without launching physical tools."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


CATEGORY_ORDER = [
    "adapter/payload-store",
    "scalar engine/scalar return",
    "bank apply",
    "bank reduction",
    "replay",
    "writeback",
    "quad completion/context tag",
    "clock/reset",
    "top-level I/O/other",
]

CORE_BBOX_UM = [10.120, 10.880, 9027.500, 9027.680]
FENCE_BBOXES_UM = {
    "Q0_fence": [20.120, 20.880, 4265.444, 4266.204],
    "Q1_fence": [4772.176, 20.880, 9017.500, 4266.204],
    "Q2_fence": [20.120, 4772.356, 4265.444, 9017.680],
    "Q3_fence": [4772.176, 4772.356, 9017.500, 9017.680],
}
CORRIDOR_STRIPS_UM = {
    "vertical": [4265.444, CORE_BBOX_UM[1], 4772.176, CORE_BBOX_UM[3]],
    "horizontal": [CORE_BBOX_UM[0], 4266.204, CORE_BBOX_UM[2], 4772.356],
}

BASELINE_METRICS = {
    "frozen_A": {
        "rrr_residual": 1768,
        "congestion_windows": 4463,
        "overflow_edges": 1293,
        "overflow_tracks": 1395,
        "maximum_congestion": 4,
    },
    "quad_local_B": {
        "rrr_residual": 3323,
        "congestion_windows": 4357,
        "overflow_edges": 2413,
        "overflow_tracks": 3146,
        "maximum_congestion": 5,
    },
}

PRESERVED_ODB = {
    "frozen_A_routed_odb": {
        "path": "reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb",
        "expected_sha256": "964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad",
    },
    "quad_local_B_routed_odb": {
        "path": "reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb",
        "expected_sha256": "ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235",
    },
    "quad_local_B2_routed_odb": {
        "path": "reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb",
        "expected_sha256": "2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d",
    },
}

INPUT_PATHS = {
    "congestion_report": "reports/groot_normalization/quad_local_b2/b2_quad_local.congestion.rpt",
    "global_route_log": "reports/groot_normalization/quad_local_b2/b2_global_route.log",
    "routed_measurements": "reports/groot_normalization/quad_local_b2/b2_routed_tag_completion_net_measurements.json",
    "mapped_locality_audit": "reports/groot_normalization/quad_local_b2/b2_mapped_locality_audit.json",
    "phase5_execution_report": "reports/groot_normalization/quad_local_b2/phase5_b2_execution_report.json",
    "prior_phase6_gate": "reports/groot_normalization/quad_local_b2/phase6_decision_gate.json",
    "phase5_contract": "reports/final_integrated_gds_execution/05_wbq_phase5_quad_local_ab_contract.md",
}

OUTPUT_PATHS = {
    "analysis_json": "reports/groot_normalization/quad_local_b2/b2_residual_congestion_analysis.json",
    "analysis_md": "reports/groot_normalization/quad_local_b2/b2_residual_congestion_analysis.md",
    "phase5_decision": "reports/groot_normalization/quad_local_b2/phase5_b2_residual_decision.json",
    "phase6_gate": "reports/groot_normalization/quad_local_b2/phase6_decision_gate.json",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_evidence(path: Path, *, compute_hash: bool = True) -> dict[str, Any]:
    stat = path.stat()
    result: dict[str, Any] = {
        "path": str(path),
        "bytes": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }
    if compute_hash:
        result["sha256"] = sha256_file(path)
    return result


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def normalize_net_name(name: str) -> str:
    return name.replace(r"\[", "[").replace(r"\]", "]")


def source_categories(name: str) -> list[str]:
    low = name.lower()
    categories: set[str] = set()

    if (
        "u_quad_local_adapter" in low
        or "u_payload_store" in low
        or re.search(r"/(reduction_data|replay_(x|gamma|beta|tag)|writeback_(tag|data))\[", low)
    ):
        categories.add("adapter/payload-store")
    if any(
        token in low
        for token in (
            "scalar",
            "u_engine",
            "g_engine",
            "partial_stat",
            "u_packet_reducer",
        )
    ):
        categories.add("scalar engine/scalar return")
    if any(
        token in low
        for token in (
            "u_apply",
            "apply_",
            "/centered",
            "/normalized",
            "meta_gamma",
            "meta_inv",
        )
    ):
        categories.add("bank apply")
    if any(
        token in low
        for token in (
            "u_reduce",
            "reduction_",
            "reduce_",
            "partial_sum",
            "partial_sumsq",
            "u_packet_reducer",
        )
    ):
        categories.add("bank reduction")
    if "replay" in low:
        categories.add("replay")
    if "writeback" in low or re.search(r"/(core_)?result_(tag|data|valid|ready|last)", low):
        categories.add("writeback")
    if any(
        token in low
        for token in (
            "quad_completion",
            "completion_descriptor",
            "ctx_tag",
            "ctx_done",
            "completion_bits",
            "context_tag",
            "u_context",
        )
    ):
        categories.add("quad completion/context tag")
    if (
        low == "clk_i"
        or low == "rst_ni"
        or "quad_rst_n" in low
        or "reset" in low
        or re.search(r"(^|/)rst_n?i?(\[|$)", low)
    ):
        categories.add("clock/reset")

    if not categories:
        categories.add("top-level I/O/other")
    return [category for category in CATEGORY_ORDER if category in categories]


def source_quads(name: str) -> list[str]:
    quads = {f"Q{match}" for match in re.findall(r"g_quad\[(\d+)\]", name)}
    if quads:
        return sorted(quads)

    signal_match = re.search(r"/([A-Za-z0-9_]+)\[(\d+)\]$", name)
    if not signal_match:
        return []
    signal, bit_text = signal_match.groups()
    bit = int(bit_text)

    bits_per_quad = {
        "reduction_data": 512,
        "replay_x": 512,
        "replay_gamma": 512,
        "replay_beta": 512,
        "writeback_data": 512,
        "pcu_writeback_data": 512,
        "replay_tag": 64,
        "writeback_tag": 64,
        "pcu_writeback_tag": 64,
        "quad_completion_tag": 16,
        "quad_scalar_tag": 16,
        "quad_partial_tag": 16,
        "quad_scalar_mean": 32,
        "quad_scalar_inv": 32,
        "quad_partial_sum": 32,
        "quad_partial_sumsq": 32,
        "quad_completion_valid": 1,
        "quad_scalar_valid": 1,
        "quad_scalar_ready": 1,
        "quad_scalar_mode": 1,
        "quad_partial_valid": 1,
        "quad_partial_ready": 1,
        "quad_rst_n": 1,
        "reduction_valid": 4,
        "reduction_ready": 4,
        "replay_valid": 4,
        "replay_ready": 4,
        "replay_last": 4,
        "writeback_valid": 4,
        "writeback_ready": 4,
        "writeback_last": 4,
    }.get(signal)
    if bits_per_quad is None:
        return []
    quad = bit // bits_per_quad
    return [f"Q{quad}"] if 0 <= quad < 4 else []


def bbox_contains(container: Iterable[float], candidate: Iterable[float], eps: float = 1e-6) -> bool:
    cx1, cy1, cx2, cy2 = container
    x1, y1, x2, y2 = candidate
    return (
        x1 >= cx1 - eps
        and y1 >= cy1 - eps
        and x2 <= cx2 + eps
        and y2 <= cy2 + eps
    )


def bbox_intersects(a: Iterable[float], b: Iterable[float], eps: float = 1e-6) -> bool:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    return not (
        ax2 < bx1 - eps
        or bx2 < ax1 - eps
        or ay2 < by1 - eps
        or by2 < ay1 - eps
    )


def spatial_region(bbox: list[float]) -> str:
    for name, fence in FENCE_BBOXES_UM.items():
        if bbox_contains(fence, bbox):
            return name
    for strip in CORRIDOR_STRIPS_UM.values():
        if bbox_contains(strip, bbox):
            return "central_corridor"
    if any(bbox_intersects(fence, bbox) for fence in FENCE_BBOXES_UM.values()):
        return "fence_boundary_overlap"
    if bbox_contains(CORE_BBOX_UM, bbox):
        return "edge_guardband"
    return "outside_core"


def parse_congestion_report(path: Path) -> list[dict[str, Any]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) % 4:
        raise ValueError(f"expected four lines per record, got {len(lines)} lines")
    records: list[dict[str, Any]] = []
    type_re = re.compile(r"^violation type: (.+)$")
    comment_re = re.compile(
        r"^\s*comment: capacity:(\d+) usage:(\d+) congestion:([0-9.]+) \([^)]*\)$"
    )
    bbox_re = re.compile(
        r"^\s*bbox = \(([-0-9.]+), ([-0-9.]+)\) - "
        r"\(([-0-9.]+), ([-0-9.]+)\) on Layer (\S+)$"
    )

    for offset in range(0, len(lines), 4):
        type_match = type_re.match(lines[offset])
        comment_match = comment_re.match(lines[offset + 2])
        bbox_match = bbox_re.match(lines[offset + 3])
        if not type_match or not lines[offset + 1].lstrip().startswith("srcs:"):
            raise ValueError(f"malformed congestion record at line {offset + 1}")
        if not comment_match or not bbox_match:
            raise ValueError(f"malformed congestion metrics at line {offset + 1}")

        source_text = lines[offset + 1].split("srcs:", 1)[1].strip()
        sources = [normalize_net_name(token[4:]) for token in source_text.split() if token.startswith("net:")]
        capacity = int(comment_match.group(1))
        usage = int(comment_match.group(2))
        congestion_number = float(comment_match.group(3))
        congestion: int | float = (
            int(congestion_number) if congestion_number.is_integer() else congestion_number
        )
        bbox = [float(value) for value in bbox_match.groups()[:4]]
        source_attribution = [
            {
                "name": source,
                "categories": source_categories(source),
                "quads": source_quads(source),
            }
            for source in sources
        ]
        categories = {
            category
            for attribution in source_attribution
            for category in attribution["categories"]
        }
        quads = {
            quad
            for attribution in source_attribution
            for quad in attribution["quads"]
        }
        records.append(
            {
                "index": len(records),
                "type": type_match.group(1),
                "layer": bbox_match.group(5),
                "bbox_um": bbox,
                "center_um": [round((bbox[0] + bbox[2]) / 2.0, 4), round((bbox[1] + bbox[3]) / 2.0, 4)],
                "capacity": capacity,
                "usage": usage,
                "overflow": max(usage - capacity, 0),
                "at_capacity": usage == capacity,
                "congestion": congestion,
                "spatial_region": spatial_region(bbox),
                "categories": [category for category in CATEGORY_ORDER if category in categories],
                "source_quads": sorted(quads),
                "sources": sources,
                "source_attribution": source_attribution,
            }
        )
    return records


def summarize_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_type: Counter[str] = Counter()
    by_layer: Counter[str] = Counter()
    by_region: Counter[str] = Counter()
    by_source_quad: Counter[str] = Counter()
    by_category_windows: Counter[str] = Counter()
    by_category_sources: Counter[str] = Counter()
    category_unique_sources: dict[str, set[str]] = defaultdict(set)
    category_layers: dict[str, Counter[str]] = defaultdict(Counter)
    source_occurrences: Counter[str] = Counter()
    overflow_tracks = 0

    for record in records:
        by_type[record["type"]] += 1
        by_layer[record["layer"]] += 1
        by_region[record["spatial_region"]] += 1
        for quad in record["source_quads"] or ["unassigned"]:
            by_source_quad[quad] += 1
        overflow_tracks += record["overflow"]
        for category in record["categories"]:
            by_category_windows[category] += 1
            category_layers[category][record["layer"]] += 1
        for attribution in record["source_attribution"]:
            source_occurrences[attribution["name"]] += 1
            for category in attribution["categories"]:
                by_category_sources[category] += 1
                category_unique_sources[category].add(attribution["name"])

    by_category = {
        category: {
            "windows": by_category_windows[category],
            "source_net_occurrences": by_category_sources[category],
            "unique_source_nets": len(category_unique_sources[category]),
            "by_layer": dict(sorted(category_layers[category].items())),
        }
        for category in CATEGORY_ORDER
    }
    return {
        "windows": len(records),
        "overflow_tracks": overflow_tracks,
        "by_type": dict(sorted(by_type.items())),
        "by_layer": dict(sorted(by_layer.items())),
        "by_spatial_region": dict(sorted(by_region.items())),
        "by_source_quad_nonexclusive": dict(sorted(by_source_quad.items())),
        "by_category_nonexclusive": by_category,
        "top_source_nets": [
            {"name": name, "window_occurrences": count}
            for name, count in source_occurrences.most_common(25)
        ],
    }


def percent_reduction(before: int, after: int) -> float:
    return round((before - after) * 100.0 / before, 2)


def compact_record(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "index": record["index"],
        "type": record["type"],
        "layer": record["layer"],
        "bbox_um": record["bbox_um"],
        "capacity": record["capacity"],
        "usage": record["usage"],
        "overflow": record["overflow"],
        "congestion": record["congestion"],
        "spatial_region": record["spatial_region"],
        "categories": record["categories"],
        "source_quads": record["source_quads"],
        "sources": record["sources"],
    }


def find_check(audit: dict[str, Any], check_id: str) -> dict[str, Any]:
    for check in audit.get("checks", []):
        if check.get("id") == check_id:
            return check
    raise ValueError(f"mapped audit is missing check {check_id}")


def artifact_hash_checks(root: Path, phase5_report: dict[str, Any]) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    artifacts = phase5_report["global_route"]["artifacts"]
    for name, artifact in artifacts.items():
        path = root / artifact["path"]
        actual = sha256_file(path)
        checks.append(
            {
                "name": name,
                "path": artifact["path"],
                "expected_sha256": artifact["sha256"],
                "actual_sha256": actual,
                "match": actual == artifact["sha256"],
                "bytes": path.stat().st_size,
            }
        )
    return checks


def preserved_odb_checks(root: Path) -> dict[str, dict[str, Any]]:
    checks: dict[str, dict[str, Any]] = {}
    for name, artifact in PRESERVED_ODB.items():
        path = root / artifact["path"]
        actual = sha256_file(path)
        checks[name] = {
            "path": artifact["path"],
            "expected_sha256": artifact["expected_sha256"],
            "actual_sha256": actual,
            "match": actual == artifact["expected_sha256"],
            "bytes": path.stat().st_size,
            "mtime_ns": path.stat().st_mtime_ns,
        }
    return checks


def markdown_table(headers: list[str], rows: list[list[Any]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |"]
    lines.append("| " + " | ".join("---" for _ in headers) + " |")
    lines.extend("| " + " | ".join(str(cell) for cell in row) + " |" for row in rows)
    return lines


def render_markdown(analysis: dict[str, Any]) -> str:
    totals = analysis["totals"]
    all_summary = analysis["aggregates"]["all_windows"]
    overflow_summary = analysis["aggregates"]["overflow_windows"]
    comparison = analysis["comparison"]
    comparator = analysis["pcu_writeback_tag_comparator_cone"]
    phase5 = analysis["phase5_contract_evaluation"]
    phase6 = analysis["phase6_strict_evaluation"]

    lines = [
        "# B2 residual congestion analysis",
        "",
        f"Generated: `{analysis['generated_at']}`",
        "",
        "This is a read-only analysis of the existing B2 route artifacts. No placement, global route, detailed route, CTS, or Phase 6 execution was started.",
        "",
        "## Decision",
        "",
        f"- Phase 5: **{phase5['decision']}**",
        f"- Phase 6: **{phase6['decision']}**",
        "- Phase 6 `authorizes=[]`; `next_stage=null`.",
        "",
        "B2 satisfies the Phase 5 contract because both residual congestion and overflow edges improve against frozen A. The strict Phase 6 zero-residual and zero-overflow requirements fail.",
        "",
        "## Direct parser checks",
        "",
        f"- Parsed records: {totals['windows']} (horizontal {totals['by_type'].get('Horizontal congestion', 0)}, vertical {totals['by_type'].get('Vertical congestion', 0)})",
        f"- Layers: met1 {totals['by_layer'].get('met1', 0)}, met2 {totals['by_layer'].get('met2', 0)}, met3 {totals['by_layer'].get('met3', 0)}",
        f"- Recomputed overflow edges/tracks: {totals['overflow_edges']}/{totals['overflow_tracks']}",
        f"- Prior summary said {analysis['reported_vs_recomputed']['reported']['overflow_edges']}/{analysis['reported_vs_recomputed']['reported']['overflow_tracks']}; it missed the two `capacity:9 usage:10` records because of string comparison.",
        f"- At capacity: {totals['at_capacity_windows']}; below capacity: {totals['below_capacity_windows']}; maximum congestion: {totals['maximum_congestion']}",
        f"- CuGR iterative-RRR residual: {totals['rrr_residual']}",
        "- Existing AWK summaries were not used; `overflow=max(usage-capacity,0)` was recomputed per record.",
        "",
        "## Non-exclusive source attribution",
        "",
    ]
    category_rows: list[list[Any]] = []
    for category in CATEGORY_ORDER:
        all_value = all_summary["by_category_nonexclusive"][category]
        overflow_value = overflow_summary["by_category_nonexclusive"][category]
        category_rows.append(
            [
                category,
                all_value["windows"],
                overflow_value["windows"],
                overflow_value["source_net_occurrences"],
            ]
        )
    lines.extend(markdown_table(["Category", f"All {totals['windows']}", f"Overflow {totals['overflow_edges']}", "Overflow source occurrences"], category_rows))
    lines.extend(["", "Counts are non-exclusive; one window may contribute to multiple categories.", ""])

    lines.extend(["## Layer, source-quad, and spatial distribution", ""])
    layer_rows = [
        [layer, count, overflow_summary["by_layer"].get(layer, 0)]
        for layer, count in all_summary["by_layer"].items()
    ]
    lines.extend(markdown_table(["Layer", "All windows", "Overflow windows"], layer_rows))
    lines.append("")
    quad_rows = [
        [quad, count, overflow_summary["by_source_quad_nonexclusive"].get(quad, 0)]
        for quad, count in all_summary["by_source_quad_nonexclusive"].items()
    ]
    lines.extend(markdown_table(["Source quad", "All windows", "Overflow windows"], quad_rows))
    lines.extend(["", "Source-quad counts are non-exclusive and are inferred from `g_quad[n]` hierarchy or packed-signal bit ranges.", ""])
    region_order = ["Q0_fence", "Q1_fence", "Q2_fence", "Q3_fence", "central_corridor", "fence_boundary_overlap", "edge_guardband", "outside_core"]
    region_rows = [
        [region, all_summary["by_spatial_region"].get(region, 0), overflow_summary["by_spatial_region"].get(region, 0)]
        for region in region_order
        if all_summary["by_spatial_region"].get(region, 0) or overflow_summary["by_spatial_region"].get(region, 0)
    ]
    lines.extend(markdown_table(["Exact spatial region", "All windows", "Overflow windows"], region_rows))
    lines.extend([
        "",
        "Fence classification uses the exact B2 ODB coordinates recorded by placement: Q0 `(20.120,20.880)-(4265.444,4266.204)`, Q1 `(4772.176,20.880)-(9017.500,4266.204)`, Q2 `(20.120,4772.356)-(4265.444,9017.680)`, and Q3 `(4772.176,4772.356)-(9017.500,9017.680)`. The central corridor is the union of the exact horizontal and vertical gaps.",
        "",
        "## Leading overflow hotspots",
        "",
    ])
    hotspot_rows: list[list[Any]] = []
    for hotspot in analysis["hotspots"]["top_overflow"][:12]:
        bbox = ",".join(f"{value:.1f}" for value in hotspot["bbox_um"])
        top_sources = ", ".join(hotspot["sources"][:3])
        hotspot_rows.append(
            [
                hotspot["index"],
                hotspot["overflow"],
                hotspot["layer"],
                hotspot["spatial_region"],
                bbox,
                top_sources,
            ]
        )
    lines.extend(markdown_table(["Index", "Overflow", "Layer", "Region", "bbox um", "First source nets"], hotspot_rows))
    lines.extend([
        "",
        "## `pcu_writeback_tag` comparator-cone recurrence check",
        "",
        f"Conclusion: **{comparator['conclusion']}**.",
        "",
        f"The B2 report contains `pcu_writeback_tag` in {comparator['congestion_report']['windows']} windows ({comparator['congestion_report']['overflow_windows']} overflow window) and {comparator['congestion_report']['source_occurrences']} source occurrences. This residual presence is on the writeback/adapter path; it does not recreate the removed 16-bank central comparator sink cone.",
        f"The mapped assertion reports internal sink pins = {comparator['mapped_assertion']['internal_sink_pins']} with result `{comparator['mapped_assertion']['result']}`. Routed measurements report fanout total {comparator['routed_measurement']['total_sink_fanout']}, fanout max {comparator['routed_measurement']['fanout_max']}, median HPWL {comparator['routed_measurement']['hpwl_median_um']} um, and congested guide rectangles {comparator['routed_measurement']['congested_guide_rectangles']}.",
        "",
        "## Baseline comparison and Phase 5 contract",
        "",
    ])
    comparison_rows = []
    for metric in ("rrr_residual", "congestion_windows", "overflow_edges", "overflow_tracks", "maximum_congestion"):
        comparison_rows.append(
            [
                metric,
                comparison["frozen_A"][metric],
                comparison["quad_local_B"][metric],
                comparison["B2"][metric],
            ]
        )
    lines.extend(markdown_table(["Metric", "Frozen A", "B", "B2"], comparison_rows))
    lines.extend([
        "",
        f"Residual improves {comparison['B2_improvement_vs_A']['rrr_residual_reduction_percent']}% vs A and {comparison['B2_improvement_vs_B']['rrr_residual_reduction_percent']}% vs B. Overflow edges improve {comparison['B2_improvement_vs_A']['overflow_edges_reduction_percent']}% vs A and {comparison['B2_improvement_vs_B']['overflow_edges_reduction_percent']}% vs B.",
        "",
        "## Strict Phase 6 gate",
        "",
    ])
    strict_rows = [
        [name, value["required"], value["actual"], value["result"]]
        for name, value in phase6["conditions"].items()
    ]
    lines.extend(markdown_table(["Condition", "Required", "Actual", "Result"], strict_rows))
    lines.extend([
        "",
        f"Phase 6 remains fail-closed because residual congestion is {totals['rrr_residual']} rather than 0, overflow edges are {totals['overflow_edges']} rather than 0, and there is no explicit Phase 6 PASS. Artifact hashes do match, but that condition alone cannot authorize release.",
        "",
        "## Cheap next work without additional P&R",
        "",
        f"1. Review the {totals['overflow_edges']} parsed overflow records by dominant category and exact bbox, starting with the single overflow-2 edge and the highest repeated source nets.",
        "2. Use the existing routed measurements to compare fanout/HPWL/guide length for the leading adapter, scalar-return, bank-apply, and completion families; do not regenerate placement or routing.",
        "3. Add a unit test for this direct parser and B2 hierarchy-aware classification so `g_quad[n].u_payload_store` cannot regress to `adapter_entries=0`.",
        "4. Seal the four B2 route-artifact hashes together with this analysis and the Phase 5/6 decisions.",
        "",
        "## Preservation",
        "",
    ])
    preservation_rows = [
        [name, item["match"], item["actual_sha256"]]
        for name, item in analysis["artifact_integrity"]["preserved_routed_odb"].items()
    ]
    lines.extend(markdown_table(["Artifact", "Hash matches", "SHA-256"], preservation_rows))
    lines.extend([
        "",
        "All three routed ODB hashes match their previously sealed values. Frozen A, B, B2 route artifacts and evidence inputs were not modified; only the requested analysis/decision outputs were written.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--write", action="store_true", help="write analysis and decision outputs")
    args = parser.parse_args()
    root = args.root.resolve()
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    inputs = {name: root / relative for name, relative in INPUT_PATHS.items()}
    for path in inputs.values():
        if not path.is_file():
            raise FileNotFoundError(path)

    prior_phase6 = load_json(inputs["prior_phase6_gate"])
    input_evidence = {
        name: file_evidence(path)
        for name, path in inputs.items()
    }
    phase5_report = load_json(inputs["phase5_execution_report"])
    mapped_audit = load_json(inputs["mapped_locality_audit"])
    routed_measurements = load_json(inputs["routed_measurements"])
    records = parse_congestion_report(inputs["congestion_report"])
    if len(records) != 181:
        raise ValueError(f"expected 181 B2 windows, parsed {len(records)}")

    overflow_records = [record for record in records if record["overflow"] > 0]
    at_capacity = [record for record in records if record["at_capacity"]]
    if len(overflow_records) != 39:
        raise ValueError(f"expected 39 numeric overflow edges, parsed {len(overflow_records)}")
    if sum(record["overflow"] for record in overflow_records) != 40:
        raise ValueError("expected 40 numeric total overflow tracks")

    by_type = Counter(record["type"] for record in records)
    by_layer = Counter(record["layer"] for record in records)
    if by_type != Counter({"Horizontal congestion": 141, "Vertical congestion": 40}):
        raise ValueError(f"unexpected type totals: {by_type}")
    if by_layer != Counter({"met1": 133, "met2": 40, "met3": 8}):
        raise ValueError(f"unexpected layer totals: {by_layer}")

    log_text = inputs["global_route_log"].read_text(encoding="utf-8")
    rrr_match = re.search(r"Iterative RRR finished with congestion remaining \((\d+)\)", log_text)
    if not rrr_match:
        raise ValueError("RRR residual not found in global-route log")
    rrr_residual = int(rrr_match.group(1))

    route_hash_checks = artifact_hash_checks(root, phase5_report)
    route_hashes_match = all(check["match"] for check in route_hash_checks)
    odb_integrity = preserved_odb_checks(root)
    if not all(item["match"] for item in odb_integrity.values()):
        raise ValueError("a preserved routed ODB hash does not match its sealed value")

    pcu_records = [
        record
        for record in records
        if any("pcu_writeback_tag" in source for source in record["sources"])
    ]
    pcu_overflow = [record for record in pcu_records if record["overflow"] > 0]
    pcu_occurrences = sum(
        1
        for record in records
        for source in record["sources"]
        if "pcu_writeback_tag" in source
    )
    mapped_sink_check = find_check(mapped_audit, "no_central_16bank_writeback_tag_consumers")
    mapped_completion_check = find_check(mapped_audit, "central_completion_is_four_narrow_descriptors")
    pcu_measurement = routed_measurements["families"]["pcu_writeback_tag"]
    comparator_recurred = not (
        mapped_sink_check["result"] == "PASS"
        and mapped_sink_check["evidence"]["internal_sink_pins"] == 0
        and mapped_completion_check["result"] == "PASS"
        and pcu_measurement["congested_guide_rectangles"] == 0
    )

    b2_metrics = {
        "rrr_residual": rrr_residual,
        "congestion_windows": len(records),
        "overflow_edges": len(overflow_records),
        "overflow_tracks": sum(record["overflow"] for record in overflow_records),
        "maximum_congestion": max(record["congestion"] for record in records),
    }
    frozen_a = BASELINE_METRICS["frozen_A"]
    quad_b = BASELINE_METRICS["quad_local_B"]
    phase5_conditions = {
        "cheap_gate_pass": phase5_report["cheap_gate"]["result"] == "PASS",
        "mapped_contract_pass": phase5_report["mapped_contract"]["result"] == "PASS",
        "workload_accuracy_pass": phase5_report["accuracy"]["result"] == "PASS",
        "placement_legality_and_fences_pass": phase5_report["placement"]["result"] == "PASS",
        "global_route_invoked_exactly_once": phase5_report["global_route"]["invocation_count"] == 1,
        "residual_improves_vs_frozen_A": b2_metrics["rrr_residual"] < frozen_a["rrr_residual"],
        "overflow_edges_improve_vs_frozen_A": b2_metrics["overflow_edges"] < frozen_a["overflow_edges"],
        "route_artifact_hashes_match": route_hashes_match,
    }
    phase5_accept = all(phase5_conditions.values())

    explicit_phase6_pass = prior_phase6.get("decision") == "PASS"
    phase6_conditions = {
        "residual_congestion_zero": {
            "required": 0,
            "actual": rrr_residual,
            "result": "PASS" if rrr_residual == 0 else "FAIL",
        },
        "overflow_edges_zero": {
            "required": 0,
            "actual": len(overflow_records),
            "result": "PASS" if not overflow_records else "FAIL",
        },
        "input_artifact_hashes_match": {
            "required": True,
            "actual": route_hashes_match,
            "result": "PASS" if route_hashes_match else "FAIL",
        },
        "explicit_phase6_pass": {
            "required": True,
            "actual": explicit_phase6_pass,
            "result": "PASS" if explicit_phase6_pass else "FAIL",
        },
    }
    phase6_pass = all(item["result"] == "PASS" for item in phase6_conditions.values())

    hotspots = sorted(
        overflow_records,
        key=lambda record: (
            -record["overflow"],
            -float(record["congestion"]),
            -len(record["sources"]),
            record["bbox_um"][0],
            record["bbox_um"][1],
        ),
    )

    analysis: dict[str, Any] = {
        "schema_version": 1,
        "generated_at": generated_at,
        "variant": phase5_report["variant"],
        "analysis_mode": {
            "existing_artifacts_only": True,
            "physical_tool_invocations": 0,
            "parser": "Python direct four-line record parser",
            "ignored_summaries": [
                "reports/groot_normalization/quad_local_b2/b2_quad_local.congestion.summary",
                "reports/groot_normalization/quad_local_b2/b2_quad_local.sources.summary",
            ],
            "classification": "non-exclusive per source net",
            "overflow_formula": "max(usage - capacity, 0)",
        },
        "inputs": input_evidence,
        "geometry_um": {
            "core_bbox": CORE_BBOX_UM,
            "fence_bboxes": FENCE_BBOXES_UM,
            "central_corridor_strips": CORRIDOR_STRIPS_UM,
            "classification_rule": "full-bbox containment; boundary overlaps are reported separately",
        },
        "totals": {
            "windows": len(records),
            "by_type": dict(sorted(by_type.items())),
            "by_layer": dict(sorted(by_layer.items())),
            "rrr_residual": rrr_residual,
            "overflow_edges": len(overflow_records),
            "overflow_tracks": sum(record["overflow"] for record in overflow_records),
            "at_capacity_windows": len(at_capacity),
            "below_capacity_windows": len(records) - len(overflow_records) - len(at_capacity),
            "maximum_congestion": max(record["congestion"] for record in records),
        },
        "reported_vs_recomputed": {
            "reported": {
                "overflow_edges": 37,
                "overflow_tracks": 38,
                "source": "prior AWK summary / supplied checkpoint",
            },
            "recomputed": {
                "overflow_edges": len(overflow_records),
                "overflow_tracks": sum(record["overflow"] for record in overflow_records),
            },
            "difference": {
                "overflow_edges": len(overflow_records) - 37,
                "overflow_tracks": sum(record["overflow"] for record in overflow_records) - 38,
            },
            "missed_by_string_comparison": [
                compact_record(record)
                for record in overflow_records
                if record["capacity"] == 9 and record["usage"] == 10
            ],
            "conclusion": "The direct numeric parse is authoritative: both capacity-9/usage-10 records are overflow edges.",
        },
        "aggregates": {
            "all_windows": summarize_records(records),
            "overflow_windows": summarize_records(overflow_records),
        },
        "hotspots": {
            "ranking": "overflow desc, congestion desc, source-count desc, coordinate asc",
            "top_overflow": [compact_record(record) for record in hotspots],
        },
        "pcu_writeback_tag_comparator_cone": {
            "conclusion": "RECURRED" if comparator_recurred else "NOT_RECURRED",
            "congestion_report": {
                "windows": len(pcu_records),
                "overflow_windows": len(pcu_overflow),
                "overflow_tracks": sum(record["overflow"] for record in pcu_overflow),
                "source_occurrences": pcu_occurrences,
                "records": [compact_record(record) for record in pcu_records],
            },
            "mapped_assertion": {
                "result": mapped_sink_check["result"],
                "writeback_tag_width": mapped_sink_check["evidence"]["writeback_tag_width"],
                "internal_sink_pins": mapped_sink_check["evidence"]["internal_sink_pins"],
                "internal_sinks": mapped_sink_check["evidence"]["internal_sinks"],
                "completion_descriptor_result": mapped_completion_check["result"],
                "central_completion_tag_bits": mapped_completion_check["evidence"]["tag_bits"],
                "central_completion_valid_bits": mapped_completion_check["evidence"]["valid_bits"],
            },
            "routed_measurement": {
                key: pcu_measurement[key]
                for key in (
                    "net_count",
                    "total_sink_fanout",
                    "fanout_max",
                    "hpwl_median_um",
                    "hpwl_max_um",
                    "guide_length_um",
                    "guide_rectangles",
                    "congested_guide_rectangles",
                )
            },
            "reason": "The wide tag family remains on the writeback/adapter transport path, but mapped internal comparator sinks are zero and routed congested guide rectangles are zero; central matching uses four registered narrow descriptors.",
        },
        "comparison": {
            "frozen_A": frozen_a,
            "quad_local_B": quad_b,
            "B2": b2_metrics,
            "B2_improvement_vs_A": {
                "rrr_residual_reduction_percent": percent_reduction(frozen_a["rrr_residual"], b2_metrics["rrr_residual"]),
                "congestion_windows_reduction_percent": percent_reduction(frozen_a["congestion_windows"], b2_metrics["congestion_windows"]),
                "overflow_edges_reduction_percent": percent_reduction(frozen_a["overflow_edges"], b2_metrics["overflow_edges"]),
                "overflow_tracks_reduction_percent": percent_reduction(frozen_a["overflow_tracks"], b2_metrics["overflow_tracks"]),
            },
            "B2_improvement_vs_B": {
                "rrr_residual_reduction_percent": percent_reduction(quad_b["rrr_residual"], b2_metrics["rrr_residual"]),
                "congestion_windows_reduction_percent": percent_reduction(quad_b["congestion_windows"], b2_metrics["congestion_windows"]),
                "overflow_edges_reduction_percent": percent_reduction(quad_b["overflow_edges"], b2_metrics["overflow_edges"]),
                "overflow_tracks_reduction_percent": percent_reduction(quad_b["overflow_tracks"], b2_metrics["overflow_tracks"]),
            },
        },
        "phase5_contract_evaluation": {
            "decision": "ACCEPTED_WITH_RESIDUAL_CONGESTION" if phase5_accept else "REJECTED",
            "conditions": phase5_conditions,
            "all_conditions_pass": phase5_accept,
            "authorizes_phase6": False,
        },
        "phase6_strict_evaluation": {
            "decision": "PASS" if phase6_pass else "BLOCKED_RESIDUAL_CONGESTION",
            "conditions": phase6_conditions,
            "all_conditions_pass": phase6_pass,
            "authorizes": ["PHASE6"] if phase6_pass else [],
            "next_stage": "PHASE6" if phase6_pass else None,
        },
        "artifact_integrity": {
            "route_artifact_hashes": route_hash_checks,
            "all_route_artifact_hashes_match": route_hashes_match,
            "preserved_routed_odb": odb_integrity,
            "all_preserved_routed_odb_hashes_match": all(item["match"] for item in odb_integrity.values()),
        },
        "windows": records,
    }

    analysis_json_text = json.dumps(analysis, indent=2, sort_keys=False) + "\n"
    analysis_md_text = render_markdown(analysis)
    analysis_sha = hashlib.sha256(analysis_json_text.encode()).hexdigest()

    phase5_decision = {
        "schema_version": 1,
        "generated_at": generated_at,
        "phase": 5,
        "variant": phase5_report["variant"],
        "decision": analysis["phase5_contract_evaluation"]["decision"],
        "basis": "Frozen A comparison requires both residual congestion and overflow edges to improve.",
        "conditions": phase5_conditions,
        "metrics": {
            "frozen_A": frozen_a,
            "quad_local_B": quad_b,
            "B2": b2_metrics,
        },
        "analysis": {
            "path": OUTPUT_PATHS["analysis_json"],
            "sha256": analysis_sha,
        },
        "authorizes": [],
        "next_stage": None,
        "phase6_authorized": False,
    }
    phase5_text = json.dumps(phase5_decision, indent=2) + "\n"
    phase5_sha = hashlib.sha256(phase5_text.encode()).hexdigest()

    phase6_gate = {
        "schema_version": 2,
        "generated_at": generated_at,
        "phase": 6,
        "variant": phase5_report["variant"],
        "decision": analysis["phase6_strict_evaluation"]["decision"],
        "reason": "Residual congestion and overflow are nonzero; strict Phase 6 release remains fail-closed.",
        "conditions": phase6_conditions,
        "artifact_hash_checks": route_hash_checks,
        "phase5_residual_decision": {
            "path": OUTPUT_PATHS["phase5_decision"],
            "sha256": phase5_sha,
            "decision": phase5_decision["decision"],
        },
        "required_before_release": [
            "residual congestion equals 0",
            "overflow edges equal 0",
            "all input artifact hashes match",
            "a separate explicit Phase 6 decision returns PASS",
        ],
        "authorizes": [],
        "next_stage": None,
    }

    if args.write:
        output_paths = {name: root / relative for name, relative in OUTPUT_PATHS.items()}
        for path in output_paths.values():
            path.parent.mkdir(parents=True, exist_ok=True)
        output_paths["analysis_json"].write_text(analysis_json_text, encoding="utf-8")
        output_paths["analysis_md"].write_text(analysis_md_text, encoding="utf-8")
        output_paths["phase5_decision"].write_text(phase5_text, encoding="utf-8")
        output_paths["phase6_gate"].write_text(json.dumps(phase6_gate, indent=2) + "\n", encoding="utf-8")

    print(
        json.dumps(
            {
                "windows": len(records),
                "overflow_edges": len(overflow_records),
                "overflow_tracks": sum(record["overflow"] for record in overflow_records),
                "phase5": phase5_decision["decision"],
                "phase6": phase6_gate["decision"],
                "pcu_writeback_tag_comparator_cone": analysis["pcu_writeback_tag_comparator_cone"]["conclusion"],
                "route_artifact_hashes_match": route_hashes_match,
                "preserved_odb_hashes_match": analysis["artifact_integrity"]["all_preserved_routed_odb_hashes_match"],
                "wrote_outputs": args.write,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
