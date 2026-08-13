#!/usr/bin/env python3
"""Collect terminal detailed-route evidence without claiming manufacturing signoff."""

from __future__ import annotations

import hashlib
import html
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "reports/groot_normalization/physical_feasibility"
OUT = ROOT / "reports/final_integrated_gds_execution"
INPUT_MANIFEST = OUT / "wbq_phase6_post_cts_route_manifest.json"
PREFIX = RAW / "logic_die_normalization_hbm_top_wbq_phase7_detailed_route"
RUN_LOG = Path(str(PREFIX) + ".log")
AUDIT_LOG = Path(str(PREFIX) + "_audit.log")
ODB = Path(str(PREFIX) + ".odb")
SDC = Path(str(PREFIX) + ".sdc")
DEF = Path(str(PREFIX) + ".def")
NETLIST = Path(str(PREFIX) + ".v")
DRC = Path(str(PREFIX) + ".drc.rpt")
ANTENNA = RAW / "logic_die_normalization_hbm_top_wbq_phase7_antenna.rpt"
MAZE = Path(str(PREFIX) + ".maze.log")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def one(pattern: str, text: str, cast=str):
    values = re.findall(pattern, text, flags=re.MULTILINE)
    return cast(values[-1]) if values else None


def kv(text: str, key: str) -> str | None:
    return one(rf"^{re.escape(key)}=(.*)$", text)


