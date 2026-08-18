#!/usr/bin/env python3
"""Seal all inexpensive B gates into the authorization manifest for P&R."""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PHYSICAL_VARIANT = os.environ.get("WBQ_VARIANT", "")
if PHYSICAL_VARIANT and not (
    PHYSICAL_VARIANT.startswith("B") and PHYSICAL_VARIANT[1:].isdigit()
    and int(PHYSICAL_VARIANT[1:]) >= 3
):
    raise ValueError(f"unsupported WBQ_VARIANT={PHYSICAL_VARIANT!r}")
NEW_VARIANT = bool(PHYSICAL_VARIANT)
B2 = os.environ.get("WBQ_B2", "0") == "1" or NEW_VARIANT
VARIANT_LOWER = PHYSICAL_VARIANT.lower() if NEW_VARIANT else ""
REPORT = ROOT / (
    f"reports/groot_normalization/quad_local_{VARIANT_LOWER}"
    if NEW_VARIANT
    else "reports/groot_normalization/quad_local_b2"
    if B2
    else "reports/groot_normalization/quad_local_ab"
)
PREFIX = VARIANT_LOWER if NEW_VARIANT else "b2" if B2 else "b"
VARIANT = (
    f"logic_die_normalization_hbm_quad_local_{VARIANT_LOWER}_physical_eco"
    if NEW_VARIANT
    else "logic_die_normalization_hbm_quad_local_b2_top"
    if B2
    else "logic_die_normalization_hbm_quad_local_ab_top"
)

# A PASS token in an old log must never authorize a physical run after the
# quad-local RTL or its contract tests have changed.  The individual artifact
# hashes seal content; this timestamp guard seals provenance/freshness.
EVIDENCE_INPUTS = tuple(sorted((ROOT / "rtl").glob("*.sv"))) + tuple(
    ROOT / "verification/groot_normalization" / filename
    for filename in (
        "mixed_precision_quad_reduction_bitexact_tb.sv",
        "logic_die_normalization_quad_local_ab_random_tb.sv",
        "normalization_writeback_quad_local_reset_tb.sv",
        "logic_die_normalization_pcu_top_tb.sv",
        "normalization_hbm_boundary_integration_tb.sv",
        "groot_logic_die_pcu_trace_tb.sv",
    )
)
LATEST_INPUT_MTIME_NS = max(path.stat().st_mtime_ns for path in EVIDENCE_INPUTS)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def text_gate(name: str, filename: str, token: str, count: int = 1) -> dict:
    path = REPORT / filename
    text = path.read_text(encoding="utf-8", errors="replace")
    actual = text.count(token)
    fresh = path.stat().st_mtime_ns >= LATEST_INPUT_MTIME_NS
    return {
        "id": name,
        "result": "PASS" if actual >= count and "FAIL" not in text and fresh else "FAIL",
        "required_token": token,
        "required_count": count,
        "actual_count": actual,
        "fresh_against_design_inputs": fresh,
        "artifact": str(path.relative_to(ROOT)),
        "sha256": sha(path),
    }


def json_gate(name: str, filename: str, pass_field: str = "overall_result") -> dict:
    path = REPORT / filename
    data = json.loads(path.read_text(encoding="utf-8"))
    fresh = path.stat().st_mtime_ns >= LATEST_INPUT_MTIME_NS
    return {
        "id": name,
        "result": "PASS" if data.get(pass_field) == "PASS" and fresh else "FAIL",
        "fresh_against_design_inputs": fresh,
        "artifact": str(path.relative_to(ROOT)),
        "sha256": sha(path),
    }


def main() -> int:
    accuracy_path = ROOT / (
        f"reports/groot_normalization/results/quad_local_{VARIANT_LOWER}_actual_trace/accuracy_summary.json"
        if NEW_VARIANT
        else "reports/groot_normalization/results/quad_local_b2_actual_trace/accuracy_summary.json"
        if B2
        else "reports/groot_normalization/results/quad_local_ab_actual_trace/accuracy_summary.json"
    )
    accuracy = json.loads(accuracy_path.read_text(encoding="utf-8"))
    accuracy_fresh = accuracy_path.stat().st_mtime_ns >= LATEST_INPUT_MTIME_NS
    gates = [
        text_gate("bit_exact_reduction", "bitexact_reduction.log", "MIXED_PRECISION_QUAD_REDUCTION_BITEXACT_TB PASS"),
        text_gate("randomized_ab_differential", "random_ab_differential.log", "LOGIC_DIE_NORMALIZATION_QUAD_LOCAL_AB_RANDOM_TB PASS"),
        text_gate("writeback_inflight_reset", "writeback_inflight_reset.log", "NORMALIZATION_WRITEBACK_QUAD_LOCAL_RESET_TB PASS"),
        text_gate("pcu_ab_matrix", "pcu_ab_matrix.log", "LOGIC_DIE_NORMALIZATION_PCU_TOP_TB PASS", 10),
        text_gate("boundary_ab_matrix", "boundary_ab_matrix.log", "NORMALIZATION_HBM_BOUNDARY_INTEGRATION_TB PASS", 8),
        json_gate("rtl_locality_reset_audit", f"{PREFIX}_rtl_locality_audit.json"),
        json_gate("mapped_locality_reset_audit", f"{PREFIX}_mapped_locality_audit.json"),
        text_gate("odb_quad_fence_capacity", f"{PREFIX}_floorplan_preflight.log", "WBQ_QUAD_FENCE_CAPACITY PASS"),
    ]
    gates.append(
        {
            "id": "actual_workload_accuracy",
            "result": "PASS" if accuracy.get("overall_result") == "PASS" and accuracy.get("passed_profiles") == 6 and accuracy_fresh else "FAIL",
            "passed_profiles": accuracy.get("passed_profiles"),
            "failed_profiles": accuracy.get("failed_profiles"),
            "fresh_against_design_inputs": accuracy_fresh,
            "artifact": str(accuracy_path.relative_to(ROOT)),
            "sha256": sha(accuracy_path),
        }
    )
    overall = all(gate["result"] == "PASS" for gate in gates)
    payload = {
        "schema_version": 1,
        "variant": VARIANT,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "evidence_input_snapshot": {
            "latest_mtime_ns": LATEST_INPUT_MTIME_NS,
            "files": [str(path.relative_to(ROOT)) for path in EVIDENCE_INPUTS],
        },
        "overall_result": "PASS" if overall else "FAIL",
        "authorizes": (
            [f"{PHYSICAL_VARIANT}_PLACEMENT", f"{PHYSICAL_VARIANT}_SINGLE_GLOBAL_ROUTE"]
            if overall and NEW_VARIANT
            else ["B2_PLACEMENT", "B2_GLOBAL_ROUTE"]
            if overall and B2
            else ["B_PLACEMENT", "B_GLOBAL_ROUTE"]
            if overall
            else []
        ),
        "gates": gates,
    }
    output = REPORT / "cheap_gate_manifest.json"
    output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"WBQ_QUAD_LOCAL_CHEAP_GATE result={payload['overall_result']} gates={len(gates)}")
    return 0 if overall else 1


if __name__ == "__main__":
    raise SystemExit(main())
