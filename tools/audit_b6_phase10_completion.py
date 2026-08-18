#!/usr/bin/env python3
"""Fail-closed Phase 10 audit for the complete B6 research-artifact chain."""

from __future__ import annotations

import hashlib
import html
import json
import os
import platform
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from merge_final_rtl_gds import merge


ROOT = Path(__file__).resolve().parents[1]
B6 = ROOT / "reports/groot_normalization/quad_local_b6"
PHASE9_ROOT = Path(
    os.environ.get("WBQ_B6_PHASE9_ROOT", str(ROOT / "output/final_integrated_gds/b6"))
)
EVIDENCE = B6 / "phase10"
PREFLIGHT = EVIDENCE / "b6_phase10_preflight.json"
HASH_MANIFEST = EVIDENCE / "b6_phase6_phase10_artifact_hash_manifest.json"
COMPLETION = EVIDENCE / "b6_phase10_completion_report.json"
MARKDOWN = EVIDENCE / "b6_phase10_completion_report.md"
EVIDENCE_MATRIX = EVIDENCE / "b6_phase10_evidence_matrix.json"
HTML = ROOT / "reports/final_integrated_gds_execution/09_final_completion_report.html"

CHAIN = {
    # Stage A is a common immutable B2-root-cause report written before the
    # B3/B4/B5/B6 variant sequence.  B6 reuses the sealed B5 functional gate
    # because its ECO changes only physical placement recovery.
    "root_cause": ROOT / "reports/groot_normalization/quad_local_b3/b3_cheap_root_cause_analysis.json",
    "eco_decision": B6 / "b6_eco_decision.json",
    "sealed_b5_cheap_gate": ROOT / "reports/groot_normalization/quad_local_b5/cheap_gate_manifest.json",
    "physical_authorization": B6 / "b6_physical_authorization.json",
    "placement": B6 / "physical/b6_placement_execution_report.json",
    "placement_numeric_analysis": B6 / "physical/b6_placement_numeric_analysis.json",
    "targeted_placement_audit": B6 / "physical/b6_targeted_placement_reopen_audit.json",
    "global_route_authorization": B6 / "b6_global_route_authorization.json",
    "global_route": B6 / "physical/b6_global_route_execution_report.json",
    "congestion_analysis": B6 / "b6_residual_congestion_analysis.json",
    "phase6_gate": B6 / "phase6_decision_gate.json",
    "phase6_cts_authorization": B6 / "phase6/b6_phase6_cts_authorization.json",
    "phase6_cts": B6 / "phase6/b6_phase6_cts_execution_report.json",
    "phase6_post_cts_authorization": B6 / "phase6/b6_phase6_post_cts_route_authorization.json",
    "phase6_post_cts": B6 / "phase6/b6_phase6_post_cts_global_route_execution_report.json",
    "phase7_authorization": B6 / "phase7/b6_phase7_detailed_route_authorization.json",
    "phase7_detailed_route": B6 / "phase7/b6_phase7_detailed_route_execution_report.json",
    "phase7_rtl_gds": B6 / "phase7/b6_phase7_rtl_gds_execution_report.json",
    "phase8_overlay": B6 / "phase8/b6_phase8_overlay_execution_report.json",
    "phase9_final_gds": B6 / "phase9/b6_phase9_final_gds_execution_report.json",
}

