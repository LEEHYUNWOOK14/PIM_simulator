#!/usr/bin/env python3
"""Seal B6's GPL-0307 failure and select the one-variable B7 recovery."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B6 = ROOT / "reports/groot_normalization/quad_local_b6"
B7 = ROOT / "reports/groot_normalization/quad_local_b7"
OPENROAD_GPL = Path(
    "/home/forstobpim/OpenROAD-flow-scripts/tools/OpenROAD/src/gpl/src/nesterovPlace.cpp"
)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest_path = B6 / "physical/b6_placement_execution_report.json"
    log_path = B6 / "physical/b6_place.log"
    tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b6_targeted_place.tcl"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    tcl = tcl_path.read_text(encoding="utf-8")
    source = OPENROAD_GPL.read_text(encoding="utf-8")

    if not (
        manifest.get("status") == "FAIL"
        and manifest.get("exit_code") == 1
        and manifest.get("global_route_invocations") == 0
        and manifest.get("audit_invocation_count") == 0
        and manifest.get("protected_artifacts_preserved") is True
        and not manifest.get("authorizes")
    ):
        raise RuntimeError("B6 is not a sealed, protected pre-route failure")
    required_log = (
        "[ERROR GPL-0307] RePlAce divergence detected",
        "Consider re-running with a smaller max_phi_cof value.",
        "WBQ_B6_PLACE_EXIT_CODE=1",
        "WBQ_B6_PLACE_AUDIT_INVOCATION_COUNT=0",
    )
    if not all(token in log for token in required_log):
        raise RuntimeError("B6 GPL-0307 diagnosis evidence is incomplete")
    if "-min_phi_coef 0.95 -max_phi_coef 1.05" not in tcl:
        raise RuntimeError("B6 phi baseline is not the sealed 0.95/1.05 policy")
    if not all(
        token in source
        for token in (
            "RePlAce divergence detected:",
            "Consider re-running with a smaller max_phi_cof value.",
            "divergeCode_ = 307;",
        )
    ):
        raise RuntimeError("installed OpenROAD source does not confirm GPL-0307 recovery")

    B7.mkdir(parents=True, exist_ok=True)
    output = B7 / "b7_eco_decision.json"
    markdown = B7 / "b7_eco_decision.md"
    if output.exists() or markdown.exists():
        raise FileExistsError("refusing to overwrite B7 decision")

    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B7",
        "decision": "SELECT_B7_LOWER_MAX_PHI_ECO",
        "status": "SELECTED_PENDING_SMOKE_AND_AUTHORIZATION",
        "failure_classification": {
            "runner_result": "tool_error",
            "automatic_recovery_class": "tool_bug",
            "subtype": "GPL-0307 optimizer_numerical_divergence",
            "not_a_stall": True,
            "resource_exhaustion": False,
            "placement_legality_reached": False,
        },
        "root_cause": {
            "stage": "B6 routability-driven global placement",
            "tool_message": "current overflow increased relative to its minimum while HPWL significantly worsened",
            "source_behavior": "installed OpenROAD raises GPL-0307 and explicitly recommends a smaller max_phi_coef",
            "observed_wall_seconds": 5215,
            "observed_peak_rss_kib": 26_259_484,
            "observed_exit_code": 1,
            "global_route_invocations": 0,
        },
        "selected_eco": {
            "single_independent_variable": "global_placement.max_phi_coef",
            "before": 1.05,
            "after": 1.01,
            "reason": "use a conservative value within OpenROAD's documented range and directly follow the GPL-0307 diagnostic",
        },
        "unchanged_contract": {
            "min_phi_coef": 0.95,
            "rtl": "byte-identical",
            "mapped_netlist": "byte-identical",
            "sdc": "byte-identical",
            "fence_geometry": "unchanged",
            "rudy_policy": "unchanged except max_phi_coef",
            "locked_anchor_targets": 2,
            "detailed_placement_policy": "unchanged",
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
        },
        "functional_evidence": {
            "policy": "reuse sealed B5 cheap 9/9 because B7 changes only one physical optimizer coefficient",
            "fresh_smoke_required": True,
            "fresh_physical_authorization_required": True,
        },
        "inputs": {
            "b6_placement_report": {"path": str(manifest_path), "sha256": sha(manifest_path)},
            "b6_placement_log": {"path": str(log_path), "sha256": sha(log_path)},
            "b6_placement_tcl": {"path": str(tcl_path), "sha256": sha(tcl_path)},
            "openroad_gpl_source": {"path": str(OPENROAD_GPL), "sha256": sha(OPENROAD_GPL)},
        },
        "authorizes": [],
        "next_stage": "B7_SMOKE",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown.write_text(
        "\n".join(
            [
                "# B7 lower-max-phi recovery",
                "",
                f"Generated: `{payload['generated_at_utc']}`",
                "",
                "B6 is sealed as a pre-route `GPL-0307` tool failure. It produced no placement checkpoint, invoked no audit or global route, and preserved every frozen artifact hash.",
                "",
                "B7 changes exactly one independent variable: `global_placement -max_phi_coef` from `1.05` to `1.01`. This directly follows the installed OpenROAD diagnostic. RTL, mapped netlist, SDC, fences, RUDY parameters, anchor locks, detailed-placement policy, and route policy remain unchanged.",
                "",
                "B7 requires a fresh input-reopen/checkpoint smoke and a fresh hash-pinned physical authorization before compute.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"B7_ECO_DECISION SELECTED output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
