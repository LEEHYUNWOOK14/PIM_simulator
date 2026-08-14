#!/usr/bin/env python3
"""Collect and render the Phase-3 wbq placement/legalization evidence."""

from __future__ import annotations

import hashlib
import html
import json
import os
import platform
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORFS_ROOT = Path(os.environ.get("ORFS_ROOT", ROOT.parent / "OpenROAD-flow-scripts"))
ORFS_FLOW = ORFS_ROOT / "flow"
RESULTS = ORFS_FLOW / "results/sky130hd/normalization_hbm_wbq/base"
LOGS = ORFS_FLOW / "logs/sky130hd/normalization_hbm_wbq/base"
RAW = ROOT / "reports/groot_normalization/physical_feasibility"
OUT = ROOT / "reports/final_integrated_gds_execution"
RUN_LOG = RAW / "logic_die_normalization_hbm_top_wbq_orfs_place.log"
AUDIT_LOG = RAW / "logic_die_normalization_hbm_top_wbq_place_audit.log"
FANOUT_LOG = RAW / "logic_die_normalization_hbm_top_wbq_net_fanout_audit.log"
NETLIST = RAW / "logic_die_normalization_hbm_top_wbq_sky130.v"
CONFIG = ROOT / "flow/designs/sky130hd/normalization_hbm_wbq/config.mk"
ODB = RESULTS / "3_place.odb"
SDC = RESULTS / "3_place.sdc"
DP_LOG = LOGS / "3_5_place_dp.log"
FLOORPLAN_LOG = LOGS / "2_1_floorplan.log"
IOP_LOG = LOGS / "3_2_place_iop.log"
PLATFORM_CONFIG = ORFS_FLOW / "platforms/sky130hd/config.mk"
FASTROUTE_TCL = ORFS_FLOW / "platforms/sky130hd/fastroute.tcl"
INPUT_SDC = ROOT / "flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc"
RESIZE_TCL = ORFS_FLOW / "scripts/resize.tcl"
CTS_TCL = ORFS_FLOW / "scripts/cts.tcl"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def one(pattern: str, text: str, cast=str, *, last: bool = False):
    values = re.findall(pattern, text, flags=re.MULTILINE)
    if not values:
        return None
    value = values[-1] if last else values[0]
    return cast(value)


def kv(text: str, key: str) -> str | None:
    return one(rf"^{re.escape(key)}=(.*)$", text)


