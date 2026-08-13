#!/usr/bin/env python3
"""Collect the wbq V4-definition global-route comparison and HTML evidence."""

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
BASELINE = RAW / "physical_feasibility_metrics.json"
PLACE_MANIFEST = OUT / "wbq_placement_manifest.json"
PREFIX = RAW / "logic_die_normalization_hbm_top_wbq_v4_control"
ROUTE_LOG = Path(str(PREFIX) + "_route.log")
CONGESTION = Path(str(PREFIX) + ".congestion.rpt")
SUMMARY = Path(str(PREFIX) + ".congestion.summary")
SOURCES = Path(str(PREFIX) + ".sources.summary")
GUIDE = Path(str(PREFIX) + ".route_guide")
ODB = Path(str(PREFIX) + "_global_route.odb")
SDC = Path(str(PREFIX) + "_global_route.sdc")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def log_value(text: str, key: str) -> str | None:
    values = re.findall(rf"^{re.escape(key)}=(.*)$", text, flags=re.MULTILINE)
    return values[-1] if values else None


def main() -> int:
    required = [BASELINE, PLACE_MANIFEST, ROUTE_LOG, CONGESTION, SUMMARY, SOURCES, GUIDE, ODB, SDC]
    missing = [str(path) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("missing/non-empty Phase-4 artifacts:\n" + "\n".join(missing))

    baseline_all = json.loads(BASELINE.read_text(encoding="utf-8"))
    baseline = baseline_all["v4_distributed_landing_pad_route"]
    placement = json.loads(PLACE_MANIFEST.read_text(encoding="utf-8"))
    log = ROUTE_LOG.read_text(encoding="utf-8", errors="replace")
    summary = parse_kv(SUMMARY)
    sources = parse_kv(SOURCES)
    residuals = re.findall(r"Iterative RRR finished with congestion remaining \((\d+)\)", log)
    residual = int(residuals[-1]) if residuals else (0 if "WBQ_V4_CONTROL_ROUTE_PASS" in log else None)
    baseline_bump_match = re.search(r"^(\d+) distributed internal met5 20um landing pads$", baseline["pin_model"])
    baseline_bump_count = int(baseline_bump_match.group(1)) if baseline_bump_match else None
    current_bump_count_match = re.findall(r"^WBQ_V4_CONTROL_BUMP_PIN_COUNT (\d+)$", log, flags=re.MULTILINE)
    current_bump_count = int(current_bump_count_match[-1]) if current_bump_count_match else None
    skipped = [
        {"net": net, "terminals": int(terminals), "allowlisted": net == "clk_i"}
        for net, terminals in re.findall(r"Skipping net (\S+) with (\d+) terminals", log)
    ]
    clean = log_value(log, "WBQ_ROUTE_EXIT_CODE") == "0" and "NORMALIZATION_HBM_WBQ_V4_CONTROL_ROUTE PASS" in log
    same_definition = all(
        [
            log_value(log, "WBQ_ROUTE_PIN_MODEL") == "DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD",
            log_value(log, "WBQ_ROUTE_SIGNAL_LAYERS") == "met1-met5",
            log_value(log, "WBQ_ROUTE_CLOCK_LAYERS") == "met2-met5",
            log_value(log, "WBQ_ROUTE_CONGESTION_ITERATIONS") == "1",
            log_value(log, "WBQ_ROUTE_GLOBAL_ROUTER") == "CUGR",
            log_value(log, "WBQ_ROUTE_SKIP_LARGE_FANOUT_NETS") == "5000",
            baseline_bump_count is not None,
            current_bump_count == baseline_bump_count,
        ]
    )
    place_odb_sha = placement["artifacts"]["placed_odb"]["sha256"]
    place_sdc_sha = placement["artifacts"]["placed_sdc"]["sha256"]
    input_hashes_match = (
        log_value(log, "WBQ_ROUTE_PLACE_ODB_SHA256") == place_odb_sha
        and log_value(log, "WBQ_ROUTE_PLACE_SDC_SHA256") == place_sdc_sha
    )
    entries = int(summary.get("entries", -1))
    overflow_edges = int(summary.get("overflow_edges", -1))
    total_overflow_tracks = int(summary.get("total_overflow_tracks", -1))
    all_skips_allowed = all(item["allowlisted"] for item in skipped)

    if not clean or not same_definition or not input_hashes_match or residual is None:
        verdict = "INVALID_RUN"
    elif residual == 0 and overflow_edges == 0 and all_skips_allowed:
        verdict = "PASS_PF4"
    elif 0 <= residual < int(baseline["remaining_congestion"]):
        verdict = "IMPROVED_NOT_CLOSED"
    else:
        verdict = "NO_IMPROVEMENT"

    elapsed = re.findall(r"Elapsed \(wall clock\) time .*?: (.+)$", log, flags=re.MULTILINE)
    rss = re.findall(r"Maximum resident set size \(kbytes\): (\d+)", log)
    artifacts = {
        "route_log": ROUTE_LOG,
        "route_guide": GUIDE,
        "congestion_report": CONGESTION,
        "routed_odb": ODB,
        "routed_sdc": SDC,
    }
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "routed_research_artifact" if clean else "unknown",
        "git_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq_v4_control",
        "verdict": verdict,
        "same_metric_definition": same_definition,
        "placement_input_hashes_match": input_hashes_match,
        "clean_completion": clean,
        "historical_v4": {
            "distributed_bump_pin_count": baseline_bump_count,
            "residual_congestion": int(baseline["remaining_congestion"]),
            "report_entries": int(baseline["report_entries"]),
            "overflow_edges": int(baseline["report_overflow_edges"]),
            "total_overflow_tracks": int(baseline["report_total_overflow_tracks"]),
        },
        "current_wbq": {
            "distributed_bump_pin_count": current_bump_count,
            "residual_congestion": residual,
            "report_entries": entries,
            "overflow_edges": overflow_edges,
            "total_overflow_tracks": total_overflow_tracks,
            "max_congestion": summary.get("max_congestion"),
            "max_capacity": summary.get("max_capacity"),
            "max_usage": summary.get("max_usage"),
            "skipped_nets": skipped,
            "all_skipped_nets_allowlisted": all_skips_allowed,
            "source_categories": sources,
        },
        "delta_vs_v4": {
            "residual": None if residual is None else residual - int(baseline["remaining_congestion"]),
            "report_entries": entries - int(baseline["report_entries"]),
            "overflow_edges": overflow_edges - int(baseline["report_overflow_edges"]),
        },
        "elapsed_wall": elapsed[-1] if elapsed else None,
        "maximum_rss_kbytes": int(rss[-1]) if rss else None,
        "artifacts": {
            name: {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for name, path in artifacts.items()
        },
        "claim_boundary": "Same-definition CuGR research control; skipped pre-CTS clock and remaining congestion are explicitly reported, and this is not detailed-route or manufacturing signoff.",
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "wbq_global_route_manifest.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    esc = lambda value: html.escape(str(value))
    color = "#168154" if verdict == "PASS_PF4" else ("#b66a00" if verdict == "IMPROVED_NOT_CLOSED" else "#a12626")
    background = "#e7f6ed" if verdict == "PASS_PF4" else ("#fff0df" if verdict == "IMPROVED_NOT_CLOSED" else "#fdecec")
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ global route 비교</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:right}}th:first-child,td:first-child{{text-align:left}}.verdict{{padding:16px;background:{background};border-left:6px solid {color}}}code{{word-break:break-all}}</style></head><body>
<h1>Phase 4 — wbq global route와 historical V4 비교</h1><div class=\"verdict\"><strong>{esc(verdict)}</strong><br>동일 metric 정의: {esc(same_definition)} / 입력 hash 일치: {esc(input_hashes_match)}</div>
<h2>동일 정의 정량 비교</h2><table><tr><th>Metric</th><th>Historical V4</th><th>Current wbq</th><th>Delta</th></tr>
<tr><td>Distributed met5 landing pads</td><td>{baseline_bump_count}</td><td>{current_bump_count if current_bump_count is not None else 'unknown'}</td><td>{esc(None if current_bump_count is None or baseline_bump_count is None else current_bump_count - baseline_bump_count)}</td></tr>
<tr><td>CuGR residual congestion</td><td>{payload['historical_v4']['residual_congestion']:,}</td><td>{residual if residual is not None else 'unknown'}</td><td>{esc(payload['delta_vs_v4']['residual'])}</td></tr>
<tr><td>Detailed report entries</td><td>{payload['historical_v4']['report_entries']:,}</td><td>{entries:,}</td><td>{payload['delta_vs_v4']['report_entries']:+,}</td></tr>
<tr><td>Overflow edges</td><td>{payload['historical_v4']['overflow_edges']:,}</td><td>{overflow_edges:,}</td><td>{payload['delta_vs_v4']['overflow_edges']:+,}</td></tr></table>
<h2>실행 경계</h2><p>Skipped nets: <code>{esc(skipped)}</code>. 이 결과는 동일 조건의 CuGR global-route 연구 비교다. Detailed-route, timing closure, 제조 signoff를 증명하지 않는다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p>
</body></html>"""
    (OUT / "04_wbq_global_route_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_GLOBAL_ROUTE_EVIDENCE {verdict} residual={residual} entries={entries} overflow_edges={overflow_edges}")
    return 0 if verdict in {"PASS_PF4", "IMPROVED_NOT_CLOSED", "NO_IMPROVEMENT"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
