#!/usr/bin/env python3
"""Fail-closed Phase 10 audit for the complete B5 research-artifact chain."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from merge_final_rtl_gds import merge


ROOT = Path(__file__).resolve().parents[1]
B5 = ROOT / "reports/groot_normalization/quad_local_b5"
PHASE9_ROOT = Path(os.environ.get("WBQ_B5_PHASE9_ROOT", "/dev/shm/wbq_b5_phase6_10/phase9"))
EVIDENCE = B5 / "phase10"
PREFLIGHT = EVIDENCE / "b5_phase10_preflight.json"
HASH_MANIFEST = EVIDENCE / "b5_phase6_phase10_artifact_hash_manifest.json"
COMPLETION = EVIDENCE / "b5_phase10_completion_report.json"
MARKDOWN = EVIDENCE / "b5_phase10_completion_report.md"

CHAIN = {
    # Stage A is a common immutable B2-root-cause report written before the
    # B3/B4/B5 variant sequence.  B5's own decision records the later diamond
    # legalizer ECO and links that shared analysis lineage.
    "root_cause": ROOT / "reports/groot_normalization/quad_local_b3/b3_cheap_root_cause_analysis.json",
    "eco_decision": B5 / "b5_eco_decision.json",
    "cheap_gate": B5 / "cheap_gate_manifest.json",
    "physical_authorization": B5 / "b5_physical_authorization.json",
    "placement": B5 / "physical/b5_placement_execution_report.json",
    "global_route": B5 / "physical/b5_global_route_execution_report.json",
    "congestion_analysis": B5 / "b5_residual_congestion_analysis.json",
    "phase6_gate": B5 / "phase6_decision_gate.json",
    "phase6_cts": B5 / "phase6/b5_phase6_cts_execution_report.json",
    "phase6_post_cts": B5 / "phase6/b5_phase6_post_cts_global_route_execution_report.json",
    "phase7_detailed_route": B5 / "phase7/b5_phase7_detailed_route_execution_report.json",
    "phase7_rtl_gds": B5 / "phase7/b5_phase7_rtl_gds_execution_report.json",
    "phase8_overlay": B5 / "phase8/b5_phase8_overlay_execution_report.json",
    "phase9_final_gds": B5 / "phase9/b5_phase9_final_gds_execution_report.json",
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
    for path in (PREFLIGHT, HASH_MANIFEST, COMPLETION, MARKDOWN):
        if path.exists():
            raise FileExistsError(f"refusing to overwrite Phase 10 evidence: {path}")
    if subprocess.run(["pgrep", "-x", "openroad"], capture_output=True).returncode == 0:
        raise RuntimeError("OpenROAD exists before Phase 10 audit")
    for path in CHAIN.values():
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    docs = {name: load(path) for name, path in CHAIN.items()}
    phase9 = docs["phase9_final_gds"]
    if phase9.get("status") != "PASS" or "B5_PHASE10_COMPLETION_AUDIT" not in phase9.get("authorizes", []):
        raise RuntimeError("Phase 9 does not authorize Phase 10")

    generated = datetime.now(timezone.utc).isoformat()
    with PREFLIGHT.open("x", encoding="utf-8") as stream:
        json.dump({
            "schema_version": 1, "phase": 10, "variant": "B5_PHASE10",
            "status": "PASS", "generated_at_utc": generated,
            "phase9_input": artifact(CHAIN["phase9_final_gds"]),
            "openroad_processes_before": [],
            "authorizes": ["B5_PHASE10_COMPLETION_AUDIT_COMPUTE"],
            "next_stage": "B5_PHASE10_COMPLETION_AUDIT_COMPUTE",
        }, stream, indent=2)
        stream.write("\n")

    phase_checks = {
        "cheap_gate_9_of_9": docs["cheap_gate"].get("overall_result") == "PASS"
        and len(docs["cheap_gate"].get("gates", [])) == 9,
        "physical_authorization": docs["physical_authorization"].get("decision") == "PASS",
        "placement": docs["placement"].get("status") == "PASS",
        "single_global_route": docs["global_route"].get("status") == "PASS"
        and docs["global_route"].get("invocation_count") == 1,
        "strict_phase6_gate": docs["phase6_gate"].get("decision") == "PASS"
        and docs["phase6_gate"].get("authorizes") == ["B5_PHASE6_CTS"],
        "phase6_cts": docs["phase6_cts"].get("status") == "PASS",
        "phase6_post_cts": docs["phase6_post_cts"].get("status") == "PASS",
        "phase7_detailed_route": docs["phase7_detailed_route"].get("status") == "PASS",
        "phase7_rtl_gds": docs["phase7_rtl_gds"].get("status") == "PASS",
        "phase8_overlay": docs["phase8_overlay"].get("status") == "PASS",
        "phase9_final_gds": phase9.get("status") == "PASS",
    }
    congestion = docs["congestion_analysis"].get("totals", {})
    phase_checks["b5_zero_congestion"] = congestion.get("rrr_residual") == 0 and congestion.get("overflow_edges") == 0
    post_metrics = docs["phase6_post_cts"].get("metrics", {})
    phase_checks["post_cts_zero_congestion"] = post_metrics.get("rrr_residual") == 0 and post_metrics.get("overflow_edges") == 0

    artifact_checks = {}
    for name, key in (("placement", "outputs"), ("global_route", "outputs"),
                      ("phase6_cts", "artifacts"), ("phase6_post_cts", "artifacts"),
                      ("phase7_detailed_route", "artifacts"), ("phase8_overlay", "artifacts"),
                      ("phase9_final_gds", "artifacts")):
        passed, checks = verify_recorded_artifacts(docs[name], key)
        artifact_checks[name] = {"pass": passed, "checks": checks}
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
    clean_parent = Path("/dev/shm/wbq_b5_phase6_10")
    clean_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="b5_phase10_clean_", dir=clean_parent) as temp_name:
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

    openroad_after = subprocess.run(["pgrep", "-a", "-x", "openroad"], capture_output=True, text=True)
    openroad_processes = [line for line in openroad_after.stdout.splitlines() if line.strip()]
    all_pass = (all(phase_checks.values()) and all(item["pass"] for item in artifact_checks.values())
                and all(item["match"] for item in preservation.values())
                and regeneration["status"] == "PASS" and regeneration["byte_identical"]
                and not openroad_processes)

    inventory_paths = list(CHAIN.values()) + [PREFLIGHT]
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
        "variant": "B5_PHASE6_PHASE10", "artifacts": [artifact(path) for path in unique],
        "preserved_routed_odb": preservation,
    }
    with HASH_MANIFEST.open("x", encoding="utf-8") as stream:
        json.dump(hash_payload, stream, indent=2); stream.write("\n")

    completion = {
        "schema_version": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "phase": 10, "variant": "B5", "status": "PASS" if all_pass else "FAIL",
        "decision": "PHASE10_COMPLETE" if all_pass else "BLOCKED_PHASE10_AUDIT",
        "phase_checks": phase_checks, "artifact_checks": artifact_checks,
        "clean_regeneration": regeneration, "protected_hashes": preservation,
        "artifact_hash_manifest": artifact(HASH_MANIFEST),
        "final_artifact": artifact(final_gds),
        "metrics": {"b5_rrr_residual": congestion.get("rrr_residual"),
                    "b5_overflow_edges": congestion.get("overflow_edges"),
                    "post_cts_rrr_residual": post_metrics.get("rrr_residual"),
                    "post_cts_overflow_edges": post_metrics.get("overflow_edges"),
                    "final_drc_violations": docs["phase7_detailed_route"].get("metrics", {}).get("final_drc_violations"),
                    "antenna_violating_nets": docs["phase7_detailed_route"].get("metrics", {}).get("antenna_violating_nets")},
        "openroad_processes_final": openroad_processes,
        "authorizes": [], "next_stage": None,
        "known_limitations": {"manufacturing_signoff": False, "timing_signoff": False,
                              "foundry_drc_lvs": False, "ir_em_signoff": False,
                              "overlay_geometry": "illustrative/estimated",
                              "volatile_large_artifact_storage": str(PHASE9_ROOT)},
        "claim_boundary": "RESEARCH ARTIFACT — NOT FOR FABRICATION",
    }
    with COMPLETION.open("x", encoding="utf-8") as stream:
        json.dump(completion, stream, indent=2); stream.write("\n")
    MARKDOWN.write_text(
        "# B5 Phase 10 completion\n\n"
        f"- Status: **{completion['status']}**\n- Decision: **{completion['decision']}**\n"
        f"- Final GDS: `{completion['final_artifact']['path']}`\n"
        f"- SHA-256: `{completion['final_artifact']['sha256']}`\n"
        f"- Clean regeneration byte-identical: `{regeneration['byte_identical']}`\n"
        f"- B5 residual/overflow: `{congestion.get('rrr_residual')}/{congestion.get('overflow_edges')}`\n"
        f"- Post-CTS residual/overflow: `{post_metrics.get('rrr_residual')}/{post_metrics.get('overflow_edges')}`\n"
        "- Boundary: research artifact; not foundry DRC/LVS, timing, IR/EM, tape-out, or fabrication signoff.\n",
        encoding="utf-8",
    )
    print(f"WBQ_B5_PHASE10_COMPLETION {completion['status']} gds_sha256={original_hash}")
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
