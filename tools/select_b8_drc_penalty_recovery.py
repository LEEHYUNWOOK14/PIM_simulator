#!/usr/bin/env python3
"""Seal B7's legality failure and select the one-variable B8 DRC recovery."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B7 = ROOT / "reports/groot_normalization/quad_local_b7"
B8 = ROOT / "reports/groot_normalization/quad_local_b8"
OPENROAD_DPL = Path(
    "/home/forstobpim/OpenROAD-flow-scripts/tools/OpenROAD/src/dpl/src/NegotiationLegalizerPass.cpp"
)
OFFENDERS = (
    "u_b2_implementation/u_quad_local_adapter/wire440455",
    "u_b2_implementation/u_quad_local_adapter/wire440867",
    "u_b2_implementation/u_quad_local_adapter/wire440876",
    "u_b2_implementation/u_quad_local_adapter/wire441097",
    "u_b2_implementation/u_quad_local_adapter/wire441921",
    "u_b2_implementation/u_quad_local_adapter/wire441940",
    "u_b2_implementation/u_quad_local_adapter/wire441994",
)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest_path = B7 / "physical/b7_placement_execution_report.json"
    log_path = B7 / "physical/b7_place.log"
    tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b7_phi_place.tcl"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    tcl = tcl_path.read_text(encoding="utf-8")
    source = OPENROAD_DPL.read_text(encoding="utf-8")

    if not (
        manifest.get("status") == "FAIL"
        and manifest.get("exit_code") == 1
        and manifest.get("global_route_invocations") == 0
        and manifest.get("audit_exit_code") == 1
        and manifest.get("protected_artifacts_preserved") is True
        and not manifest.get("authorizes")
    ):
        raise RuntimeError("B7 is not a sealed, protected pre-route failure")
    rudy = manifest.get("checkpoints", {}).get("post_rudy", {})
    rudy_path = Path(rudy.get("path", ""))
    if not rudy_path.is_file() or sha(rudy_path) != rudy.get("sha256"):
        raise RuntimeError("B7 sealed RUDY checkpoint is missing or changed")
    required_log = (
        "WBQ_B7_RUDY_GLOBAL_PLACEMENT PASS",
        "[WARNING DPL-0701] NegotiationLegalizer did not fully converge. Violations remain: 18",
        "[WARNING DPL-0005] Overlap check failed (7).",
        "[WARNING DPL-0011] Padding check failed (7).",
        "[ERROR DPL-0033] detailed placement checks failed during check placement.",
        "WBQ_B7_PLACE_EXIT_CODE=1",
        "WBQ_B7_PLACE_AUDIT_EXIT_CODE=1",
    )
    if not all(token in log for token in required_log) or not all(name in log for name in OFFENDERS):
        raise RuntimeError("B7 detailed-placement failure evidence is incomplete")
    if "GPL-0307" in log:
        raise RuntimeError("B7 unexpectedly retained the GPL-0307 failure")
    if "-site_search_window 100 -row_search_window 20 -drc_penalty 20" not in tcl:
        raise RuntimeError("B7 detailed-placement baseline is not sealed")
    if not all(
        token in source
        for token in (
            "const double drc_penalty = drc_penalty_ * (1.0 + iter);",
            "cost += drc_penalty * drcCount;",
            "clean positions are strongly preferred",
        )
    ):
        raise RuntimeError("installed OpenROAD source does not confirm DRC penalty behavior")

    B8.mkdir(parents=True, exist_ok=True)
    output = B8 / "b8_eco_decision.json"
    markdown = B8 / "b8_eco_decision.md"
    if output.exists() or markdown.exists():
        raise FileExistsError("refusing to overwrite B8 decision")

    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B8",
        "decision": "SELECT_B8_HIGHER_DRC_PENALTY_ECO",
        "status": "SELECTED_PENDING_SMOKE_AND_AUTHORIZATION",
        "failure_classification": {
            "runner_result": "tool_error",
            "automatic_recovery_class": "design_legality_failure",
            "subtype": "seven_movable_buffers_overlap_fixed_tapcells",
            "not_a_stall": True,
            "resource_exhaustion": False,
            "global_placement_passed": True,
        },
        "root_cause": {
            "stage": "B7 negotiation detailed placement",
            "remaining_negotiation_violations": 18,
            "check_placement_overlaps": 7,
            "check_placement_padding_violations": 7,
            "offending_movable_instances": list(OFFENDERS),
            "observed_exit_code": 1,
            "global_route_invocations": 0,
        },
        "selected_eco": {
            "single_independent_variable": "detailed_placement.drc_penalty",
            "before": 20,
            "after": 100,
            "input_checkpoint": "sealed B7 post-RUDY ODB",
            "reason": "the installed legalizer multiplies this coefficient by each candidate's DRC count; a higher value directly discourages the observed fixed-tap overlaps",
        },
        "unchanged_contract": {
            "rtl": "byte-identical",
            "mapped_netlist": "byte-identical",
            "sdc": "byte-identical",
            "fence_geometry": "byte-identical in sealed B7 RUDY ODB",
            "global_placement_result": "byte-identical sealed B7 RUDY ODB",
            "locked_anchor_targets": 2,
            "max_displacement_um": [1000, 1000],
            "site_search_window": 100,
            "row_search_window": 20,
            "full_design_diamond": False,
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
        },
        "functional_evidence": {
            "policy": "reuse sealed B5 cheap 9/9 because B8 changes only one physical legalizer coefficient",
            "fresh_smoke_required": True,
            "fresh_physical_authorization_required": True,
        },
        "inputs": {
            "b7_placement_report": {"path": str(manifest_path), "sha256": sha(manifest_path)},
            "b7_placement_log": {"path": str(log_path), "sha256": sha(log_path)},
            "b7_placement_tcl": {"path": str(tcl_path), "sha256": sha(tcl_path)},
            "b7_rudy_odb": {"path": str(rudy_path), "sha256": sha(rudy_path)},
            "openroad_dpl_source": {"path": str(OPENROAD_DPL), "sha256": sha(OPENROAD_DPL)},
        },
        "authorizes": [],
        "next_stage": "B8_SMOKE",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown.write_text(
        "\n".join(
            [
                "# B8 higher-DRC-penalty recovery",
                "",
                f"Generated: `{payload['generated_at_utc']}`",
                "",
                "B7 is sealed as a pre-route placement-legality failure. Its global placement passed and its immutable post-RUDY checkpoint is retained, but seven movable buffers overlap fixed tapcells after the negotiation legalizer.",
                "",
                "B8 reopens that exact B7 RUDY checkpoint and changes one independent variable: `detailed_placement -drc_penalty` from `20` to `100`. Max displacement, search windows, fences, anchors, SDC, netlist, RTL, and downstream route policy remain unchanged. Full-design diamond legalization remains forbidden.",
                "",
                "A fresh input-reopen/checkpoint smoke and hash-pinned physical authorization are required before compute.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"B8_ECO_DECISION SELECTED output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
