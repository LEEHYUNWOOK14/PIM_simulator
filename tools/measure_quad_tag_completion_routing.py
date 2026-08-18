#!/usr/bin/env python3
"""Measure tag/completion feedback topology in an existing routed OpenDB.

Run this script with OpenROAD's Python interpreter.  It is intentionally
read-only: the input ODB is opened, inspected, and never written back.
"""

from __future__ import annotations

import json
import os
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import odb


ROOT = str(Path(__file__).resolve().parents[1])
DEFAULT_ODB = os.path.join(
    ROOT,
    "reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb",
)
DEFAULT_JSON = os.path.join(
    ROOT,
    "reports/groot_normalization/quad_local_ab/"
    "b_routed_tag_completion_net_measurements.json",
)
DEFAULT_MD = os.path.join(
    ROOT,
    "reports/groot_normalization/quad_local_ab/"
    "b_routed_tag_completion_net_measurements.md",
)


def family_for(name: str) -> str | None:
    """Return the narrow feedback family under audit, if any."""
    if "pcu_writeback_tag" in name:
        return "pcu_writeback_tag"
    if "writeback_tag" in name:
        return "writeback_tag"
    if "quad_completion" in name:
        return "quad_completion"
    if "completion_bits" in name:
        return "completion_bits"
    if "ctx_tag_q" in name or "context_tag" in name:
        return "context_tag"
    return None


def median(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * pct))
    return ordered[index]


def rect_measure(box, dbu: int) -> tuple[float, float, float]:
    dx = max(0, box.xMax() - box.xMin()) / dbu
    dy = max(0, box.yMax() - box.yMin()) / dbu
    return dx, dy, max(dx, dy)