def git_file_sha256(repo: Path, revision: str, relative_path: str) -> str:
    data = subprocess.check_output(
        ["git", "-C", str(repo), "show", f"{revision}:{relative_path}"]
    )
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    required = [
        RUN_LOG, AUDIT_LOG, NETLIST, CONFIG, ODB, SDC, DP_LOG,
        FLOORPLAN_LOG, IOP_LOG,
        PLATFORM_CONFIG, FASTROUTE_TCL,
        INPUT_SDC, RESIZE_TCL, CTS_TCL,
    ]
    missing = [str(path) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("missing/non-empty Phase-3 artifacts:\n" + "\n".join(missing))

    run = RUN_LOG.read_text(encoding="utf-8", errors="replace")
    audit = AUDIT_LOG.read_text(encoding="utf-8", errors="replace")
    fanout = FANOUT_LOG.read_text(encoding="utf-8", errors="replace") if FANOUT_LOG.is_file() else ""
    dp = DP_LOG.read_text(encoding="utf-8", errors="replace")
    floorplan = FLOORPLAN_LOG.read_text(encoding="utf-8", errors="replace")
    iop = IOP_LOG.read_text(encoding="utf-8", errors="replace")
    platform_config = PLATFORM_CONFIG.read_text(encoding="utf-8", errors="replace")
    input_sdc = INPUT_SDC.read_text(encoding="utf-8", errors="replace")
    resize_tcl = RESIZE_TCL.read_text(encoding="utf-8", errors="replace")
    cts_tcl = CTS_TCL.read_text(encoding="utf-8", errors="replace")
    actual_hashes = {
        "mapped_netlist": sha256(NETLIST),
        "placement_config": sha256(CONFIG),
        "placed_odb": sha256(ODB),
        "placed_sdc": sha256(SDC),
        "run_log": sha256(RUN_LOG),
        "detail_place_log": sha256(DP_LOG),
        "independent_audit_log": sha256(AUDIT_LOG),
        "floorplan_log": sha256(FLOORPLAN_LOG),
        "io_placement_log": sha256(IOP_LOG),
        "sky130hd_platform_config": sha256(PLATFORM_CONFIG),
        "sky130hd_fastroute_tcl": sha256(FASTROUTE_TCL),
        "input_sdc": sha256(INPUT_SDC),
        "orfs_resize_tcl": sha256(RESIZE_TCL),
        "orfs_cts_tcl": sha256(CTS_TCL),
    }
    placement_run_git_sha = kv(run, "WBQ_PLACE_GIT_SHA")
    launch_orfs_sha = kv(run, "WBQ_PLACE_ORFS_SHA")
    current_orfs_sha = subprocess.check_output(
        ["git", "-C", str(ORFS_ROOT), "rev-parse", "HEAD"], text=True
    ).strip()
    current_orfs_dirty = bool(subprocess.check_output(
        ["git", "-C", str(ORFS_ROOT), "status", "--porcelain"], text=True
    ).strip())
    launch_hashes = {
        "mapped_netlist": kv(run, "WBQ_PLACE_NETLIST_SHA256"),
        "placement_config": kv(run, "WBQ_PLACE_CONFIG_SHA256"),
        "input_sdc": git_file_sha256(
            ROOT,
            placement_run_git_sha,
            "flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc",
        ),
    }
    repair_rows = re.findall(
        r"^\s*(?:final|\d+)\s*\|\s*([+-][0-9.]+)%\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$",
        run,
        flags=re.MULTILINE,
    )
    repair = None
    if repair_rows:
        area, resized, buffers, nets, remaining = repair_rows[-1]
        repair = {
            "area_growth_percent": float(area),
            "resized_cells": int(resized),
            "inserted_buffers": int(buffers),
            "nets_repaired": int(nets),
            "remaining_driver_vertices": int(remaining),
        }

    overall_elapsed = one(r"Elapsed \(wall clock\) time .*?: (.+)$", run, last=True)
    overall_rss = one(r"Maximum resident set size \(kbytes\): (\d+)", run, int, last=True)
    violations = one(r"^WBQ_PLACE_AUDIT_VIOLATIONS (\d+)$", audit, int)
    audit_top = one(r"^WBQ_PLACE_AUDIT_TOP (\S+)$", audit)
    audit_hashes_match = (
        kv(audit, "WBQ_PLACE_AUDIT_ODB_SHA256") == actual_hashes["placed_odb"]
        and kv(audit, "WBQ_PLACE_AUDIT_SDC_SHA256") == actual_hashes["placed_sdc"]
    )
    placement_complete = (
        kv(run, "WBQ_PLACE_EXIT_CODE") == "0"
        and "NORMALIZATION_HBM_WBQ_PLACE PASS" in run
        and "Placement Analysis" in dp
    )
    audit_complete = (
        "WBQ_PLACE_AUDIT_PASS" in audit
        and violations == 0
        and audit_top == "logic_die_normalization_hbm_top"
        and audit_hashes_match
    )
    hashes_match = all(launch_hashes[name] == actual_hashes[name] for name in launch_hashes)
    locality_rows = {"BANK": [], "QUAD": []}
    for kind, group, cells, cx, cy, x0, y0, x1, y1 in re.findall(
        r"^WBQ_PLACE_AUDIT_LOCALITY (BANK|QUAD) (\d+) (\d+) "
        r"([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+)$",
        audit,
        flags=re.MULTILINE,
    ):
        locality_rows[kind].append({
            "id": int(group), "cell_count": int(cells),
            "centroid_um": [float(cx), float(cy)],
            "bbox_um": [float(x0), float(y0), float(x1), float(y1)],
        })
    locality_complete = (
        len(locality_rows["BANK"]) == 16
        and len(locality_rows["QUAD"]) == 4
        and all(row["cell_count"] > 0 for rows in locality_rows.values() for row in rows)
    )
    io_pin_count = one(r"Number of I/O\s+(\d+)$", iop, int)
    pin_placement_complete = "Successfully assigned pins to sections." in iop
    signal_min_layer = one(r"^export MIN_ROUTING_LAYER\s*\?=\s*(\S+)", platform_config)
    signal_max_layer = one(r"^export MAX_ROUTING_LAYER\s*\?=\s*(\S+)", platform_config)
    routing_layer_setup_complete = (
        signal_min_layer == "met1"
        and signal_max_layer == "met5"
        and "/platforms/sky130hd/fastroute.tcl" in floorplan
    )
    clock_name = one(r"create_clock\s+-name\s+(\S+)", input_sdc)
    clock_period_ns = one(r"create_clock.*?-period\s+([0-9.]+)", input_sdc, float)
    clock_policy_complete = (
        clock_name == "clk"
        and clock_period_ns == 40.0
        and "repair_design_helper" in resize_tcl
        and "-repair_clock_nets" in cts_tcl
    )
    git_status_paths = subprocess.check_output(
        ["git", "-C", str(ROOT), "status", "--porcelain"], text=True
    ).splitlines()
    gate_checks = {
        "terminal_completion": placement_complete,
        "independent_reopen_and_legality": audit_complete,
        "launch_input_hashes_match_current": hashes_match,
        "repair_completed": repair is not None and repair["remaining_driver_vertices"] == 0,
        "bank_quad_locality_16_4": locality_complete,
        "pin_placement_completed": pin_placement_complete and io_pin_count is not None,
        "routing_layer_setup": routing_layer_setup_complete,
        "clock_policy_evidence": clock_policy_complete,
        "orfs_commit_unchanged_and_clean": (
            launch_orfs_sha == current_orfs_sha and not current_orfs_dirty
        ),
    }

    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "placed",
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq",
        "placement_run_git_sha": placement_run_git_sha,
        "evidence_git_parent_sha": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "evidence_git_dirty": bool(git_status_paths),
        "evidence_git_status_entry_count": len(git_status_paths),
        "host_os": platform.platform(),
        "orfs_sha": launch_orfs_sha,
        "current_orfs_sha": current_orfs_sha,
        "orfs_commit_match": launch_orfs_sha == current_orfs_sha,
        "current_orfs_dirty": current_orfs_dirty,
        "openroad_version": kv(run, "WBQ_PLACE_OPENROAD_VERSION"),
        "start_utc": kv(run, "WBQ_PLACE_START_UTC"),
        "end_utc": kv(run, "WBQ_PLACE_END_UTC"),
        "elapsed_wall": overall_elapsed,
        "maximum_rss_kbytes": overall_rss,
        "die_bbox_um": one(r"Die BBox:\s*\(\s*([^\n]+?)\s*\) um", run),
        "core_bbox_um": one(r"Core BBox:\s*\(\s*([^\n]+?)\s*\) um", run),
        "core_area_um2": one(r"Core area:\s*([0-9.]+) um\^2", run, float),
        "initial_instance_area_um2": one(r"Total instances area:\s*([0-9.]+) um\^2", run, float),
        "effective_utilization": one(r"Effective utilization:\s*([0-9.]+)", run, float),
        "routing_layers": {
            "signal_min": signal_min_layer,
            "signal_max": signal_max_layer,
            "source": "hash-pinned Sky130HD config.mk and fastroute.tcl sourced by floorplan log",
            "setup_complete": routing_layer_setup_complete,
        },
        "pin_placement": {
            "method": "OpenROAD place_pins section assignment",
            "horizontal_layer": one(r"place_pins -hor_layers (\S+)", iop),
            "vertical_layer": one(r"-ver_layers (\S+)", iop),
            "io_count": io_pin_count,
            "successful_section_assignment": pin_placement_complete,
        },
        "bank_quad_locality": {
            "method": "measured placed-cell centroids and bounding boxes from independently reopened ODB",
            "physical_regions_constrained": False,
            "banks": locality_rows["BANK"],
            "quads": locality_rows["QUAD"],
            "complete": locality_complete,
        },
        "clock_high_fanout_policy": {
            "clock_name": clock_name,
            "period_ns": clock_period_ns,
            "placement": "ORFS repair_design runs pre-CTS without an explicit clock-skip override; pre-CTS clock topology is not claimed as final clock distribution",
            "final_flow": "Phase 6 ORFS cts.tcl explicitly uses -repair_clock_nets, followed by post-CTS legality and routing rechecks",
            "evidence_complete": clock_policy_complete,
        },
        "mapped_instance_count": one(r"number instances in verilog is (\d+)", run, int),
        "placed_instance_count": one(r"^WBQ_PLACE_AUDIT_INSTANCE_COUNT (\d+)$", audit, int),
        "placed_net_count": one(r"^WBQ_PLACE_AUDIT_NET_COUNT (\d+)$", audit, int),
        "boundary_terminal_count": one(r"^WBQ_PLACE_AUDIT_BTERM_COUNT (\d+)$", audit, int),
        "legalization_violations": violations,
        "repair": repair,
        "pre_repair_fanout_audit": {
            "scanned_nets": one(r"^WBQ_FANOUT_AUDIT_SCANNED (\d+)$", fanout, int),
            "nets_over_1000_terminals": one(r"^WBQ_FANOUT_AUDIT_OVER_1000 (\d+)$", fanout, int),
            "nets_over_5000_terminals": one(r"^WBQ_FANOUT_AUDIT_OVER_5000 (\d+)$", fanout, int),
            "top_signal_nets": [
                {"rank": int(rank), "terminals": int(terminals), "signal_type": signal_type, "net": net}
                for rank, terminals, signal_type, net in re.findall(
                    r"^WBQ_FANOUT_AUDIT_TOP (\d+) (\d+) (\S+) (.+)$", fanout, flags=re.MULTILINE
                )
                if signal_type == "SIGNAL"
            ],
            "source_checkpoint": "3_3_place_gp.odb",
        },
        "placement_complete": placement_complete,
        "independent_reopen_and_legality_pass": audit_complete,
        "independent_audit_top": audit_top,
        "independent_audit_hashes_match_current": audit_hashes_match,
        "launch_input_hashes_match_current": hashes_match,
        "launch_hashes": launch_hashes,
        "artifacts": {
            name: {"path": str(path), "bytes": path.stat().st_size, "sha256": actual_hashes[name]}
            for name, path in {
                "mapped_netlist": NETLIST,
                "placement_config": CONFIG,
                "placed_odb": ODB,
                "placed_sdc": SDC,
                "run_log": RUN_LOG,
                "detail_place_log": DP_LOG,
                "independent_audit_log": AUDIT_LOG,
                "floorplan_log": FLOORPLAN_LOG,
                "io_placement_log": IOP_LOG,
                "sky130hd_platform_config": PLATFORM_CONFIG,
                "sky130hd_fastroute_tcl": FASTROUTE_TCL,
                "input_sdc": INPUT_SDC,
                "orfs_resize_tcl": RESIZE_TCL,
                "orfs_cts_tcl": CTS_TCL,
            }.items()
        },
        "reproduction_commands": [
            "bash verification/groot_normalization/run_normalization_hbm_wbq_place.sh",
            "bash verification/groot_normalization/run_normalization_hbm_wbq_place_audit.sh",
            "python3 tools/collect_wbq_placement_evidence.py",
        ],
        "historical_comparison": {
            "status": "not_applicable_to_phase3_gate",
            "reason": "Pre-slice placement checkpoints are historical only and cannot prove latest-wbq placement; same-definition congestion comparison is deferred to Phase 4.",
        },
        "next_stage": "CLI-owned Phase 4 reuses this legal ODB for same-definition global-route comparison against historical residual congestion 2,620.",
        "gate_checks": gate_checks,
        "failed_gates": [name for name, passed in gate_checks.items() if not passed],
        "claim_boundary": "Placed Sky130HD research artifact; routing, timing closure, and manufacturing signoff are not established.",
    }
    if FANOUT_LOG.is_file() and FANOUT_LOG.stat().st_size:
        payload["artifacts"]["pre_repair_fanout_audit_log"] = {
            "path": str(FANOUT_LOG),
            "bytes": FANOUT_LOG.stat().st_size,
            "sha256": sha256(FANOUT_LOG),
        }
    payload["gate_pass"] = all(gate_checks.values())

    OUT.mkdir(parents=True, exist_ok=True)
    manifest = OUT / "wbq_placement_manifest.json"
    manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    esc = lambda value: html.escape(str(value))
    verdict = "PASS" if payload["gate_pass"] else "FAIL"
    repair_html = "unavailable" if repair is None else (
        f"{repair['resized_cells']:,} resized, {repair['inserted_buffers']:,} buffers, "
        f"{repair['nets_repaired']:,} nets, {repair['area_growth_percent']:+.1f}% area"
    )
    artifact_rows = "".join(
        f"<tr><td>{esc(name)}</td><td><code>{esc(item['path'])}</code></td>"
        f"<td>{item['bytes']:,}</td><td><code>{esc(item['sha256'])}</code></td></tr>"
        for name, item in payload["artifacts"].items()
    )
    failure_summary = "none" if not payload["failed_gates"] else ", ".join(payload["failed_gates"])
    placement_claim = (
        "공개 Sky130HD에서 독립 재개방·legalization 검사를 통과한 placed 연구 산출물이다."
        if payload["gate_pass"]
        else "Phase 3 gate를 통과하지 못한 불완전 placement 시도이며 placed 성공 산출물로 주장하지 않는다."
    )
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ 배치·legalization 보고서</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}}th{{background:#eef3f8}}.verdict{{padding:16px;background:{'#e7f6ed' if payload['gate_pass'] else '#fff0df'};border-left:6px solid {'#168154' if payload['gate_pass'] else '#b66a00'}}}code{{word-break:break-all}}pre{{white-space:pre-wrap}}</style></head><body>
<h1>Phase 3 — wbq floorplan, repair, placement, legalization</h1>
<div class=\"verdict\"><strong>{verdict}</strong><br>분류: placed<br>실행 Git <code>{esc(payload['placement_run_git_sha'])}</code><br>보고 시각 {esc(payload['captured_at_utc'])}<br>실패 게이트: {esc(failure_summary)}</div>
<h2>게이트</h2><table>
<tr><th>latest wbq input hash</th><td>{esc(hashes_match)}</td></tr>
<tr><th>terminal completion</th><td>{esc(placement_complete)}</td></tr>
<tr><th>독립 ODB 재개방</th><td>{esc(audit_complete)}</td></tr><tr><th>audit top / current ODB·SDC hash</th><td>{esc(audit_top)} / {esc(audit_hashes_match)}</td></tr>
<tr><th>legalization violations</th><td>{esc(violations)}</td></tr></table>
<h2>Routing, pin placement, bank/quad locality</h2><table>
<tr><th>Signal routing layers</th><td>{esc(signal_min_layer)}–{esc(signal_max_layer)}; hash-pinned Sky130HD fastroute setup {esc(routing_layer_setup_complete)}</td></tr>
<tr><th>I/O pin placement</th><td>{esc(io_pin_count)} pins; horizontal {esc(payload['pin_placement']['horizontal_layer'])}, vertical {esc(payload['pin_placement']['vertical_layer'])}; section assignment {esc(pin_placement_complete)}</td></tr>
<tr><th>Measured hierarchy locality</th><td>{len(locality_rows['BANK'])}/16 banks and {len(locality_rows['QUAD'])}/4 quads measured from final ODB; no explicit physical regions constrained</td></tr>
<tr><th>Clock policy</th><td>{esc(clock_name)} {esc(clock_period_ns)} ns; pre-CTS topology는 최종 clock distribution으로 주장하지 않으며 Phase 6에서 <code>-repair_clock_nets</code> CTS 및 post-CTS legality/routing을 재검사한다. Evidence {esc(clock_policy_complete)}</td></tr></table>
<h2>물리·자원 결과</h2><table>
<tr><th>Die BBox</th><td>{esc(payload['die_bbox_um'])} µm</td></tr><tr><th>Core BBox</th><td>{esc(payload['core_bbox_um'])} µm</td></tr>
<tr><th>Core area / utilization</th><td>{payload['core_area_um2']:,.3f} µm² / {payload['effective_utilization']:.3f}</td></tr>
<tr><th>Instances / nets / BTerms</th><td>{payload['placed_instance_count']:,} / {payload['placed_net_count']:,} / {payload['boundary_terminal_count']:,}</td></tr>
<tr><th>Repair</th><td>{esc(repair_html)}</td></tr><tr><th>Wall / peak RSS</th><td>{esc(overall_elapsed)} / {overall_rss / 1024 / 1024:.2f} GiB</td></tr></table>
<h2>Provenance와 입력·출력 해시</h2><table>
<tr><th>Evidence Git / dirty</th><td><code>{esc(payload['evidence_git_parent_sha'])}</code> / {esc(payload['evidence_git_dirty'])} ({payload['evidence_git_status_entry_count']} status entries)</td></tr>
<tr><th>ORFS launch/current</th><td><code>{esc(payload['orfs_sha'])}</code> / <code>{esc(payload['current_orfs_sha'])}</code>; match {esc(payload['orfs_commit_match'])}; dirty {esc(payload['current_orfs_dirty'])}</td></tr>
<tr><th>OpenROAD</th><td>{esc(payload['openroad_version'])}</td></tr>
<tr><th>OS</th><td>{esc(payload['host_os'])}</td></tr></table>
<table><tr><th>Artifact</th><th>Path</th><th>Bytes</th><th>SHA-256</th></tr>{artifact_rows}</table>
<h2>비교 경계·다음 단계</h2>
<p>Historical comparison: {esc(payload['historical_comparison']['reason'])}</p>
<p>Next: {esc(payload['next_stage'])}</p>
<h2>재현 명령</h2><pre>{esc(chr(10).join(payload['reproduction_commands']))}</pre>
<p><strong>Claim boundary:</strong> {esc(placement_claim)} Routing, timing closure, 제조용 DRC/LVS 또는 fabrication readiness를 증명하지 않는다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p>
</body></html>"""
    (OUT / "03_wbq_placement_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_PLACEMENT_EVIDENCE {verdict} violations={violations} odb={actual_hashes['placed_odb']}")
    return 0 if payload["gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
