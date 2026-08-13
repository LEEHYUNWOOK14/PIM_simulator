#!/usr/bin/env python3
"""Verify Phase-4 evidence and select the next wbq physical-flow phase."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "reports/final_integrated_gds_execution/wbq_global_route_manifest.json"
ARTIFACT_KEYS = {"route_log", "route_guide", "congestion_report", "routed_odb", "routed_sdc"}


def absolute(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (ROOT / path).resolve()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decide(manifest_path: str | Path) -> dict[str, Any]:
    path = absolute(manifest_path)
    manifest = json.loads(path.read_text(encoding="utf-8-sig"))
    artifacts = manifest.get("artifacts", {})
    checks: dict[str, bool] = {
        "schema_version": manifest.get("schema_version") == 1,
        "top": manifest.get("top") == "logic_die_normalization_hbm_top",
        "variant": manifest.get("variant") == "wbq_v4_control",
        "same_metric_definition": manifest.get("same_metric_definition") is True,
        "placement_gate_pass": manifest.get("placement_gate_pass") is True,
        "placement_input_hashes_match": manifest.get("placement_input_hashes_match") is True,
        "clean_completion": manifest.get("clean_completion") is True,
        "artifact_inventory": set(artifacts) == ARTIFACT_KEYS,
    }
    artifact_results: dict[str, dict[str, Any]] = {}
    if checks["artifact_inventory"]:
        for name in sorted(ARTIFACT_KEYS):
            item = artifacts[name]
            artifact = absolute(item.get("path", ""))
            exists = artifact.is_file() and artifact.stat().st_size > 0
            actual_hash = sha256(artifact) if exists else None
            actual_bytes = artifact.stat().st_size if exists else None
            match = (
                exists
                and actual_hash == item.get("sha256")
                and actual_bytes == item.get("bytes")
            )
            checks[f"artifact_{name}"] = bool(match)
            artifact_results[name] = {
                "path": str(artifact), "exists_nonempty": exists,
                "bytes": actual_bytes, "sha256": actual_hash, "manifest_match": bool(match),
            }

    evidence_valid = all(checks.values())
    verdict = manifest.get("verdict")
    if not evidence_valid or verdict not in {"PASS_PF4", "IMPROVED_NOT_CLOSED", "NO_IMPROVEMENT"}:
        decision = "STOP_INVALID_RUN"
    elif verdict == "PASS_PF4":
        current = manifest.get("current_wbq", {})
        if (
            current.get("residual_congestion") == 0
            and current.get("overflow_edges") == 0
            and current.get("all_skipped_nets_allowlisted") is True
        ):
            decision = "PHASE6_CLOCK_AND_DETAILED_ROUTE"
        else:
            decision = "STOP_INVALID_RUN"
    else:
        decision = "PHASE5_HIERARCHICAL_ARCHITECTURE"

    return {
        "schema_version": 1,
        "source_manifest": str(path),
        "source_manifest_sha256": sha256(path),
        "verdict": verdict,
        "evidence_valid": evidence_valid,
        "checks": checks,
        "artifact_results": artifact_results,
        "decision": decision,
        "claim_boundary": "Decision gate only; it does not itself establish CTS, detailed-route, GDS, or manufacturing signoff.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = decide(args.manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"WBQ_POST_ROUTE_DECISION STOP_INVALID_RUN error={error}")
        return 2
    if args.output:
        output = absolute(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"WBQ_POST_ROUTE_DECISION {result['decision']} verdict={result['verdict']}")
    return 0 if result["decision"] != "STOP_INVALID_RUN" else 2


if __name__ == "__main__":
    raise SystemExit(main())
