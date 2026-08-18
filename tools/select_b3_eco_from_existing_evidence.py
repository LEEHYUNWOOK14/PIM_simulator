#!/usr/bin/env python3
"""Select the lowest-risk B3 ECO using only sealed B2 text/JSON evidence."""

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B2 = ROOT / "reports/groot_normalization/quad_local_b2"
OUT = ROOT / "reports/groot_normalization/quad_local_b3"
ANALYSIS = B2 / "b2_residual_congestion_analysis.json"
MEASUREMENTS = B2 / "b2_routed_tag_completion_net_measurements.json"
NETLIST = B2 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
ROUTE_LOG = B2 / "b2_global_route.log"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def mapped_inverter_roots(text: str) -> dict[str, str]:
    roots: dict[str, str] = {}
    pattern = re.compile(
        r"\.A\((quad_completion_tag\[[0-9]+\])\),\s*\.Y\((_?[0-9]+_?)\)",
        re.MULTILINE,
    )
    for match in pattern.finditer(text):
        roots[match.group(2)] = match.group(1)
    return roots


def render(payload: dict) -> str:
    totals = payload["totals"]
    lines = [
        "# B2 cheap root-cause analysis and B3 ECO selection",
        "",
        f"Generated: `{payload['generated_at_utc']}`",
        "",
        "All evidence comes from existing B2 reports, mapped netlist, route log, and routed-family measurements. No placement or routing was run.",
        "",
        "## Verdict",
        "",
        f"- B2 residual: {totals['rrr_residual']}",
        f"- Actual numeric overflow: {totals['overflow_edges']} edges / {totals['overflow_tracks']} tracks",
        f"- Central corridor: {totals['central_corridor_overflow']} / {totals['overflow_edges']} overflow windows",
        f"- met1: {totals['met1_overflow']} / {totals['overflow_edges']} overflow windows",
        "- 38 edges have overflow 1 and one Q1 bank-reduction edge has overflow 2.",
        "- The B2 global route used one configured congestion iteration and stopped at residual 46.",
        "- Therefore a bounded route-effort ECO is selected before another functional RTL change.",
        "",
        "## Repeated overflow source ranking",
        "",
        "| source | windows | overflow contribution | mapped/routed evidence | fanout | HPWL um | guide um |",
        "|---|---:|---:|---|---:|---:|---:|",
    ]
    for item in payload["ranked_sources"][:32]:
        routed = item.get("routed_measurement") or {}
        fanout = routed.get("sink_fanout", "-")
        hpwl = routed.get("terminal_hpwl_um")
        guide = routed.get("guide_length_um")
        hpwl_text = "-" if hpwl is None else f"{hpwl:.3f}"
        guide_text = "-" if guide is None else f"{guide:.3f}"
        lines.append(
            f"| `{item['name']}` | {item['window_occurrences']} | "
            f"{item['overflow_track_contribution']} | {item['trace_label']} | "
            f"{fanout} | {hpwl_text} | {guide_text} |"
        )
    lines.extend(
        [
            "",
            "## `clk_i`",
            "",
            f"- Appears in {payload['clock']['overflow_window_occurrences']} overflow windows.",
            f"- The route log explicitly skipped it with {payload['clock']['skipped_terminals']} terminals.",
            "- Decision: `CO_RESIDENT_SKIPPED_NET`, not the routed cause of the 39 overflow edges.",
            "",
            "## Existing routed-family evidence",
            "",
            "| family | nets | fanout total/max | HPWL median/max um | guide length um | congested guide rectangles |",
            "|---|---:|---:|---:|---:|---:|",
        ]
    )
    for family, data in payload["routed_families"].items():
        lines.append(
            f"| `{family}` | {data['net_count']} | {data['total_sink_fanout']}/{data['fanout_max']} | "
            f"{data['hpwl_median_um']:.3f}/{data['hpwl_max_um']:.3f} | "
            f"{data['guide_length_um']:.3f} | {data['congested_guide_rectangles']} |"
        )
    lines.extend(
        [
            "",
            "## Selected B3 ECO",
            "",
            "**SELECT_B3_ROUTE_EFFORT_ECO**",
            "",
            "B3 preserves the B2 RTL/netlist behavior and four-fence geometry, creates a new variant/output directory, reruns all nine cheap gates, produces one new incremental placement checkpoint from the read-only B2 placed ODB, and invokes CUGR exactly once with ten congestion iterations. This changes routing effort, not arithmetic, protocol, tag-completion behavior, or the frozen B2 artifacts.",
            "",
            "If B3 remains nonzero, it is sealed without rerouting and a separately justified B4 placement/RTL ECO is required.",
            "",
            "## Current authorization",
            "",
            "`authorizes=[]`; `next_stage=B3_IMPLEMENTATION_AND_CHEAP_GATES`. Placement is not authorized until the fresh B3 cheap manifest passes 9/9.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    analysis = json.loads(ANALYSIS.read_text(encoding="utf-8"))
    measurements = json.loads(MEASUREMENTS.read_text(encoding="utf-8"))
    netlist_text = NETLIST.read_text(encoding="utf-8", errors="replace")
    route_log = ROUTE_LOG.read_text(encoding="utf-8", errors="replace")

    if analysis["totals"]["overflow_edges"] != 39 or analysis["totals"]["overflow_tracks"] != 40:
        raise SystemExit("direct numeric B2 overflow totals are not 39/40")
    if "Iterative RRR finished with congestion remaining (46)" not in route_log:
        raise SystemExit("B2 residual 46 token is missing")
    if "-congestion_iterations 1" not in (ROOT / "verification/groot_normalization/wbq_quad_local_global_route.tcl").read_text(encoding="utf-8"):
        raise SystemExit("B2 one-iteration route policy is no longer present")

    skipped_match = re.search(r"Skipping net clk_i with ([0-9]+) terminals", route_log)
    if not skipped_match:
        raise SystemExit("clk_i skip evidence is missing")

    occurrence: Counter[str] = Counter()
    overflow_contribution: Counter[str] = Counter()
    categories: dict[str, set[str]] = defaultdict(set)
    regions: dict[str, set[str]] = defaultdict(set)
    layers: dict[str, set[str]] = defaultdict(set)
    for window in analysis["windows"]:
        if window["overflow"] <= 0:
            continue
        attribution = {item["name"]: item for item in window["source_attribution"]}
        for name in window["sources"]:
            occurrence[name] += 1
            overflow_contribution[name] += window["overflow"]
            categories[name].update(attribution[name]["categories"])
            regions[name].add(window["spatial_region"])
            layers[name].add(window["layer"])

    routed_by_name = {record["name"]: record for record in measurements["nets"]}
    inverter_roots = mapped_inverter_roots(netlist_text)
    if inverter_roots.get("_0712_") != "quad_completion_tag[54]":
        raise SystemExit("mapped _0712_ completion root mismatch")
    if inverter_roots.get("_0732_") != "quad_completion_tag[35]":
        raise SystemExit("mapped _0732_ completion root mismatch")

    ranked = []
    for name, count in occurrence.most_common():
        local = name.rsplit("/", 1)[-1]
        routed = routed_by_name.get(name)
        if local in inverter_roots:
            trace = f"mapped inverter of `{inverter_roots[local]}`"
        elif routed is not None:
            trace = f"routed `{routed['family']}` family"
        elif re.fullmatch(r"net[0-9]+", local):
            trace = "post-map repair fragment; owning hierarchy/category retained"
        elif local.startswith("_") and local.endswith("_"):
            trace = "mapped synthetic PCU/leaf logic; category from co-resident named nets"
        else:
            trace = "named RTL/mapped net"
        ranked.append(
            {
                "name": name,
                "window_occurrences": count,
                "overflow_track_contribution": overflow_contribution[name],
                "categories": sorted(categories[name]),
                "regions": sorted(regions[name]),
                "layers": sorted(layers[name]),
                "trace_label": trace,
                "mapped_upstream": inverter_roots.get(local),
                "routed_measurement": (
                    {
                        key: routed[key]
                        for key in (
                            "family",
                            "sink_fanout",
                            "terminal_hpwl_um",
                            "guide_length_um",
                            "guide_rectangles",
                            "congested_guide_rectangles",
                        )
                    }
                    if routed is not None
                    else None
                ),
            }
        )

    overflow = analysis["aggregates"]["overflow_windows"]
    generated = datetime.now(timezone.utc).isoformat()
    payload = {
        "schema_version": 1,
        "generated_at_utc": generated,
        "mode": "existing_artifacts_only_no_openroad",
        "inputs": {
            "analysis": {"path": str(ANALYSIS.relative_to(ROOT)), "sha256": sha256(ANALYSIS)},
            "measurements": {"path": str(MEASUREMENTS.relative_to(ROOT)), "sha256": sha256(MEASUREMENTS)},
            "mapped_netlist": {"path": str(NETLIST.relative_to(ROOT)), "sha256": sha256(NETLIST)},
            "route_log": {"path": str(ROUTE_LOG.relative_to(ROOT)), "sha256": sha256(ROUTE_LOG)},
        },
        "totals": {
            "rrr_residual": analysis["totals"]["rrr_residual"],
            "overflow_edges": analysis["totals"]["overflow_edges"],
            "overflow_tracks": analysis["totals"]["overflow_tracks"],
            "central_corridor_overflow": overflow["by_spatial_region"]["central_corridor"],
            "met1_overflow": overflow["by_layer"]["met1"],
            "unique_overflow_source_nets": len(occurrence),
        },
        "clock": {
            "overflow_window_occurrences": occurrence["clk_i"],
            "skipped_terminals": int(skipped_match.group(1)),
            "decision": "CO_RESIDENT_SKIPPED_NET",
        },
        "mapped_trace_checks": {
            "_0712_": inverter_roots["_0712_"],
            "_0732_": inverter_roots["_0732_"],
            "post_map_net_fragments_are_absent_from_mapped_netlist": all(
                name.rsplit("/", 1)[-1] not in netlist_text
                for name in occurrence
                if re.fullmatch(r"net4[0-9]+", name.rsplit("/", 1)[-1])
            ),
        },
        "ranked_sources": ranked,
        "routed_families": measurements["families"],
        "root_cause": {
            "dominant_location": "central corridor (31/39 overflow windows)",
            "dominant_layer": "met1 (31/39 overflow windows)",
            "dominant_named_function": "registered quad completion/context plus scalar/adapter traffic",
            "single_overflow_two_hotspot": "Q1 bank-reduction at (7445.1,1414.5)-(7452.0,1421.4)",
            "pcu_writeback_comparator_recurrence": "NOT_RECURRED",
            "route_policy_observation": "B2 used one configured CUGR congestion iteration",
        },
        "b3_eco_decision": {
            "decision": "SELECT_B3_ROUTE_EFFORT_ECO",
            "status": "SELECTED_PENDING_CHEAP_GATES",
            "change_scope": "B3-only config/run policy; B2 RTL behavior and A/B/B2 artifacts remain frozen",
            "cugr_congestion_iterations": 10,
            "global_route_invocation_limit": 1,
            "new_incremental_placement_required": True,
            "fallback": "Seal nonzero B3 without reroute; create B4 for a separately justified placement/RTL ECO.",
            "authorizes": [],
            "next_stage": "B3_IMPLEMENTATION_AND_CHEAP_GATES",
        },
        "execution_assertions": {
            "placement_started": False,
            "global_route_started": False,
            "detailed_route_started": False,
            "cts_started": False,
        },
    }

    OUT.mkdir(parents=True, exist_ok=True)
    json_path = OUT / "b3_cheap_root_cause_analysis.json"
    md_path = OUT / "b3_cheap_root_cause_analysis.md"
    decision_path = OUT / "b3_eco_decision.json"
    json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_path.write_text(render(payload), encoding="utf-8")
    decision = {
        "schema_version": 1,
        "generated_at_utc": generated,
        "source_analysis": {
            "path": str(json_path.relative_to(ROOT)),
            "sha256": sha256(json_path),
        },
        **payload["b3_eco_decision"],
    }
    decision_path.write_text(json.dumps(decision, indent=2) + "\n", encoding="utf-8")
    print("B3_CHEAP_ROOT_CAUSE PASS")
    print("B3_ECO_DECISION SELECT_B3_ROUTE_EFFORT_ECO iterations=10 authorizes=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