PRESERVED = {
    "frozen_A": (
        ROOT / "reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb",
        "964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad",
    ),
    "B": (
        ROOT / "reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb",
        "ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235",
    ),
    "B2": (
        ROOT / "reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb",
        "2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d",
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def artifact(path: Path) -> dict:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def verify_recorded_artifacts(doc: dict, key: str) -> tuple[bool, list[dict]]:
    checks = []
    for name, item in doc.get(key, {}).items():
        if not isinstance(item, dict) or "path" not in item or "sha256" not in item:
            continue
        path = Path(item["path"])
        actual = sha256(path) if path.is_file() else None
        checks.append({"name": name, "path": str(path), "expected": item.get("sha256"),
                       "actual": actual, "match": actual is not None and actual == item.get("sha256")})
    return bool(checks) and all(item["match"] for item in checks), checks


def main() -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    for path in (PREFLIGHT, HASH_MANIFEST, COMPLETION, MARKDOWN, EVIDENCE_MATRIX, HTML):
        if path.exists():
            raise FileExistsError(f"refusing to overwrite Phase 10 evidence: {path}")
    if subprocess.run(["pgrep", "-x", "openroad"], capture_output=True).returncode == 0:
        raise RuntimeError("OpenROAD exists before Phase 10 audit")
    for path in CHAIN.values():
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    docs = {name: load(path) for name, path in CHAIN.items()}
    phase9 = docs["phase9_final_gds"]
    if phase9.get("status") != "PASS" or "B6_PHASE10_COMPLETION_AUDIT" not in phase9.get("authorizes", []):
        raise RuntimeError("Phase 9 does not authorize Phase 10")

    generated = datetime.now(timezone.utc).isoformat()
    with PREFLIGHT.open("x", encoding="utf-8") as stream:
        json.dump({
            "schema_version": 1, "phase": 10, "variant": "B6_PHASE10",
            "status": "PASS", "generated_at_utc": generated,
            "phase9_input": artifact(CHAIN["phase9_final_gds"]),
            "openroad_processes_before": [],
            "authorizes": ["B6_PHASE10_COMPLETION_AUDIT_COMPUTE"],
            "next_stage": "B6_PHASE10_COMPLETION_AUDIT_COMPUTE",
        }, stream, indent=2)
        stream.write("\n")

    phase_checks = {
        "sealed_b5_cheap_gate_9_of_9": docs["sealed_b5_cheap_gate"].get("overall_result") == "PASS"
        and len(docs["sealed_b5_cheap_gate"].get("gates", [])) == 9,
        "physical_authorization": docs["physical_authorization"].get("decision") == "PASS",
        "placement": docs["placement"].get("status") == "PASS",
        "placement_numeric_analysis": docs["placement_numeric_analysis"].get("status") == "PASS",
        "targeted_placement_audit": docs["targeted_placement_audit"].get("status") == "PASS"
        and docs["targeted_placement_audit"].get("metrics", {}).get("anchors_verified") == 2
        and docs["targeted_placement_audit"].get("metrics", {}).get("placement_violations") == 0,
        "global_route_authorization": docs["global_route_authorization"].get("decision") == "PASS",
        "single_global_route": docs["global_route"].get("status") == "PASS"
        and docs["global_route"].get("invocation_count") == 1,
        "strict_phase6_gate": docs["phase6_gate"].get("decision") == "PASS"
        and docs["phase6_gate"].get("authorizes") == ["B6_PHASE6_CTS"],
        "phase6_cts_authorization": docs["phase6_cts_authorization"].get("decision") == "PASS",
        "phase6_cts": docs["phase6_cts"].get("status") == "PASS",
        "phase6_post_cts_authorization": docs["phase6_post_cts_authorization"].get("decision") == "PASS",
        "phase6_post_cts": docs["phase6_post_cts"].get("status") == "PASS",
        "phase7_authorization": docs["phase7_authorization"].get("decision") == "PASS",
        "phase7_detailed_route": docs["phase7_detailed_route"].get("status") == "PASS",
        "phase7_rtl_gds": docs["phase7_rtl_gds"].get("status") == "PASS",
        "phase8_overlay": docs["phase8_overlay"].get("status") == "PASS",
        "phase9_final_gds": phase9.get("status") == "PASS",
    }
    congestion = docs["congestion_analysis"].get("totals", {})
    phase_checks["b6_zero_congestion"] = congestion.get("rrr_residual") == 0 and congestion.get("overflow_edges") == 0
    post_metrics = docs["phase6_post_cts"].get("metrics", {})
    phase_checks["post_cts_zero_congestion"] = post_metrics.get("rrr_residual") == 0 and post_metrics.get("overflow_edges") == 0
    detailed_metrics = docs["phase7_detailed_route"].get("metrics", {})
    placement_metrics = docs["placement_numeric_analysis"].get("metrics", {})
    phase_checks["phase7_timing_and_constraints_quantified"] = all(
        isinstance(detailed_metrics.get(name), (int, float))
        for name in (
            "worst_slack_ns", "max_slew_violation_rows",
            "max_capacitance_violation_rows", "max_fanout_violation_rows",
        )
    )

    artifact_checks = {}
    for name, key in (("placement", "outputs"), ("targeted_placement_audit", "outputs"),
                      ("global_route", "outputs"),
                      ("phase6_cts", "artifacts"), ("phase6_post_cts", "artifacts"),
                      ("phase7_detailed_route", "artifacts"), ("phase8_overlay", "artifacts"),
                      ("phase9_final_gds", "artifacts")):
        passed, checks = verify_recorded_artifacts(docs[name], key)
        artifact_checks[name] = {"pass": passed, "checks": checks}
    for name, doc in docs.items():
        if isinstance(doc.get("inputs"), dict):
            passed, checks = verify_recorded_artifacts(doc, "inputs")
            if checks:
                artifact_checks[f"{name}_inputs"] = {"pass": passed, "checks": checks}
    # Phase-7 RTL GDS uses a single named record instead of an artifacts map.
    rtl_gds_path = Path(docs["phase7_rtl_gds"]["gds"]["path"])
    artifact_checks["phase7_rtl_gds"] = {
        "pass": rtl_gds_path.is_file() and sha256(rtl_gds_path) == docs["phase7_rtl_gds"]["gds"]["sha256"],
        "checks": [],
    }

    preservation = {}
    for name, (path, expected) in PRESERVED.items():
        actual = sha256(path)
        preservation[name] = {"path": str(path), "expected_sha256": expected,
                              "actual_sha256": actual, "match": actual == expected}

    recipe = Path(phase9["artifacts"]["recipe"]["path"])
    final_gds = Path(phase9["artifacts"]["final_gds"]["path"])
    original_hash = sha256(final_gds)
    clean_parent = Path("/dev/shm/wbq_b6_phase6_10")
    clean_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="b6_phase10_clean_", dir=clean_parent) as temp_name:
        temp = Path(temp_name)
        recipe_data = load(recipe)
        recipe_data["output"] = {
            **recipe_data["output"], "gds": str(temp / "merged_final_physical.gds"),
            "lyp": str(temp / "merged_final_physical.lyp"),
            "report": str(temp / "merged_final_physical_report.json"),
        }
        clean_recipe = temp / "recipe.json"
        clean_recipe.write_text(json.dumps(recipe_data, indent=2) + "\n", encoding="utf-8")
        clean_report = merge(clean_recipe)
        clean_gds = temp / "merged_final_physical.gds"
        clean_hash = sha256(clean_gds)
        regeneration = {"status": clean_report.get("status"), "original_sha256": original_hash,
                        "regenerated_sha256": clean_hash, "byte_identical": clean_hash == original_hash}

    final_lyp = Path(phase9["artifacts"]["final_lyp"]["path"])
    with tempfile.TemporaryDirectory(prefix="b6_phase10_klayout_", dir=clean_parent) as temp_name:
        readback_png = Path(temp_name) / "independent_readback.png"
        environment = {
            **os.environ,
            "STOB_FINAL_GDS": str(final_gds),
            "STOB_FINAL_LYP": str(final_lyp),
            "STOB_FINAL_PNG": str(readback_png),
        }
        readback_process = subprocess.run(
            ["klayout", "-zz", "-r", str(ROOT / "tools/render_wbq_final_gds.py")],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        independent_klayout = {
            "exit_code": readback_process.returncode,
            "pass_token": "KLAYOUT_WBQ_FINAL_RENDER PASS " in readback_process.stdout,
            "image_nonempty": readback_png.is_file() and readback_png.stat().st_size > 0,
            "stdout": readback_process.stdout[-4000:],
            "stderr": readback_process.stderr[-4000:],
        }

    openroad_candidates = [
        Path(os.environ["OPENROAD_EXE"]) if os.environ.get("OPENROAD_EXE") else None,
        ROOT.parent / "OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad",
        Path(shutil.which("openroad")) if shutil.which("openroad") else None,
    ]
    openroad_exe = next((path for path in openroad_candidates if path and path.is_file()), None)
    openroad_version = subprocess.run(
        [str(openroad_exe), "-version"], capture_output=True, text=True
    ) if openroad_exe else None
    klayout_version = subprocess.run(
        ["klayout", "-b", "-v"], capture_output=True, text=True
    )
    git_revision = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True
    )
    tool_versions = {
        "python": platform.python_version(),
        "openroad": None if openroad_version is None else (openroad_version.stdout + openroad_version.stderr).strip(),
        "openroad_path": None if openroad_exe is None else str(openroad_exe),
        "openroad_version_exit_code": None if openroad_version is None else openroad_version.returncode,
        "klayout": (klayout_version.stdout + klayout_version.stderr).strip(),
        "klayout_version_exit_code": klayout_version.returncode,
        "git_revision": git_revision.stdout.strip(),
        "git_revision_exit_code": git_revision.returncode,
    }
    tool_versions_pass = (
        openroad_version is not None and openroad_version.returncode == 0
        and klayout_version.returncode == 0 and git_revision.returncode == 0
    )

    openroad_after = subprocess.run(["pgrep", "-a", "-x", "openroad"], capture_output=True, text=True)
    openroad_processes = [line for line in openroad_after.stdout.splitlines() if line.strip()]
    all_pass = (all(phase_checks.values()) and all(item["pass"] for item in artifact_checks.values())
                and all(item["match"] for item in preservation.values())
                and regeneration["status"] == "PASS" and regeneration["byte_identical"]
                and independent_klayout["exit_code"] == 0
                and independent_klayout["pass_token"] and independent_klayout["image_nonempty"]
                and tool_versions_pass
                and not openroad_processes)

    evidence_matrix = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B6",
        "phase_gate_evidence": [
            {"name": name, "evidence_class": "measured_or_hash_pinned_gate", "pass": passed}
            for name, passed in phase_checks.items()
        ],
        "artifact_evidence": [
            {"name": name, "evidence_class": "recorded_sha256_recomputed", "pass": value["pass"]}
            for name, value in artifact_checks.items()
        ],
        "claim_boundary": "RESEARCH ARTIFACT — NOT FOR FABRICATION",
        "known_limitations": {
            "manufacturing_signoff": False,
            "timing_signoff": False,
            "foundry_drc_lvs": False,
            "ir_em_signoff": False,
            "overlay_geometry": "illustrative/estimated",
        },
    }
    with EVIDENCE_MATRIX.open("x", encoding="utf-8") as stream:
        json.dump(evidence_matrix, stream, indent=2); stream.write("\n")

    inventory_paths = list(CHAIN.values()) + [PREFLIGHT, EVIDENCE_MATRIX]
    for result in artifact_checks.values():
        for check in result.get("checks", []):
            if check.get("path"):
                inventory_paths.append(Path(check["path"]))
    for name in ("phase6_cts", "phase6_post_cts", "phase7_detailed_route", "phase8_overlay", "phase9_final_gds"):
        for item in docs[name].get("artifacts", {}).values():
            if isinstance(item, dict) and item.get("path"):
                inventory_paths.append(Path(item["path"]))
    inventory_paths.append(rtl_gds_path)
    unique = []
    seen = set()
    for path in inventory_paths:
        resolved = str(path.resolve())
        if resolved not in seen and path.is_file():
            seen.add(resolved); unique.append(path)
    hash_payload = {
        "schema_version": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B6_PHASE6_PHASE10", "artifacts": [artifact(path) for path in unique],
        "preserved_routed_odb": preservation,
    }
    with HASH_MANIFEST.open("x", encoding="utf-8") as stream:
        json.dump(hash_payload, stream, indent=2); stream.write("\n")

    completion = {
        "schema_version": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "phase": 10, "variant": "B6", "status": "PASS" if all_pass else "FAIL",
        "decision": "PHASE10_COMPLETE" if all_pass else "BLOCKED_PHASE10_AUDIT",
        "phase_checks": phase_checks, "artifact_checks": artifact_checks,
        "clean_regeneration": regeneration, "protected_hashes": preservation,
        "independent_klayout_process": independent_klayout,
        "tool_versions": tool_versions,
        "artifact_hash_manifest": artifact(HASH_MANIFEST),
        "evidence_matrix": artifact(EVIDENCE_MATRIX),
        "final_artifact": artifact(final_gds),
        "metrics": {"b6_rrr_residual": congestion.get("rrr_residual"),
                    "b6_overflow_edges": congestion.get("overflow_edges"),
                    "placement_routability_iterations": placement_metrics.get("routability_iterations"),
                    "placement_weighted_congestion_initial": placement_metrics.get("weighted_congestion_initial"),
                    "placement_weighted_congestion_final": placement_metrics.get("weighted_congestion_final"),
                    "placement_total_overflow_initial": placement_metrics.get("total_overflow_initial"),
                    "placement_total_overflow_final": placement_metrics.get("total_overflow_final"),
                    "post_cts_rrr_residual": post_metrics.get("rrr_residual"),
                    "post_cts_overflow_edges": post_metrics.get("overflow_edges"),
                    "final_drc_violations": detailed_metrics.get("final_drc_violations"),
                    "antenna_violating_nets": detailed_metrics.get("antenna_violating_nets"),
                    "worst_slack_ns": detailed_metrics.get("worst_slack_ns"),
                    "total_negative_slack_ns": detailed_metrics.get("total_negative_slack_ns"),
                    "worst_negative_slack_ns": detailed_metrics.get("worst_negative_slack_ns"),
                    "max_slew_violation_rows": detailed_metrics.get("max_slew_violation_rows"),
                    "max_capacitance_violation_rows": detailed_metrics.get("max_capacitance_violation_rows"),
                    "max_fanout_violation_rows": detailed_metrics.get("max_fanout_violation_rows")},
        "openroad_processes_final": openroad_processes,
        "authorizes": [], "next_stage": None,
        "known_limitations": {"manufacturing_signoff": False, "timing_signoff": False,
                              "foundry_drc_lvs": False, "ir_em_signoff": False,
                              "overlay_geometry": "illustrative/estimated",
                              "intermediate_large_artifact_storage": "/dev/shm/wbq_b6_phase6_10",
                              "final_artifact_storage": str(PHASE9_ROOT)},
        "claim_boundary": "RESEARCH ARTIFACT — NOT FOR FABRICATION",
    }
    with COMPLETION.open("x", encoding="utf-8") as stream:
        json.dump(completion, stream, indent=2); stream.write("\n")
    MARKDOWN.write_text(
        "# B6 Phase 10 completion\n\n"
        f"- Status: **{completion['status']}**\n- Decision: **{completion['decision']}**\n"
        f"- Final GDS: `{completion['final_artifact']['path']}`\n"
        f"- SHA-256: `{completion['final_artifact']['sha256']}`\n"
        f"- Clean regeneration byte-identical: `{regeneration['byte_identical']}`\n"
        f"- B6 residual/overflow: `{congestion.get('rrr_residual')}/{congestion.get('overflow_edges')}`\n"
        f"- Post-CTS residual/overflow: `{post_metrics.get('rrr_residual')}/{post_metrics.get('overflow_edges')}`\n"
        "- Boundary: research artifact; not foundry DRC/LVS, timing, IR/EM, tape-out, or fabrication signoff.\n",
        encoding="utf-8",
    )
    HTML.parent.mkdir(parents=True, exist_ok=True)
    metric_rows = "".join(
        f"<tr><th>{html.escape(str(name))}</th><td>{html.escape(str(value))}</td></tr>"
        for name, value in completion["metrics"].items()
    )
    gate_rows = "".join(
        f"<tr><th>{html.escape(name)}</th><td>{'PASS' if passed else 'FAIL'}</td></tr>"
        for name, passed in phase_checks.items()
    )
    HTML.write_text(
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>B6 Phase 10 completion</title>"
        "<style>body{font:15px system-ui;max-width:1100px;margin:40px auto;padding:0 24px;color:#172033}"
        "h1{font-size:32px}table{border-collapse:collapse;width:100%;margin:16px 0 28px}"
        "th,td{border:1px solid #ccd3df;padding:8px;text-align:left}th{background:#f3f6fa}"
        ".boundary{padding:16px;background:#fff3cd;border:1px solid #e5bd45;font-weight:700}</style>"
        "</head><body><h1>B6 Phase 10 completion report</h1>"
        f"<p>Status: <strong>{html.escape(completion['status'])}</strong> · "
        f"Decision: <strong>{html.escape(completion['decision'])}</strong></p>"
        f"<p>Final GDS SHA-256: <code>{html.escape(completion['final_artifact']['sha256'])}</code></p>"
        "<h2>Gate matrix</h2><table>" + gate_rows + "</table>"
        "<h2>Measured metrics</h2><table>" + metric_rows + "</table>"
        "<h2>Known limitations</h2><p>No manufacturing, foundry DRC/LVS, timing, IR/EM, "
        "tape-out, package, or silicon signoff is claimed. Overlay geometry is illustrative/estimated.</p>"
        "<p class='boundary'>RESEARCH ARTIFACT — NOT FOR FABRICATION</p>"
        "</body></html>\n",
        encoding="utf-8",
    )
    completion["final_html_report"] = artifact(HTML)
    COMPLETION.write_text(json.dumps(completion, indent=2) + "\n", encoding="utf-8")
    print(f"WBQ_B6_PHASE10_COMPLETION {completion['status']} gds_sha256={original_hash}")
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
