#!/usr/bin/env python3
"""Issue the fail-closed B3 physical authorization after all cheap gates pass."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b3"
DECISION = REPORT / "b3_eco_decision.json"
CHEAP = REPORT / "cheap_gate_manifest.json"
OUTPUT = REPORT / "b3_physical_authorization.json"


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


def main() -> int:
    decision = load(DECISION)
    cheap = load(CHEAP)
    gates = cheap.get("gates", [])
    gates_by_id = {gate.get("id"): gate for gate in gates}
    mapped_gate = gates_by_id.get("mapped_locality_reset_audit", {})
    workload_gate = gates_by_id.get("actual_workload_accuracy", {})
    mapped_path = ROOT / mapped_gate.get("artifact", "missing")
    workload_path = ROOT / workload_gate.get("artifact", "missing")
    mapped = load(mapped_path) if mapped_path.is_file() else {}
    workload = load(workload_path) if workload_path.is_file() else {}
    mapped_checks = mapped.get("checks", [])
    profiles = workload.get("profiles", [])
    conditions = {
        "selected_b3_route_effort_eco": decision.get("decision") == "SELECT_B3_ROUTE_EFFORT_ECO",
        "precheap_decision_fail_closed": decision.get("authorizes") == [],
        "cheap_gate_9_of_9": cheap.get("overall_result") == "PASS" and len(gates) == 9
        and all(gate.get("result") == "PASS" for gate in gates),
        "mapped_assertions_20_of_20": mapped.get("overall_result") == "PASS"
        and len(mapped_checks) == 20
        and sum(check.get("result") == "PASS" for check in mapped_checks) == 20,
        "workload_profiles_6_of_6": workload.get("overall_result") == "PASS"
        and workload.get("passed_profiles") == 6
        and workload.get("failed_profiles") == 0
        and len(profiles) == 6,
        "requested_global_route_invocation_limit_is_one": decision.get("global_route_invocation_limit") == 1,
        "requested_cugr_iterations_is_ten": decision.get("cugr_congestion_iterations") == 10,
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B3",
        "decision": "PASS" if passed else "BLOCKED_CHEAP_GATE",
        "conditions": {name: "PASS" if value else "FAIL" for name, value in conditions.items()},
        "inputs": {
            "b3_eco_decision": {"path": str(DECISION), "sha256": sha256(DECISION)},
            "cheap_gate_manifest": {"path": str(CHEAP), "sha256": sha256(CHEAP)},
            "mapped_locality_audit": {
                "path": str(mapped_path),
                "sha256": sha256(mapped_path) if mapped_path.is_file() else None,
            },
            "workload_accuracy": {
                "path": str(workload_path),
                "sha256": sha256(workload_path) if workload_path.is_file() else None,
            },
        },
        "authorizes": ["B3_PLACEMENT", "B3_SINGLE_GLOBAL_ROUTE"] if passed else [],
        "next_stage": "B3_PLACEMENT" if passed else None,
    }
    if OUTPUT.exists():
        raise FileExistsError(f"refusing to overwrite existing authorization: {OUTPUT}")
    with OUTPUT.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2)
        stream.write("\n")
    print(f"B3_PHYSICAL_AUTHORIZATION {payload['decision']} output={OUTPUT}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
