#!/usr/bin/env python3
"""Select the B25 aggregated completion-descriptor structural ECO."""

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/groot_normalization/quad_local_b25"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    decision = OUT / "b25_eco_decision.json"
    report = OUT / "b25_eco_decision.md"
    if decision.exists() or report.exists():
        raise SystemExit("refusing to overwrite B25 decision")
    evidence = {}
    for variant, residual, overflow in (("b21", 455, 345), ("b24", 487, 363)):
        base = ROOT / f"reports/groot_normalization/quad_local_{variant}"
        gate = json.loads((base / "phase6_decision_gate.json").read_text())
        analysis = json.loads((base / f"{variant}_residual_congestion_analysis.json").read_text())
        if gate.get("decision") != "BLOCKED_RESIDUAL_CONGESTION" or gate.get("authorizes") != []:
            raise SystemExit(f"{variant} is not sealed BLOCKED")
        totals = analysis.get("totals", {})
        if totals.get("rrr_residual") != residual or totals.get("overflow_edges") != overflow:
            raise SystemExit(f"{variant} evidence mismatch")
        evidence[variant] = {
            "gate": {"path": str(base / "phase6_decision_gate.json"), "sha256": sha(base / "phase6_decision_gate.json")},
            "analysis": {"path": str(base / f"{variant}_residual_congestion_analysis.json"), "sha256": sha(base / f"{variant}_residual_congestion_analysis.json")},
        }
    rtl = [
        ROOT / "rtl/normalization_quad_local_bank_scheduler.sv",
        ROOT / "rtl/logic_die_normalization_quad_local_pcu_top.sv",
    ]
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B25",
        "decision": "SELECT_B25_AGGREGATED_COMPLETION_DESCRIPTOR_ECO",
        "status": "SELECTED_PENDING_CHEAP_GATES",
        "failure_classification": {
            "automatic_recovery_class": "residual_congestion",
            "subtype": "central_completion_compare_fabric",
            "not_a_stall": True,
        },
        "congestion_evidence": {
            "best_valid_route": {"variant": "B21", "residual": 455, "overflow_edges": 345},
            "adjacent_origin_probe": {"variant": "B24", "residual": 487, "overflow_edges": 363},
            "dominant_region": "central_corridor",
            "repeated_sources": ["quad_completion_tag", "clk_i"],
        },
        "selected_eco": {
            "single_independent_variable": "completion_descriptor_transport_structure",
            "before": "four valid bits plus four 16-bit tags consumed by central PCU",
            "after": "one all-quad valid bit plus one verified 16-bit tag consumed by central PCU",
            "hypothesis": "move all-quad agreement and tag equality checks into the scheduler boundary to remove 51 central interconnect bits and duplicated context comparators",
        },
        "preserved_contract": {
            "external_interfaces": "byte-identical",
            "ready_valid_ordering_tag_backpressure": "unchanged",
            "completion_acceptance": "all four quads valid in the same cycle with identical tags",
            "rtl_top": "logic_die_normalization_hbm_quad_local_b2_top",
            "clock_reset_policy": "unchanged",
        },
        "expected_cost": {"latency_cycles": 0, "throughput_change": "none", "area": "reduced central compare fabric"},
        "success_criteria": [
            "registered and unregistered random A/B regressions pass",
            "PCU and HBM boundary regressions pass",
            "Yosys check reports zero problems and mapped primitives are zero",
            "mapped audit proves completion boundary width is 17 bits",
            "legal placement and single-shot global route pass strict zero-congestion gate",
        ],
        "inputs": evidence,
        "rtl_outputs": {str(path): sha(path) for path in rtl},
        "authorizes": [],
        "next_stage": "B25_CHEAP_GATES",
    }
    OUT.mkdir(parents=True, exist_ok=True)
    decision.write_text(json.dumps(payload, indent=2) + "\n")
    report.write_text(
        "# B25 aggregated completion descriptor ECO\n\n"
        "B21/B24 prove pin-origin tuning does not close congestion. B25 preserves the external protocol and moves the already-required all-quad/tag agreement check to the scheduler boundary, reducing the central completion interface from 68 bits to 17 bits.\n"
    )
    print("B25_ECO_DECISION SELECTED")


if __name__ == "__main__":
    main()
