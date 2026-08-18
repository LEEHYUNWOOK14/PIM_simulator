#!/usr/bin/env python3
"""Directly parse one routed variant's congestion evidence using numeric fields."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from analyze_b2_residual_congestion import compact_record, parse_congestion_report, summarize_records


PRESERVED = {
    "frozen_A": (
        "reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb",
        "964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad",
    ),
    "B": (
        "reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb",
        "ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235",
    ),
    "B2": (
        "reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb",
        "2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d",
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def evidence(path: Path) -> dict:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def render_markdown(data: dict) -> str:
    totals = data["totals"]
    lines = [
        f"# {data['variant']} residual congestion analysis",
        "",
        f"Generated: `{data['generated_at_utc']}`",
        "",
        "The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.",
        "",
        "## Direct result",
        "",
        f"- RRR residual: **{totals['rrr_residual']}**",
        f"- Overflow edges/tracks: **{totals['overflow_edges']} / {totals['overflow_tracks']}**",
        f"- Congestion windows: **{totals['windows']}**; at capacity: **{totals['at_capacity_windows']}**",
        f"- Maximum congestion: **{totals['maximum_congestion']}**",
        f"- Layers: `{json.dumps(totals['by_layer'], sort_keys=True)}`",
        f"- Global-route invocation count: **{data['global_route']['invocation_count']}**",
        "",
        "## Overflow distribution",
        "",
        f"- Spatial: `{json.dumps(data['aggregates']['overflow_windows']['by_spatial_region'], sort_keys=True)}`",
        f"- Source quad, non-exclusive: `{json.dumps(data['aggregates']['overflow_windows']['by_source_quad_nonexclusive'], sort_keys=True)}`",
        "",
        "## Leading overflow hotspots",
        "",
        "| Overflow | Layer | Region | bbox (um) | Leading sources |",
        "| --- | --- | --- | --- | --- |",
    ]
    for item in data["hotspots"][:15]:
        bbox = ", ".join(str(value) for value in item["bbox_um"])
        sources = ", ".join(item["sources"][:4]).replace("|", "\\|")
        lines.append(f"| {item['overflow']} | {item['layer']} | {item['spatial_region']} | {bbox} | {sources} |")
    if not data["hotspots"]:
        lines.append("| 0 | — | — | — | none |")
    lines.extend([
        "",
        "## Preservation",
        "",
    ])
    for name, item in data["preserved_routed_odb"].items():
        lines.append(f"- {name}: `{item['actual_sha256']}` — {'MATCH' if item['match'] else 'MISMATCH'}")
    lines.extend([
        "",
        f"Physical zero-congestion evidence: **{data['zero_congestion_evidence']}**.",
        "This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--variant", default="B3")
    parser.add_argument("--pass-token", default="WBQ_B3_SINGLE_GLOBAL_ROUTE PASS")
    parser.add_argument("--cugr-iterations", type=int, default=10)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--guide", type=Path, required=True)
    parser.add_argument("--odb", type=Path, required=True)
    parser.add_argument("--sdc", type=Path, required=True)
    parser.add_argument("--invocation", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-md", type=Path, required=True)
    parser.add_argument(
        "--max-hotspots-in-output",
        type=int,
        default=-1,
        help="retain at most this many sorted overflow hotspots; -1 retains all",
    )
    parser.add_argument(
        "--max-windows-in-output",
        type=int,
        default=-1,
        help="retain at most this many raw windows; -1 retains all",
    )
    args = parser.parse_args()
    if args.max_hotspots_in_output < -1 or args.max_windows_in_output < -1:
        raise ValueError("compact output limits must be -1 or non-negative")
    root = args.root.resolve()
    paths = [args.report, args.log, args.guide, args.odb, args.sdc, args.invocation]
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(path)
    if args.output_json.exists() or args.output_md.exists():
        raise FileExistsError("refusing to overwrite sealed variant congestion analysis")

    records = parse_congestion_report(args.report)
    overflow = [record for record in records if record["overflow"] > 0]
    log_text = args.log.read_text(encoding="utf-8", errors="replace")
    residual_matches = re.findall(r"Iterative RRR finished with congestion remaining \((\d+)\)", log_text)
    if len(residual_matches) > 1:
        raise ValueError(f"multiple final RRR residual messages found: {residual_matches}")
    route_pass = args.pass_token in log_text
    if residual_matches:
        residual = int(residual_matches[0])
        residual_evidence = "explicit OpenROAD GRT-0118 residual warning"
    elif route_pass:
        # CuGR emits GRT-0118 iff totalOverflow() is positive.  A successful
        # non-incremental route with no such warning therefore has residual 0.
        residual = 0
        residual_evidence = "successful non-incremental CuGR route with no conditional GRT-0118 warning"
    else:
        raise ValueError("cannot establish final RRR residual from a failed/incomplete route log")

    invocation = json.loads(args.invocation.read_text(encoding="utf-8"))
    if invocation.get("invocation_count") != 1:
        raise ValueError("global-route invocation count is not exactly one")
    preserved = {}
    for name, (relative, expected) in PRESERVED.items():
        path = root / relative
        actual = sha256(path)
        preserved[name] = {
            "path": str(path),
            "expected_sha256": expected,
            "actual_sha256": actual,
            "match": actual == expected,
        }
    if not all(item["match"] for item in preserved.values()):
        raise ValueError("a frozen A/B/B2 routed ODB hash changed")

    by_layer = Counter(record["layer"] for record in records)
    by_type = Counter(record["type"] for record in records)
    totals = {
        "rrr_residual": residual,
        "windows": len(records),
        "overflow_edges": len(overflow),
        "overflow_tracks": sum(record["overflow"] for record in overflow),
        "at_capacity_windows": sum(record["at_capacity"] for record in records),
        "below_capacity_windows": sum(record["usage"] < record["capacity"] for record in records),
        "maximum_congestion": max((record["congestion"] for record in records), default=0),
        "by_layer": dict(sorted(by_layer.items())),
        "by_type": dict(sorted(by_type.items())),
    }
    hotspots = sorted(
        overflow,
        key=lambda record: (-record["overflow"], -float(record["congestion"]), -len(record["sources"]), record["index"]),
    )
    retained_hotspots = hotspots if args.max_hotspots_in_output == -1 else hotspots[: args.max_hotspots_in_output]
    retained_windows = records if args.max_windows_in_output == -1 else records[: args.max_windows_in_output]
    zero = residual == 0 and len(overflow) == 0
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": args.variant,
        "parser_policy": "direct numeric capacity/usage parsing; no AWK decision evidence",
        "totals": totals,
        "aggregates": {
            "all_windows": summarize_records(records),
            "overflow_windows": summarize_records(overflow),
        },
        "compact_output_policy": {
            "total_hotspots": len(hotspots),
            "retained_hotspots": len(retained_hotspots),
            "total_windows": len(records),
            "retained_windows": len(retained_windows),
            "max_hotspots_in_output": args.max_hotspots_in_output,
            "max_windows_in_output": args.max_windows_in_output,
        },
        "hotspots": [compact_record(record) for record in retained_hotspots],
        "windows": [compact_record(record) for record in retained_windows],
        "global_route": {
            "invocation_count": invocation["invocation_count"],
            "cugr_congestion_iterations": args.cugr_iterations,
            "rrr_residual_evidence": residual_evidence,
            "artifacts": {
                "congestion_report": evidence(args.report),
                "log": evidence(args.log),
                "route_guide": evidence(args.guide),
                "routed_odb": evidence(args.odb),
                "routed_sdc": evidence(args.sdc),
                "invocation_record": evidence(args.invocation),
            },
        },
        "preserved_routed_odb": preserved,
        "zero_congestion_evidence": "PASS" if zero else "FAIL",
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    with args.output_json.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2)
        stream.write("\n")
    with args.output_md.open("x", encoding="utf-8") as stream:
        stream.write(render_markdown(payload))
    print(
        f"{args.variant}_DIRECT_CONGESTION_PARSE PASS residual={residual} "
        f"overflow_edges={len(overflow)} overflow_tracks={totals['overflow_tracks']} windows={len(records)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
