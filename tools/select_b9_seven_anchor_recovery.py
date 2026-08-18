#!/usr/bin/env python3
"""Seal B8 and select the one-variable B9 seven-anchor recovery."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B8 = ROOT / "reports/groot_normalization/quad_local_b8"
B9 = ROOT / "reports/groot_normalization/quad_local_b9"
ANCHOR_LOG = B8 / "b9_anchor_candidate_inspection.log"
ANCHORS = (
    ("u_b2_implementation/u_quad_local_adapter/wire440455", 7_308_480, 4_417_280, "MY"),
    ("u_b2_implementation/u_quad_local_adapter/wire440867", 4_287_200, 1_392_640, "MY"),
    ("u_b2_implementation/u_quad_local_adapter/wire440876", 4_285_360, 1_479_680, "R180"),
    ("u_b2_implementation/u_quad_local_adapter/wire441097", 4_723_740, 6_636_800, "R0"),
    ("u_b2_implementation/u_quad_local_adapter/wire441921", 4_376_900, 2_186_880, "MX"),
    ("u_b2_implementation/u_quad_local_adapter/wire441940", 4_345_620, 2_208_640, "R0"),
    ("u_b2_implementation/u_quad_local_adapter/wire441994", 4_293_640, 2_224_960, "MX"),
)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest_path = B8 / "physical/b8_placement_execution_report.json"
    log_path = B8 / "physical/b8_place.log"
    tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b8_drc_place.tcl"
    b7_rudy = Path("/dev/shm/wbq_b7_phase6_10/quad_local_b7/b7_rudy.odb")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    anchor_log = ANCHOR_LOG.read_text(encoding="utf-8", errors="replace")
    tcl = tcl_path.read_text(encoding="utf-8")
    if not (
        manifest.get("status") == "FAIL"
        and manifest.get("failure_class") == "design_legality_failure"
        and manifest.get("exit_code") == 1
        and manifest.get("global_route_invocations") == 0
        and manifest.get("protected_artifacts_preserved") is True
        and manifest.get("runtime_policy_marker") == "PASS"
        and not manifest.get("authorizes")
    ):
        raise RuntimeError("B8 is not a sealed protected legality failure")
    required = (
        "NegotiationLegalizer DRC penalty: 100.",
        "NegotiationLegalizer did not fully converge. Violations remain: 18",
        "Overlap check failed (7).",
        "Padding check failed (7).",
        "DPL-0033",
        "WBQ_B8_PLACE_EXIT_CODE=1",
    )
    if not all(token in log for token in required):
        raise RuntimeError("B8 failure signature is incomplete")
    if "WBQ_B9_B2_SOURCE_LEGALITY violations={}" not in anchor_log or "WBQ_B9_B2_ANCHOR_CANDIDATES PASS count=7" not in anchor_log:
        raise RuntimeError("B2 anchor source was not independently proven legal")
    pattern = re.compile(
        r"^WBQ_B9_B2_ANCHOR_CANDIDATE name=\{(.+?)\} origin_dbu=\{(\d+) (\d+)\} orient=\{(\S+)\} status=\{PLACED\}",
        re.MULTILINE,
    )
    observed = [(name, int(x), int(y), orient) for name, x, y, orient in pattern.findall(anchor_log)]
    if observed != list(ANCHORS):
        raise RuntimeError("measured B2 anchor candidates do not match the selected set")
    if "-drc_penalty 100" not in tcl or "-use_diamond_legalizer" in tcl:
        raise RuntimeError("B8 legalizer policy is not the sealed baseline")
    if not b7_rudy.is_file() or sha(b7_rudy) != manifest.get("inputs", {}).get("b7_rudy_odb", {}).get("sha256"):
        raise RuntimeError("sealed B7 RUDY checkpoint changed")

    B9.mkdir(parents=True, exist_ok=True)
    output = B9 / "b9_eco_decision.json"
    markdown = B9 / "b9_eco_decision.md"
    if output.exists() or markdown.exists():
        raise FileExistsError("refusing to overwrite B9 decision")
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B9",
        "decision": "SELECT_B9_SEVEN_ADDITIONAL_ANCHORS_ECO",
        "status": "SELECTED_PENDING_SMOKE_AND_AUTHORIZATION",
        "failure_classification": {
            "automatic_recovery_class": "design_legality_failure",
            "subtype": "drc_penalty_insensitive_fixed_tap_overlaps",
            "b8_same_seven_offenders": True,
            "not_a_stall": True,
            "resource_exhaustion": False,
        },
        "selected_eco": {
            "single_independent_variable": "locked_anchor_targets",
            "before": 2,
            "after": 9,
            "new_anchors": [
                {"instance": name, "origin_dbu": [x, y], "orientation": orient}
                for name, x, y, orient in ANCHORS
            ],
            "reason": "each repeated offender is returned to its independently reopened, globally legal B2 origin and locked so surrounding movable cells legalize around it",
        },
        "unchanged_contract": {
            "drc_penalty": 100,
            "rtl": "byte-identical",
            "mapped_netlist": "byte-identical",
            "sdc": "byte-identical",
            "fence_geometry": "byte-identical in sealed B7 RUDY ODB",
            "global_placement_result": "byte-identical sealed B7 RUDY ODB",
            "max_displacement_um": [1000, 1000],
            "site_search_window": 100,
            "row_search_window": 20,
            "full_design_diamond": False,
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
        },
        "functional_evidence": {
            "policy": "reuse sealed B5 cheap 9/9 because B9 changes only the physical anchor target set",
            "fresh_smoke_required": True,
            "fresh_physical_authorization_required": True,
        },
        "inputs": {
            "b8_placement_report": {"path": str(manifest_path), "sha256": sha(manifest_path)},
            "b8_placement_log": {"path": str(log_path), "sha256": sha(log_path)},
            "b8_placement_tcl": {"path": str(tcl_path), "sha256": sha(tcl_path)},
            "b2_anchor_inspection": {"path": str(ANCHOR_LOG), "sha256": sha(ANCHOR_LOG)},
            "b7_rudy_odb": {"path": str(b7_rudy), "sha256": sha(b7_rudy)},
        },
        "authorizes": [],
        "next_stage": "B9_SMOKE",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown.write_text(
        "# B9 seven-anchor recovery\n\n"
        f"Generated: `{payload['generated_at_utc']}`\n\n"
        "B8 proved that increasing DRC penalty from 20 to 100 does not move the repeated seven fixed-tap offenders. B9 therefore keeps penalty 100 and changes one variable: the locked anchor set from two to nine targets.\n\n"
        "The seven added origins and orientations were independently reopened from the sealed, legal B2 placement. RTL, netlist, SDC, fences, B7 RUDY checkpoint, search windows, and route policy remain unchanged.\n",
        encoding="utf-8",
    )
    print(f"B9_ECO_DECISION SELECTED output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