def main() -> int:
    required_nonempty = [INPUT_MANIFEST, RUN_LOG, AUDIT_LOG, ODB, SDC, DEF, NETLIST]
    required_files = [DRC, ANTENNA, MAZE]
    missing = [str(path) for path in required_nonempty if not path.is_file() or path.stat().st_size == 0]
    missing += [str(path) for path in required_files if not path.is_file()]
    if missing:
        raise SystemExit("missing Phase-7 detailed-route artifacts:\n" + "\n".join(missing))

    source = json.loads(INPUT_MANIFEST.read_text(encoding="utf-8-sig"))
    run = RUN_LOG.read_text(encoding="utf-8", errors="replace")
    audit = AUDIT_LOG.read_text(encoding="utf-8", errors="replace")
    antenna_text = ANTENNA.read_text(encoding="utf-8", errors="replace")
    final_drc = one(r"Number of violations\s*=\s*(\d+)", run, int)
    antenna_nets = one(r"(?:violating nets|antenna violations?)\D+(\d+)", antenna_text, int)
    antenna_pins = one(r"violating pins\D+(\d+)", antenna_text, int)

    input_hashes_match = (
        kv(run, "WBQ_PHASE7_ROUTE_MANIFEST_SHA256") == sha256(INPUT_MANIFEST)
        and kv(run, "WBQ_PHASE7_INPUT_ODB_SHA256") == source["artifacts"]["routed_odb"]["sha256"]
        and kv(run, "WBQ_PHASE7_INPUT_SDC_SHA256") == source["artifacts"]["routed_sdc"]["sha256"]
    )
    actual_odb_hash = sha256(ODB)
    actual_sdc_hash = sha256(SDC)
    audit_hashes_match = (
        kv(audit, "WBQ_PHASE7_AUDIT_ODB_SHA256") == actual_odb_hash
        and kv(audit, "WBQ_PHASE7_AUDIT_SDC_SHA256") == actual_sdc_hash
    )
    clock_nets = one(r"^WBQ_PHASE7_AUDIT_CLOCK_NET_COUNT (\d+)$", audit, int)
    signal_wires = one(r"^WBQ_PHASE7_AUDIT_SIGNAL_WIRE_COUNT (\d+)$", audit, int)
    clean = (
        kv(run, "WBQ_PHASE7_EXIT_CODE") == "0"
        and "NORMALIZATION_HBM_WBQ_PHASE7_DETAILED_ROUTE PASS" in run
        and "WBQ_PHASE7_AUDIT_PASS" in audit
        and one(r"^WBQ_PHASE7_AUDIT_DESIGN_IS_ROUTED (\d+)$", audit, int) == 1
    )
    policy_match = (
        kv(run, "WBQ_PHASE7_SIGNAL_LAYERS") == "met1-met5"
        and kv(run, "WBQ_PHASE7_CLOCK_LAYERS") == "met2-met5"
        and kv(run, "WBQ_PHASE7_END_ITERATION") == "64"
    )
    gate_pass = bool(
        source.get("gate_pass") is True
        and input_hashes_match and audit_hashes_match and clean and policy_match
        and final_drc is not None
        and clock_nets is not None and clock_nets > 0
        and signal_wires is not None and signal_wires > 0
    )
    verdict = "PASS_RESEARCH_DETAILED_ROUTE" if gate_pass else "INVALID_RUN"
    elapsed = one(r"Elapsed \(wall clock\) time .*?: (.+)$", run)
    rss = one(r"Maximum resident set size \(kbytes\): (\d+)", run, int)
    artifacts = {
        "detailed_odb": ODB, "detailed_sdc": SDC, "detailed_def": DEF,
        "detailed_netlist": NETLIST, "drc_report": DRC, "antenna_report": ANTENNA,
        "maze_log": MAZE, "run_log": RUN_LOG, "independent_audit_log": AUDIT_LOG,
    }
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "routed_research_artifact" if gate_pass else "unknown",
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq_phase7_detailed_route",
        "verdict": verdict,
        "gate_pass": gate_pass,
        "manufacturing_signoff": False,
        "run_git_sha": kv(run, "WBQ_PHASE7_GIT_SHA"),
        "evidence_git_parent_sha": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "orfs_sha": kv(run, "WBQ_PHASE7_ORFS_SHA"),
        "openroad_version": kv(run, "WBQ_PHASE7_OPENROAD_VERSION"),
        "start_utc": kv(run, "WBQ_PHASE7_START_UTC"),
        "end_utc": kv(run, "WBQ_PHASE7_END_UTC"),
        "elapsed_wall": elapsed,
        "maximum_rss_kbytes": rss,
        "terminal_completion": clean,
        "independent_reopen_pass": "WBQ_PHASE7_AUDIT_PASS" in audit,
        "input_hashes_match": input_hashes_match,
        "audit_output_hashes_match": audit_hashes_match,
        "metrics": {
            "detailed_route_end_iteration": 64,
            "final_drc_violations": final_drc,
            "antenna_violating_nets": antenna_nets,
            "antenna_violating_pins": antenna_pins,
            "clock_nets": clock_nets,
            "signal_nets_with_wire": signal_wires,
        },
        "artifacts": {
            name: {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for name, path in artifacts.items()
        },
        "reproduction_commands": [
            "bash verification/groot_normalization/run_normalization_hbm_wbq_phase7_detailed_route.sh",
            "bash verification/groot_normalization/run_normalization_hbm_wbq_phase7_detailed_route_audit.sh",
            "python3 tools/collect_wbq_phase7_detailed_route_evidence.py",
        ],
        "claim_boundary": "Terminal detailed-route research artifact. Residual DRC and antenna results are reported, not waived; no timing, DRC/LVS, IR/EM, tape-out, or fabrication signoff is claimed.",
        "disclaimer": "RESEARCH ARTIFACT — NOT FOR FABRICATION",
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "wbq_phase7_detailed_route_manifest.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    esc = lambda value: html.escape(str(value))
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ 상세배선 보고서</title><style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.verdict{{padding:16px;background:{'#e7f6ed' if gate_pass else '#fdecec'};border-left:6px solid {'#168154' if gate_pass else '#a12626'}}}</style></head><body><h1>Phase 7 — wbq detailed route</h1><div class=\"verdict\"><strong>{esc(verdict)}</strong><br>Terminal completion: {esc(clean)} / independent reopen: {esc(payload['independent_reopen_pass'])}</div><h2>Measured results</h2><table><tr><th>Final DRC violations</th><td>{esc(final_drc)}</td></tr><tr><th>Antenna violating nets / pins</th><td>{esc(antenna_nets)} / {esc(antenna_pins)}</td></tr><tr><th>Clock nets / signal wires</th><td>{esc(clock_nets)} / {esc(signal_wires)}</td></tr><tr><th>Wall / peak RSS</th><td>{esc(elapsed)} / {esc(None if rss is None else f'{rss / 1024 / 1024:.2f} GiB')}</td></tr></table><p>남은 위반은 숨기거나 waiver로 간주하지 않는다. 이 결과는 terminal detailed-route 연구 산출물이며 제조 승인 결과가 아니다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p></body></html>"""
    (OUT / "06_clock_and_detailed_route_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_PHASE7_DETAILED_ROUTE_EVIDENCE {verdict} drc={final_drc} antenna_nets={antenna_nets}")
    return 0 if gate_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
