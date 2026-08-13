#!/usr/bin/env python3
"""Fail closed unless current wbq evidence authorizes Phase 6 from exact placement bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from decide_wbq_post_route import decide

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DECISION = ROOT / "reports/final_integrated_gds_execution/wbq_post_route_decision.json"
DEFAULT_PLACEMENT = ROOT / "reports/final_integrated_gds_execution/wbq_placement_manifest.json"
REQUIRED_PLACEMENT_ARTIFACTS = ("placed_odb", "placed_sdc")


def absolute(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (ROOT / path).resolve()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(
    decision_path: str | Path = DEFAULT_DECISION,
    placement_path: str | Path = DEFAULT_PLACEMENT,
) -> dict[str, Any]:
    decision_file = absolute(decision_path)
    placement_file = absolute(placement_path)
    decision_document = json.loads(decision_file.read_text(encoding="utf-8-sig"))
    placement = json.loads(placement_file.read_text(encoding="utf-8-sig"))

    source_manifest = absolute(decision_document.get("source_manifest", ""))
    source_exists = source_manifest.is_file() and source_manifest.stat().st_size > 0
    source_hash = sha256(source_manifest) if source_exists else None
    recomputed = decide(source_manifest) if source_exists else None

    checks: dict[str, bool] = {
        "decision_schema_version": decision_document.get("schema_version") == 1,
        "decision_exact_phase6": decision_document.get("decision")
        == "PHASE6_CLOCK_AND_DETAILED_ROUTE",
        "decision_evidence_valid": decision_document.get("evidence_valid") is True,
        "source_manifest_exists_nonempty": source_exists,
        "source_manifest_hash_match": source_hash
        == decision_document.get("source_manifest_sha256"),
        "source_recomputes_phase6": recomputed is not None
        and recomputed.get("decision") == "PHASE6_CLOCK_AND_DETAILED_ROUTE",
        "placement_schema_version": placement.get("schema_version") == 1,
        "placement_top": placement.get("top") == "logic_die_normalization_hbm_top",
        "placement_variant": placement.get("variant") == "wbq",
        "placement_gate_pass": placement.get("gate_pass") is True,
    }

    artifacts: dict[str, dict[str, Any]] = {}
    placement_inventory = placement.get("artifacts", {})
    for name in REQUIRED_PLACEMENT_ARTIFACTS:
        item = placement_inventory.get(name, {})
        artifact = absolute(item.get("path", ""))
        exists = artifact.is_file() and artifact.stat().st_size > 0
        actual_bytes = artifact.stat().st_size if exists else None
        actual_hash = sha256(artifact) if exists else None
        match = (
            exists
            and actual_bytes == item.get("bytes")
            and actual_hash == item.get("sha256")
        )
        checks[f"placement_{name}_match"] = bool(match)
        artifacts[name] = {
            "path": str(artifact),
            "exists_nonempty": exists,
            "bytes": actual_bytes,
            "sha256": actual_hash,
            "manifest_match": bool(match),
        }

    gate_pass = all(checks.values())
    return {
        "schema_version": 1,
        "gate": "WBQ_PHASE6_INPUT_GATE",
        "gate_pass": gate_pass,
        "checks": checks,
        "decision_path": str(decision_file),
        "decision_sha256": sha256(decision_file),
        "source_manifest_path": str(source_manifest),
        "source_manifest_sha256": source_hash,
        "placement_manifest_path": str(placement_file),
        "placement_manifest_sha256": sha256(placement_file),
        "placement_artifacts": artifacts,
        "claim_boundary": "Input authorization only; CTS, reroute, detailed route, and GDS are not yet established.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decision", default=str(DEFAULT_DECISION))
    parser.add_argument("--placement", default=str(DEFAULT_PLACEMENT))
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = verify(args.decision, args.placement)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"WBQ_PHASE6_INPUT_GATE FAIL error={error}")
        return 2
    if args.output:
        output = absolute(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    verdict = "PASS" if result["gate_pass"] else "FAIL"
    print(f"WBQ_PHASE6_INPUT_GATE {verdict}")
    return 0 if result["gate_pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
