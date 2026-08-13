#!/usr/bin/env python3
"""Collect and gate the wbq post-CTS global-route checkpoint."""

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
CTS = OUT / "wbq_phase6_cts_manifest.json"
BASELINE = RAW / "physical_feasibility_metrics.json"
PREFIX = RAW / "logic_die_normalization_hbm_top_wbq_phase6_post_cts"
RUN_LOG = Path(str(PREFIX) + "_route.log")
AUDIT_LOG = Path(str(PREFIX) + "_route_audit.log")
GUIDE = Path(str(PREFIX) + ".route_guide")
CONGESTION = Path(str(PREFIX) + ".congestion.rpt")
SUMMARY = Path(str(PREFIX) + ".congestion.summary")
SOURCES = Path(str(PREFIX) + ".sources.summary")
ODB = Path(str(PREFIX) + "_global_route.odb")
SDC = Path(str(PREFIX) + "_global_route.sdc")


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


def parse_kv(path: Path) -> dict[str, int | float | str]:
    values: dict[str, int | float | str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, raw = line.split("=", 1)
        try:
            values[key] = int(raw)
        except ValueError:
            try:
                values[key] = float(raw)
            except ValueError:
                values[key] = raw
    return values


def main() -> int:
    required = [CTS, BASELINE, RUN_LOG, AUDIT_LOG, GUIDE, CONGESTION, SUMMARY, SOURCES, ODB, SDC]
    missing = [str(path) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("missing/non-empty Phase-6 route artifacts:\n" + "\n".join(missing))

    cts = json.loads(CTS.read_text(encoding="utf-8-sig"))
    baseline = json.loads(BASELINE.read_text(encoding="utf-8-sig"))["v4_distributed_landing_pad_route"]
    run = RUN_LOG.read_text(encoding="utf-8", errors="replace")
    audit = AUDIT_LOG.read_text(encoding="utf-8", errors="replace")
    summary = parse_kv(SUMMARY)
    sources = parse_kv(SOURCES)
    residual_values = re.findall(r"Iterative RRR finished with congestion remaining \((\d+)\)", run)
    residual = int(residual_values[-1]) if residual_values else (
        0 if "WBQ_PHASE6_POST_CTS_ROUTE_PASS" in run else None
    )
    skipped = [
        {"net": net, "terminals": int(terminals)}
        for net, terminals in re.findall(r"Skipping net (\S+) with (\d+) terminals", run)
    ]
    bump_count = one(r"^WBQ_PHASE6_POST_CTS_BUMP_PIN_COUNT (\d+)$", run, int)
    baseline_match = re.match(r"^(\d+) distributed internal met5 20um landing pads$", baseline["pin_model"])
    baseline_bumps = int(baseline_match.group(1)) if baseline_match else None
    entries = int(summary.get("entries", -1))
    overflow_edges = int(summary.get("overflow_edges", -1))
    overflow_tracks = int(summary.get("total_overflow_tracks", -1))
    actual_odb_hash = sha256(ODB)
    actual_sdc_hash = sha256(SDC)

    input_hashes_match = (
        kv(run, "WBQ_PHASE6_POST_CTS_MANIFEST_SHA256") == sha256(CTS)
        and kv(run, "WBQ_PHASE6_POST_CTS_ODB_SHA256") == cts["artifacts"]["cts_odb"]["sha256"]
        and kv(run, "WBQ_PHASE6_POST_CTS_SDC_SHA256") == cts["artifacts"]["cts_sdc"]["sha256"]
    )
    audit_hashes_match = (
        kv(audit, "WBQ_PHASE6_ROUTE_AUDIT_ODB_SHA256") == actual_odb_hash
        and kv(audit, "WBQ_PHASE6_ROUTE_AUDIT_SDC_SHA256") == actual_sdc_hash
    )
    same_definition = all([
        kv(run, "WBQ_PHASE6_POST_CTS_PIN_MODEL") == "DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD",
        kv(run, "WBQ_PHASE6_POST_CTS_SIGNAL_LAYERS") == "met1-met5",
        kv(run, "WBQ_PHASE6_POST_CTS_CLOCK_LAYERS") == "met2-met5",
        kv(run, "WBQ_PHASE6_POST_CTS_CONGESTION_ITERATIONS") == "1",
        kv(run, "WBQ_PHASE6_POST_CTS_GLOBAL_ROUTER") == "CUGR",
        kv(run, "WBQ_PHASE6_POST_CTS_SKIP_LARGE_FANOUT_NETS") == "5000",
        baseline_bumps is not None,
        bump_count == baseline_bumps,
    ])
    violations = one(r"^WBQ_PHASE6_ROUTE_AUDIT_VIOLATIONS (\d+)$", audit, int)
    clock_nets = one(r"^WBQ_PHASE6_ROUTE_AUDIT_CLOCK_NET_COUNT (\d+)$", audit, int)
    has_routes = one(r"^WBQ_PHASE6_ROUTE_AUDIT_HAS_GLOBAL_ROUTES (\d+)$", audit, int)
    clean = (
        kv(run, "WBQ_PHASE6_POST_CTS_EXIT_CODE") == "0"
        and "NORMALIZATION_HBM_WBQ_PHASE6_POST_CTS_ROUTE PASS" in run
        and "WBQ_PHASE6_ROUTE_AUDIT_PASS" in audit
    )
    gate_pass = bool(
        cts.get("gate_pass") is True
        and input_hashes_match
        and audit_hashes_match
        and same_definition
        and clean
        and residual == 0
        and overflow_edges == 0
        and overflow_tracks == 0
        and not skipped
        and violations == 0
        and clock_nets is not None and clock_nets > 0
        and has_routes == 1
    )
    verdict = "PASS_PF4_POST_CTS" if gate_pass else (
        "ROUTED_NOT_CLOSED" if clean and residual is not None else "INVALID_RUN"
    )

    elapsed = one(r"Elapsed \(wall clock\) time .*?: (.+)$", run)
    rss = one(r"Maximum resident set size \(kbytes\): (\d+)", run, int)
    artifact_paths = {
        "route_log": RUN_LOG, "route_audit_log": AUDIT_LOG, "route_guide": GUIDE,
        "congestion_report": CONGESTION, "congestion_summary": SUMMARY,
        "source_summary": SOURCES, "routed_odb": ODB, "routed_sdc": SDC,
    }
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "routed_research_artifact" if clean else "unknown",
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq_phase6_post_cts",
        "verdict": verdict,
        "gate_pass": gate_pass,
        "run_git_sha": kv(run, "WBQ_PHASE6_POST_CTS_GIT_SHA"),
        "evidence_git_parent_sha": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "orfs_sha": kv(run, "WBQ_PHASE6_POST_CTS_ORFS_SHA"),
        "openroad_version": kv(run, "WBQ_PHASE6_POST_CTS_OPENROAD_VERSION"),
        "start_utc": kv(run, "WBQ_PHASE6_POST_CTS_START_UTC"),
        "end_utc": kv(run, "WBQ_PHASE6_POST_CTS_END_UTC"),
        "elapsed_wall": elapsed,
        "maximum_rss_kbytes": rss,
        "same_metric_definition": same_definition,
        "cts_gate_pass": cts.get("gate_pass") is True,
        "cts_input_hashes_match": input_hashes_match,
        "independent_audit_hashes_match": audit_hashes_match,
        "clean_completion_and_reopen": clean,
        "historical_v4": {
            "residual_congestion": int(baseline["remaining_congestion"]),
            "report_entries": int(baseline["report_entries"]),
            "overflow_edges": int(baseline["report_overflow_edges"]),
        },
        "post_cts": {
            "distributed_bump_pin_count": bump_count,
            "residual_congestion": residual,
            "report_entries": entries,
            "overflow_edges": overflow_edges,
            "total_overflow_tracks": overflow_tracks,
            "skipped_nets": skipped,
            "clock_net_count": clock_nets,
            "legalization_violations": violations,
            "source_categories": sources,
        },
        "artifacts": {
            name: {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for name, path in artifact_paths.items()
        },
        "reproduction_commands": [
            "bash verification/groot_normalization/run_normalization_hbm_wbq_phase6_post_cts_route.sh",
            "bash verification/groot_normalization/run_normalization_hbm_wbq_phase6_post_cts_route_audit.sh",
            "python3 tools/collect_wbq_phase6_post_cts_route_evidence.py",
        ],
        "claim_boundary": "Post-CTS global-route research checkpoint; detailed route, timing closure, and manufacturing signoff are not yet established.",
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "wbq_phase6_post_cts_route_manifest.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    esc = lambda value: html.escape(str(value))
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ clock 및 상세배선 보고서</title><style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.verdict{{padding:16px;background:{'#e7f6ed' if gate_pass else '#fdecec'};border-left:6px solid {'#168154' if gate_pass else '#a12626'}}}</style></head><body><h1>Phase 6 — post-CTS global route</h1><div class=\"verdict\"><strong>{esc(verdict)}</strong><br>동일 정의: {esc(same_definition)} / CTS 입력 hash: {esc(input_hashes_match)}</div><h2>Route metrics</h2><table><tr><th>Residual congestion</th><td>{esc(residual)}</td></tr><tr><th>Entries</th><td>{entries:,}</td></tr><tr><th>Overflow edges / tracks</th><td>{overflow_edges:,} / {overflow_tracks:,}</td></tr><tr><th>Skipped nets</th><td>{esc(skipped)}</td></tr><tr><th>Clock nets</th><td>{esc(clock_nets)}</td></tr><tr><th>Legalization violations</th><td>{esc(violations)}</td></tr></table><p>이 결과는 명시적 clock tree를 포함한 global-route 연구 checkpoint다. Detailed route나 제조 signoff를 증명하지 않는다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p></body></html>"""
    (OUT / "06_clock_and_detailed_route_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_PHASE6_POST_CTS_ROUTE_EVIDENCE {verdict} residual={residual} overflow_edges={overflow_edges}")
    return 0 if gate_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
