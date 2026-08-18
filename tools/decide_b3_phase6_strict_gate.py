#!/usr/bin/env python3
"""Evaluate the four fail-closed Phase 6 release conditions for B3."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b3"
PHYSICAL = REPORT / "physical"
ROUTE_MANIFEST = PHYSICAL / "b3_global_route_execution_report.json"
ANALYSIS = REPORT / "b3_residual_congestion_analysis.json"
PLACEMENT = PHYSICAL / "b3_placement_execution_report.json"
OUTPUT = REPORT / "phase6_decision_gate.json"


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
    if OUTPUT.exists():
        raise FileExistsError(f"refusing to overwrite Phase 6 gate: {OUTPUT}")
    placement = load(PLACEMENT)
    route = load(ROUTE_MANIFEST)
    analysis = load(ANALYSIS)

    artifact_checks = []
    for name, item in route.get("outputs", {}).items():
        path = Path(item["path"])
        actual = sha256(path) if path.is_file() else None
        artifact_checks.append({
            "name": name,
            "path": str(path),
            "expected_sha256": item.get("sha256"),
            "actual_sha256": actual,
            "match": actual == item.get("sha256") and actual is not None,
        })
    input_hashes_match = (
        placement.get("status") == "PASS"
        and route.get("status") == "PASS"
        and route.get("invocation_count") == 1
        and all(item["match"] for item in artifact_checks)
        and all(item.get("match") for item in analysis.get("preserved_routed_odb", {}).values())
    )
    totals = analysis.get("totals", {})
    residual = totals.get("rrr_residual")
    overflow_edges = totals.get("overflow_edges")
    preliminary = residual == 0 and overflow_edges == 0 and input_hashes_match
    # This file is the separate explicit decision required by the fourth
    # condition.  It issues PASS only when the other independent checks pass.
    explicit_pass = preliminary
    passed = preliminary and explicit_pass
    conditions = {
        "residual_congestion_zero": {
            "required": 0,
            "actual": residual,
            "result": "PASS" if residual == 0 else "FAIL",
        },
        "overflow_edges_zero": {
            "required": 0,
            "actual": overflow_edges,
            "result": "PASS" if overflow_edges == 0 else "FAIL",
        },
        "input_artifact_hashes_match": {
            "required": True,
            "actual": input_hashes_match,
            "result": "PASS" if input_hashes_match else "FAIL",
        },
        "explicit_phase6_pass": {
            "required": True,
            "actual": explicit_pass,
            "result": "PASS" if explicit_pass else "FAIL",
        },
    }
    payload = {
        "schema_version": 2,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "phase": 6,
        "variant": "B3",
        "decision": "PASS" if passed else "BLOCKED_RESIDUAL_CONGESTION",
        "reason": (
            "B3 has zero RRR residual, zero numeric overflow edges, matching input hashes, and this explicit PASS."
            if passed
            else "One or more strict zero-congestion/hash conditions failed; Phase 6 remains fail-closed."
        ),
        "conditions": conditions,
        "artifact_hash_checks": artifact_checks,
        "inputs": {
            "placement_execution_report": {"path": str(PLACEMENT), "sha256": sha256(PLACEMENT)},
            "global_route_execution_report": {"path": str(ROUTE_MANIFEST), "sha256": sha256(ROUTE_MANIFEST)},
            "direct_congestion_analysis": {"path": str(ANALYSIS), "sha256": sha256(ANALYSIS)},
        },
        "global_route_invocation_count": route.get("invocation_count"),
        "authorizes": ["B3_PHASE6_CTS"] if passed else [],
        "next_stage": "B3_PHASE6_CTS" if passed else None,
        "blocked_recovery": None if passed else "Seal B3 without reroute; create a separately justified B4 ECO variant.",
    }
    with OUTPUT.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2)
        stream.write("\n")
    print(
        f"B3_PHASE6_STRICT_GATE {payload['decision']} residual={residual} "
        f"overflow_edges={overflow_edges} authorizes={payload['authorizes']}"
    )
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
