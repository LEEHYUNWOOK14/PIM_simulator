#!/usr/bin/env python3
"""Generate compact B25 structural-ECO evidence and the Phase 5 HTML report."""

from __future__ import annotations

import hashlib
import html
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B25 = ROOT / "reports/groot_normalization/quad_local_b25"
EXEC = ROOT / "reports/final_integrated_gds_execution"
OUT_JSON = EXEC / "b25_architecture_milestone.json"
OUT_HTML = EXEC / "05_hierarchical_architecture_report.html"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def evidence(path: Path) -> dict:
    return {"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": sha256(path)}


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, text=True, capture_output=True
    ).stdout.strip()


def main() -> int:
    decision_path = B25 / "b25_eco_decision.json"
    cheap_path = B25 / "cheap_gate_manifest.json"
    rtl_audit_path = B25 / "b25_rtl_locality_audit.json"
    mapped_audit_path = B25 / "b25_mapped_locality_audit.json"
    actual_path = ROOT / "reports/groot_normalization/results/quad_local_b25_actual_trace/accuracy_summary.json"
    config_path = ROOT / "flow/designs/sky130hd/normalization_hbm_quad_local_b25/config.mk"
    scheduler_path = ROOT / "rtl/normalization_quad_local_bank_scheduler.sv"
    pcu_path = ROOT / "rtl/logic_die_normalization_quad_local_pcu_top.sv"
    generator_path = Path(__file__).resolve()
    inputs = {
        "eco_decision": decision_path,
        "cheap_gate": cheap_path,
        "rtl_locality_audit": rtl_audit_path,
        "mapped_locality_audit": mapped_audit_path,
        "actual_workload_accuracy": actual_path,
        "physical_config": config_path,
        "scheduler_rtl": scheduler_path,
        "pcu_rtl": pcu_path,
        "report_generator": generator_path,
    }
    if not all(path.is_file() and path.stat().st_size for path in inputs.values()):
        raise FileNotFoundError("one or more B25 report inputs are missing")

    decision = load(decision_path)
    cheap = load(cheap_path)
    rtl_audit = load(rtl_audit_path)
    mapped = load(mapped_audit_path)
    actual = load(actual_path)
    checks = {item["id"]: item for item in mapped["checks"]}
    aggregate = checks["central_completion_is_one_aggregated_descriptor"]["evidence"]
    registered = checks["quad_completion_descriptor_outputs_are_registered"]["evidence"]
    gate_rows = [
        {"id": item["id"], "result": item["result"], "artifact": item.get("artifact")}
        for item in cheap["gates"]
    ]
    passed = (
        decision.get("decision") == "SELECT_B25_AGGREGATED_COMPLETION_DESCRIPTOR_ECO"
        and cheap.get("overall_result") == "PASS"
        and rtl_audit.get("overall_result") == "PASS"
        and mapped.get("overall_result") == "PASS"
        and aggregate.get("tag_bits") == 16
        and aggregate.get("valid_bits") == 1
        and aggregate.get("previous_quad_descriptor_bits") == 68
        and registered.get("output_bits") == registered.get("registered_driver_bits") == 17
        and all(item["result"] == "PASS" for item in gate_rows)
    )
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "milestone": "B25_AGGREGATED_COMPLETION_DESCRIPTOR_STRUCTURAL_ECO",
        "status": "PASS" if passed else "FAIL",
        "git": {
            "branch": git("branch", "--show-current"),
            "head_before_milestone_commit": git("rev-parse", "HEAD"),
            "dirty_during_generation": bool(git("status", "--short")),
        },
        "hypothesis": decision["selected_eco"]["hypothesis"],
        "contract": decision["preserved_contract"],
        "measured_structure": {
            "central_descriptor_bits_before": aggregate["previous_quad_descriptor_bits"],
            "central_descriptor_bits_after": aggregate["tag_bits"] + aggregate["valid_bits"],
            "central_interconnect_bits_removed": aggregate["previous_quad_descriptor_bits"] - aggregate["tag_bits"] - aggregate["valid_bits"],
            "registered_output_bits": registered["registered_driver_bits"],
            "central_16bank_writeback_tag_consumers": mapped["cross_quad_contract"]["central_16bank_writeback_tag_consumers"],
        },
        "gates": gate_rows,
        "actual_workload": actual,
        "inputs": {name: evidence(path) for name, path in inputs.items()},
        "claim_boundary": "synthesized and cheap-gate validated structural ECO; placement and routing remain pending",
        "known_limitations": [
            "No placement or route PASS is claimed by this milestone.",
            "Sky130HD is a public research proxy and not a proprietary HBM logic process.",
            "Final manufacturing DRC/LVS, IR/EM, and tape-out signoff are outside scope.",
        ],
        "next_stage": "B25 legal placement, independent reopen audit, then one authorized global-route invocation",
        "artifact_label": "RESEARCH ARTIFACT — NOT FOR FABRICATION",
    }
    EXEC.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    rows = "\n".join(
        f"<tr><td>{html.escape(item['id'])}</td><td class='{item['result'].lower()}'>{item['result']}</td><td>{html.escape(str(item.get('artifact') or 'embedded audit'))}</td></tr>"
        for item in gate_rows
    )
    hash_rows = "\n".join(
        f"<tr><td>{html.escape(name)}</td><td><code>{html.escape(item['path'])}</code></td><td><code>{item['sha256']}</code></td></tr>"
        for name, item in payload["inputs"].items()
    )
    limitations = "".join(f"<li>{html.escape(value)}</li>" for value in payload["known_limitations"])
    measured = payload["measured_structure"]
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>B25 hierarchical architecture report</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;max-width:1180px;margin:2rem auto;padding:0 1rem;color:#17202a}}table{{border-collapse:collapse;width:100%;margin:1rem 0}}th,td{{border:1px solid #ccd1d1;padding:.45rem;vertical-align:top}}th{{background:#eef3f5}}code{{font-size:.82rem;overflow-wrap:anywhere}}.pass{{color:#087a36;font-weight:700}}.fail{{color:#b42318;font-weight:700}}.banner{{padding:.8rem;background:#fff3cd;border:1px solid #e0b000;font-weight:700}}</style></head>
<body><p class="banner">RESEARCH ARTIFACT — NOT FOR FABRICATION</p>
<h1>Phase 5 — B25 aggregated completion descriptor ECO</h1>
<p><strong>Verdict:</strong> <span class="{payload['status'].lower()}">{payload['status']}</span>. Generated {html.escape(payload['generated_at_utc'])}; branch <code>{html.escape(payload['git']['branch'])}</code>; pre-commit HEAD <code>{payload['git']['head_before_milestone_commit']}</code>.</p>
<h2>Outcome</h2><p>{html.escape(payload['hypothesis'])}</p>
<table><tr><th>Measured item</th><th>Before</th><th>After/result</th></tr>
<tr><td>Central completion descriptor</td><td>{measured['central_descriptor_bits_before']} bits</td><td>{measured['central_descriptor_bits_after']} bits</td></tr>
<tr><td>Central interconnect removed</td><td>—</td><td>{measured['central_interconnect_bits_removed']} bits</td></tr>
<tr><td>Registered descriptor output</td><td>required 17</td><td>{measured['registered_output_bits']} bits</td></tr>
<tr><td>Central 16-bank tag consumers</td><td>required 0</td><td>{measured['central_16bank_writeback_tag_consumers']}</td></tr></table>
<h2>Preserved contract</h2><pre>{html.escape(json.dumps(payload['contract'], indent=2))}</pre>
<h2>Cheap gates</h2><table><tr><th>Gate</th><th>Result</th><th>Evidence</th></tr>{rows}</table>
<h2>Reproduction commands</h2><pre>bash verification/groot_normalization/run_wbq_quad_local_b25_cheap_gates.sh
python3 tools/generate_b25_architecture_report.py</pre>
<h2>Hash-pinned inputs</h2><table><tr><th>Name</th><th>Path</th><th>SHA-256</th></tr>{hash_rows}</table>
<h2>Claim boundary and limitations</h2><p>{html.escape(payload['claim_boundary'])}</p><ul>{limitations}</ul>
<h2>Next gate</h2><p>{html.escape(payload['next_stage'])}</p></body></html>"""
    OUT_HTML.write_text(document, encoding="utf-8")
    print(f"B25_ARCHITECTURE_REPORT {payload['status']} json={OUT_JSON} html={OUT_HTML}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
