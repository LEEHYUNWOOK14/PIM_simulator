#!/usr/bin/env python3
"""Summarize the sealed B16-B24 single-shot route recovery sequence."""

from __future__ import annotations

import hashlib
import html
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXEC = ROOT / "reports/final_integrated_gds_execution"
OUT_JSON = EXEC / "b16_b24_route_recovery_summary.json"
OUT_HTML = EXEC / "04_wbq_global_route_report.html"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def item(path: Path) -> dict:
    return {"path": str(path.relative_to(ROOT)), "sha256": sha256(path), "bytes": path.stat().st_size}


def main() -> int:
    variants = []
    inputs: dict[str, dict] = {}
    for number in range(16, 25):
        name = f"B{number}"
        report = ROOT / f"reports/groot_normalization/quad_local_b{number}"
        decision_path = report / f"b{number}_eco_decision.json"
        manifest_path = report / f"physical/b{number}_global_route_execution_report.json"
        analysis_path = report / f"b{number}_residual_congestion_analysis.json"
        gate_path = report / "phase6_decision_gate.json"
        decision = load(decision_path)
        manifest = load(manifest_path)
        analysis = load(analysis_path) if analysis_path.is_file() else None
        gate = load(gate_path) if gate_path.is_file() else None
        totals = (analysis or {}).get("totals", {})
        comparison_valid = manifest.get("status") == "PASS" and analysis is not None and number != 23
        variant = {
            "variant": name,
            "selected_policy": decision.get("decision"),
            "route_status": manifest.get("status"),
            "failure_class": manifest.get("failure_class"),
            "invocation_count": manifest.get("invocation_count"),
            "cugr_congestion_iterations": manifest.get("cugr_congestion_iterations"),
            "residual": totals.get("rrr_residual"),
            "overflow_edges": totals.get("overflow_edges"),
            "overflow_tracks": totals.get("overflow_tracks"),
            "strict_gate": (gate or {}).get("decision"),
            "comparison_valid": comparison_valid,
            "comparison_exclusion": "B23 changed both x and y origin; see integrity audit" if number == 23 else None,
        }
        variants.append(variant)
        inputs[f"{name}_decision"] = item(decision_path)
        inputs[f"{name}_route_manifest"] = item(manifest_path)
        if analysis_path.is_file():
            inputs[f"{name}_analysis"] = item(analysis_path)
        if gate_path.is_file():
            inputs[f"{name}_strict_gate"] = item(gate_path)
    valid = [entry for entry in variants if entry["comparison_valid"]]
    best = min(valid, key=lambda entry: (entry["residual"], entry["overflow_edges"]))
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "sealed B16-B24 one-variable pin-grid recovery sequence",
        "status": "BLOCKED_RESIDUAL_CONGESTION",
        "variants": variants,
        "best_valid_variant": best,
        "conclusion": "The best valid pin-grid result remains nonzero; router geometry iteration is sealed and B25 moves to an evidence-based RTL structural ECO.",
        "inputs": inputs,
        "next_stage": "B25 aggregated completion descriptor structural ECO",
        "artifact_label": "RESEARCH ARTIFACT — NOT FOR FABRICATION",
    }
    EXEC.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    rows = []
    for entry in variants:
        validity = "VALID" if entry["comparison_valid"] else ("INVALID" if entry["comparison_exclusion"] else "FAILED")
        rows.append(
            "<tr>"
            f"<td>{entry['variant']}</td><td>{html.escape(str(entry['selected_policy']))}</td>"
            f"<td>{entry['route_status']}</td><td>{entry['residual'] if entry['residual'] is not None else '—'}</td>"
            f"<td>{entry['overflow_edges'] if entry['overflow_edges'] is not None else '—'}</td>"
            f"<td>{entry['overflow_tracks'] if entry['overflow_tracks'] is not None else '—'}</td>"
            f"<td>{html.escape(str(entry['strict_gate'] or entry['failure_class'] or '—'))}</td><td>{validity}</td></tr>"
        )
    document = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>WBQ B16-B24 route recovery</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#17202a}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #ccd1d1;padding:.45rem;text-align:right}}th:nth-child(-n+3),td:nth-child(-n+3){{text-align:left}}th{{background:#eef3f5}}.blocked{{padding:.8rem;background:#fff0df;border-left:6px solid #b66a00}}code{{overflow-wrap:anywhere}}</style></head><body>
<p><strong>RESEARCH ARTIFACT — NOT FOR FABRICATION</strong></p><h1>Phase 4/5 — B16 through B24 sealed route recovery</h1>
<div class="blocked"><strong>BLOCKED_RESIDUAL_CONGESTION</strong>. Best valid result: {best['variant']}, residual {best['residual']}, overflow edges {best['overflow_edges']}, overflow tracks {best['overflow_tracks']}.</div>
<p>Every listed route attempt has invocation_count=1 and CuGR congestion iterations=1. B23 is excluded from A/B comparison because its implementation changed both pin-grid origins.</p>
<table><tr><th>Variant</th><th>Selected policy</th><th>Route</th><th>Residual</th><th>Overflow edges</th><th>Overflow tracks</th><th>Gate/failure</th><th>Comparison</th></tr>{''.join(rows)}</table>
<h2>Decision</h2><p>{html.escape(payload['conclusion'])}</p><p>Next: {html.escape(payload['next_stage'])}.</p>
<h2>Reproduction</h2><pre>python3 tools/generate_b16_b24_route_report.py</pre>
<p>Machine-readable input hashes are in <code>reports/final_integrated_gds_execution/b16_b24_route_recovery_summary.json</code>.</p></body></html>"""
    OUT_HTML.write_text(document, encoding="utf-8")
    print(f"B16_B24_ROUTE_REPORT PASS best={best['variant']} residual={best['residual']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
