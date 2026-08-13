#!/usr/bin/env python3
"""Collect and render the Phase-3 wbq placement/legalization evidence."""

from __future__ import annotations

import hashlib
import html
import json
import os
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


def main() -> int:
    required = [RUN_LOG, AUDIT_LOG, NETLIST, CONFIG, ODB, SDC, DP_LOG]
    missing = [str(path) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("missing/non-empty Phase-3 artifacts:\n" + "\n".join(missing))

    run = RUN_LOG.read_text(encoding="utf-8", errors="replace")
    audit = AUDIT_LOG.read_text(encoding="utf-8", errors="replace")
    fanout = FANOUT_LOG.read_text(encoding="utf-8", errors="replace") if FANOUT_LOG.is_file() else ""
    dp = DP_LOG.read_text(encoding="utf-8", errors="replace")
    actual_hashes = {
        "mapped_netlist": sha256(NETLIST),
        "placement_config": sha256(CONFIG),
        "placed_odb": sha256(ODB),
        "placed_sdc": sha256(SDC),
        "run_log": sha256(RUN_LOG),
        "detail_place_log": sha256(DP_LOG),
        "independent_audit_log": sha256(AUDIT_LOG),
    }
    launch_hashes = {
        "mapped_netlist": kv(run, "WBQ_PLACE_NETLIST_SHA256"),
        "placement_config": kv(run, "WBQ_PLACE_CONFIG_SHA256"),
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
    placement_complete = (
        kv(run, "WBQ_PLACE_EXIT_CODE") == "0"
        and "NORMALIZATION_HBM_WBQ_PLACE PASS" in run
        and "Placement Analysis" in dp
    )
    audit_complete = "WBQ_PLACE_AUDIT_PASS" in audit and violations == 0
    hashes_match = all(launch_hashes[name] == actual_hashes[name] for name in launch_hashes)

    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "placed",
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq",
        "placement_run_git_sha": kv(run, "WBQ_PLACE_GIT_SHA"),
        "evidence_git_parent_sha": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "orfs_sha": kv(run, "WBQ_PLACE_ORFS_SHA"),
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
            }.items()
        },
        "reproduction_commands": [
            "bash verification/groot_normalization/run_normalization_hbm_wbq_place.sh",
            "bash verification/groot_normalization/run_normalization_hbm_wbq_place_audit.sh",
            "python3 tools/collect_wbq_placement_evidence.py",
        ],
        "claim_boundary": "Placed Sky130HD research artifact; routing, timing closure, and manufacturing signoff are not established.",
    }
    if FANOUT_LOG.is_file() and FANOUT_LOG.stat().st_size:
        payload["artifacts"]["pre_repair_fanout_audit_log"] = {
            "path": str(FANOUT_LOG),
            "bytes": FANOUT_LOG.stat().st_size,
            "sha256": sha256(FANOUT_LOG),
        }
    payload["gate_pass"] = bool(
        placement_complete
        and audit_complete
        and hashes_match
        and repair is not None
        and repair["remaining_driver_vertices"] == 0
    )

    OUT.mkdir(parents=True, exist_ok=True)
    manifest = OUT / "wbq_placement_manifest.json"
    manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    esc = lambda value: html.escape(str(value))
    verdict = "PASS" if payload["gate_pass"] else "FAIL"
    repair_html = "unavailable" if repair is None else (
        f"{repair['resized_cells']:,} resized, {repair['inserted_buffers']:,} buffers, "
        f"{repair['nets_repaired']:,} nets, {repair['area_growth_percent']:+.1f}% area"
    )
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ 배치·legalization 보고서</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}}th{{background:#eef3f8}}.verdict{{padding:16px;background:{'#e7f6ed' if payload['gate_pass'] else '#fff0df'};border-left:6px solid {'#168154' if payload['gate_pass'] else '#b66a00'}}}code{{word-break:break-all}}pre{{white-space:pre-wrap}}</style></head><body>
<h1>Phase 3 — wbq floorplan, repair, placement, legalization</h1>
<div class=\"verdict\"><strong>{verdict}</strong><br>분류: placed<br>실행 Git <code>{esc(payload['placement_run_git_sha'])}</code></div>
<h2>게이트</h2><table>
<tr><th>latest wbq input hash</th><td>{esc(hashes_match)}</td></tr>
<tr><th>terminal completion</th><td>{esc(placement_complete)}</td></tr>
<tr><th>독립 ODB 재개방</th><td>{esc(audit_complete)}</td></tr>
<tr><th>legalization violations</th><td>{esc(violations)}</td></tr></table>
<h2>물리·자원 결과</h2><table>
<tr><th>Die BBox</th><td>{esc(payload['die_bbox_um'])} µm</td></tr><tr><th>Core BBox</th><td>{esc(payload['core_bbox_um'])} µm</td></tr>
<tr><th>Core area / utilization</th><td>{payload['core_area_um2']:,.3f} µm² / {payload['effective_utilization']:.3f}</td></tr>
<tr><th>Instances / nets / BTerms</th><td>{payload['placed_instance_count']:,} / {payload['placed_net_count']:,} / {payload['boundary_terminal_count']:,}</td></tr>
<tr><th>Repair</th><td>{esc(repair_html)}</td></tr><tr><th>Wall / peak RSS</th><td>{esc(overall_elapsed)} / {overall_rss / 1024 / 1024:.2f} GiB</td></tr></table>
<h2>재현 명령</h2><pre>{esc(chr(10).join(payload['reproduction_commands']))}</pre>
<p><strong>Claim boundary:</strong> 공개 Sky130HD에서 독립 재개방·legalization 검사를 통과한 placed 연구 산출물이다. Routing, timing closure, 제조용 DRC/LVS 또는 fabrication readiness를 증명하지 않는다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p>
</body></html>"""
    (OUT / "03_wbq_placement_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_PLACEMENT_EVIDENCE {verdict} violations={violations} odb={actual_hashes['placed_odb']}")
    return 0 if payload["gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