def terminal_points(net) -> tuple[list[tuple[int, int]], int, int, list[str]]:
    points: list[tuple[int, int]] = []
    sources = 0
    sinks = 0
    endpoints: list[str] = []

    for iterm in net.getITerms():
        io_type = iterm.getIoType()
        direction = (
            io_type.getString() if hasattr(io_type, "getString") else str(io_type)
        ).upper()
        if direction in ("INPUT", "INOUT"):
            sinks += 1
        if direction in ("OUTPUT", "INOUT"):
            sources += 1
        inst = iterm.getInst()
        endpoints.append(f"{inst.getName()}/{iterm.getMTerm().getName()}:{direction}")
        valid, x, y = iterm.getAvgXY()
        if valid:
            points.append((x, y))
        elif inst.isPlaced():
            box = inst.getBBox()
            points.append(((box.xMin() + box.xMax()) // 2, (box.yMin() + box.yMax()) // 2))

    for bterm in net.getBTerms():
        io_type = bterm.getIoType()
        direction = (
            io_type.getString() if hasattr(io_type, "getString") else str(io_type)
        ).upper()
        # At the block boundary an INPUT drives the internal net and an OUTPUT
        # consumes it, the reverse of an instance terminal.
        if direction in ("OUTPUT", "INOUT"):
            sinks += 1
        if direction in ("INPUT", "INOUT"):
            sources += 1
        endpoints.append(f"BTERM/{bterm.getName()}:{direction}")
        for bpin in bterm.getBPins():
            box = bpin.getBBox()
            points.append(((box.xMin() + box.xMax()) // 2, (box.yMin() + box.yMax()) // 2))

    return points, sources, sinks, endpoints


def measure_net(net, family: str, dbu: int) -> dict:
    points, sources, sinks, endpoints = terminal_points(net)
    if points:
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        span_x = (max(xs) - min(xs)) / dbu
        span_y = (max(ys) - min(ys)) / dbu
    else:
        span_x = 0.0
        span_y = 0.0

    guide_layers: dict[str, dict[str, float | int]] = defaultdict(
        lambda: {"rectangles": 0, "length_um": 0.0, "area_um2": 0.0, "congested": 0}
    )
    guide_count = 0
    guide_length = 0.0
    guide_congested = 0
    for guide in net.getGuides():
        layer_name = guide.getLayer().getName()
        dx, dy, length = rect_measure(guide.getBox(), dbu)
        data = guide_layers[layer_name]
        data["rectangles"] += 1
        data["length_um"] += length
        data["area_um2"] += dx * dy
        guide_count += 1
        guide_length += length
        if guide.isCongested():
            data["congested"] += 1
            guide_congested += 1

    track_layers: dict[str, dict[str, float | int]] = defaultdict(
        lambda: {"rectangles": 0, "length_um": 0.0, "area_um2": 0.0}
    )
    track_count = 0
    track_length = 0.0
    for track in net.getTracks():
        layer_name = track.getLayer().getName()
        dx, dy, length = rect_measure(track.getBox(), dbu)
        data = track_layers[layer_name]
        data["rectangles"] += 1
        data["length_um"] += length
        data["area_um2"] += dx * dy
        track_count += 1
        track_length += length

    return {
        "name": net.getName(),
        "family": family,
        "sources": sources,
        "sink_fanout": sinks,
        "terminal_count": len(endpoints),
        "terminal_span_x_um": span_x,
        "terminal_span_y_um": span_y,
        "terminal_hpwl_um": span_x + span_y,
        "guide_rectangles": guide_count,
        "guide_length_um": guide_length,
        "congested_guide_rectangles": guide_congested,
        "guide_layers": dict(sorted(guide_layers.items())),
        "track_rectangles": track_count,
        "track_length_um": track_length,
        "track_layers": dict(sorted(track_layers.items())),
        "endpoints": sorted(endpoints),
    }


def aggregate(records: list[dict]) -> dict:
    result: dict[str, dict] = {}
    by_family: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        by_family[record["family"]].append(record)

    for family, members in sorted(by_family.items()):
        fanouts = [record["sink_fanout"] for record in members]
        hpwls = [record["terminal_hpwl_um"] for record in members]
        spans_x = [record["terminal_span_x_um"] for record in members]
        spans_y = [record["terminal_span_y_um"] for record in members]
        guide_lengths = [record["guide_length_um"] for record in members]
        guide_layer_rectangles: Counter[str] = Counter()
        guide_layer_lengths: defaultdict[str, float] = defaultdict(float)
        track_layer_rectangles: Counter[str] = Counter()
        track_layer_lengths: defaultdict[str, float] = defaultdict(float)
        for record in members:
            for layer, data in record["guide_layers"].items():
                guide_layer_rectangles[layer] += data["rectangles"]
                guide_layer_lengths[layer] += data["length_um"]
            for layer, data in record["track_layers"].items():
                track_layer_rectangles[layer] += data["rectangles"]
                track_layer_lengths[layer] += data["length_um"]

        result[family] = {
            "net_count": len(members),
            "total_sink_fanout": sum(fanouts),
            "fanout_median": median(fanouts),
            "fanout_p95": percentile(fanouts, 0.95),
            "fanout_max": max(fanouts, default=0),
            "span_x_max_um": max(spans_x, default=0.0),
            "span_y_max_um": max(spans_y, default=0.0),
            "hpwl_median_um": median(hpwls),
            "hpwl_p95_um": percentile(hpwls, 0.95),
            "hpwl_max_um": max(hpwls, default=0.0),
            "guide_rectangles": sum(record["guide_rectangles"] for record in members),
            "guide_length_um": sum(guide_lengths),
            "congested_guide_rectangles": sum(
                record["congested_guide_rectangles"] for record in members
            ),
            "guide_layers": {
                layer: {
                    "rectangles": guide_layer_rectangles[layer],
                    "length_um": guide_layer_lengths[layer],
                }
                for layer in sorted(guide_layer_rectangles)
            },
            "track_rectangles": sum(record["track_rectangles"] for record in members),
            "track_length_um": sum(record["track_length_um"] for record in members),
            "track_layers": {
                layer: {
                    "rectangles": track_layer_rectangles[layer],
                    "length_um": track_layer_lengths[layer],
                }
                for layer in sorted(track_layer_rectangles)
            },
        }
    return result


def render_markdown(payload: dict) -> str:
    lines = [
        "# Existing routed B tag/completion net measurement",
        "",
        f"- Generated: `{payload['generated_at_utc']}`",
        f"- Input ODB: `{payload['input_odb']}`",
        f"- ODB SHA-256: `{payload['input_odb_sha256']}`",
        f"- Design: `{payload['design']}`",
        f"- DBU/um: `{payload['dbu_per_micron']}`",
        "- Mode: read-only ODB inspection; no placement or routing was rerun.",
        "- Span/HPWL: placed terminal-center bounding box.",
        "- Layer usage: OpenDB global-route guide rectangles; length is the longer rectangle dimension.",
        "",
        "## Family summary",
        "",
        "| family | nets | sink fanout total/max | HPWL median/p95/max (um) | guide rects | guide length (um) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for family, data in payload["families"].items():
        lines.append(
            f"| `{family}` | {data['net_count']} | "
            f"{data['total_sink_fanout']}/{data['fanout_max']} | "
            f"{data['hpwl_median_um']:.3f}/{data['hpwl_p95_um']:.3f}/"
            f"{data['hpwl_max_um']:.3f} | {data['guide_rectangles']} | "
            f"{data['guide_length_um']:.3f} |"
        )
        lines.extend(["", f"### `{family}` guide layers", ""])
        lines.extend(["| layer | rectangles | length (um) |", "|---|---:|---:|"])
        if data["guide_layers"]:
            for layer, layer_data in data["guide_layers"].items():
                lines.append(
                    f"| `{layer}` | {layer_data['rectangles']} | "
                    f"{layer_data['length_um']:.3f} |"
                )
        else:
            lines.append("| _none_ | 0 | 0.000 |")

    lines.extend(
        [
            "",
            "## Highest-span nets",
            "",
            "| net | family | sinks | span x/y (um) | HPWL (um) | guide length (um) |",
            "|---|---|---:|---:|---:|---:|",
        ]
    )
    for record in sorted(
        payload["nets"], key=lambda item: item["terminal_hpwl_um"], reverse=True
    )[:24]:
        lines.append(
            f"| `{record['name']}` | `{record['family']}` | "
            f"{record['sink_fanout']} | {record['terminal_span_x_um']:.3f}/"
            f"{record['terminal_span_y_um']:.3f} | {record['terminal_hpwl_um']:.3f} | "
            f"{record['guide_length_um']:.3f} |"
        )
    lines.append("")
    return "\n".join(lines)


def sha256_file(path: str) -> str:
    import hashlib

    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    odb_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ODB
    json_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_JSON
    md_path = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_MD
    if not os.path.isfile(odb_path):
        raise SystemExit(f"input ODB not found: {odb_path}")

    database = odb.read_db(None, odb_path)
    chip = database.getChip()
    if chip is None or chip.getBlock() is None:
        raise SystemExit(f"ODB has no design block: {odb_path}")
    block = chip.getBlock()
    dbu = block.getDbUnitsPerMicron()

    records = []
    for net in block.getNets():
        family = family_for(net.getName())
        if family is not None:
            records.append(measure_net(net, family, dbu))

    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_odb": os.path.abspath(odb_path),
        "input_odb_size_bytes": os.path.getsize(odb_path),
        "input_odb_sha256": sha256_file(odb_path),
        "design": block.getName(),
        "dbu_per_micron": dbu,
        "measurement_contract": {
            "read_only": True,
            "terminal_span": "bounding box of placed terminal centers",
            "fanout": "count of input/inout ITerms plus output/inout BTerms",
            "layer_usage": "OpenDB global-route guides grouped by routing layer",
            "guide_length": "sum of max(rectangle width, rectangle height)",
        },
        "families": aggregate(records),
        "nets": sorted(records, key=lambda item: item["name"]),
    }

    os.makedirs(os.path.dirname(json_path), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
    with open(md_path, "w", encoding="utf-8") as stream:
        stream.write(render_markdown(payload))

    print(f"TAG_COMPLETION_MEASUREMENT_JSON {json_path}")
    print(f"TAG_COMPLETION_MEASUREMENT_MD {md_path}")
    for family, data in payload["families"].items():
        print(
            "TAG_COMPLETION_FAMILY "
            f"{family} nets={data['net_count']} fanout={data['total_sink_fanout']} "
            f"hpwl_max_um={data['hpwl_max_um']:.3f} "
            f"guide_length_um={data['guide_length_um']:.3f}"
        )
    return 0


if __name__ == "__main__":
    # OpenROAD's embedded Python wrapper reports even SystemExit(0) as a
    # traceback/non-zero process status.  Let normal module return semantics
    # carry a successful read-only measurement instead.
    main()
