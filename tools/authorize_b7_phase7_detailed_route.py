#!/usr/bin/env python3
"""Issue a one-shot, hash-pinned authorization for B7 detailed route."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b7"
PHASE6 = REPORT / "phase6"
PHASE7 = REPORT / "phase7"
INPUT_ROOT = Path(
    os.environ.get(
        "WBQ_B7_PHASE6_ROUTE_ROOT", "/dev/shm/wbq_b7_phase6_10/phase6_post_cts"
    )
)
SOURCE = PHASE6 / "b7_phase6_post_cts_global_route_execution_report.json"
ODB = INPUT_ROOT / "b7_phase6_post_cts_global_route.odb"
SDC = INPUT_ROOT / "b7_phase6_post_cts_global_route.sdc"
OUTPUT = PHASE7 / "b7_phase7_detailed_route_authorization.json"

PINNED_TOOLS = {
    "authorization_tool": ROOT / "tools/authorize_b7_phase7_detailed_route.py",
    "runner": ROOT / "verification/groot_normalization/run_wbq_b7_phase7_detailed_route.sh",
    "route_tcl": ROOT / "verification/groot_normalization/wbq_b7_phase7_detailed_route.tcl",
    "audit_tcl": ROOT / "verification/groot_normalization/audit_wbq_b7_phase7_detailed_route.tcl",
    "silence_snapshot_tool": ROOT / "tools/capture_openroad_stage_snapshot.py",
    "silence_compare_tool": ROOT / "tools/compare_openroad_stage_snapshots.py",
}

REFUSE_IF_PRESENT = (
    PHASE7 / "b7_phase7_preflight.json",
    PHASE7 / "b7_phase7_detailed_route_invocation.json",
    PHASE7 / "b7_phase7_detailed_route_execution_report.json",
    PHASE7 / "b7_phase7_detailed_route.log",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def item(path: Path) -> dict:
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def main() -> int:
    PHASE7.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        raise FileExistsError(f"refusing to overwrite {OUTPUT}")
    for path in (SOURCE, ODB, SDC, *PINNED_TOOLS.values()):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)

    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    recorded = source.get("artifacts", {})
    openroad = subprocess.run(
        ["pgrep", "-a", "-x", "openroad"], capture_output=True, text=True
    )
    openroad_processes = [line for line in openroad.stdout.splitlines() if line.strip()]
    checks = {
        "post_cts_status_pass": source.get("status") == "PASS",
        "post_cts_authorizes_phase7": (
            "B7_PHASE7_DETAILED_ROUTE_AUTHORIZATION"
            in source.get("authorizes", [])
        ),
        "zero_rrr_residual": source.get("metrics", {}).get("rrr_residual") == 0,
        "zero_overflow_edges": source.get("metrics", {}).get("overflow_edges") == 0,
        "no_skipped_nets": source.get("skipped_nets") == [],
        "protected_artifacts_preserved": (
            source.get("protected_artifacts_preserved") is True
        ),
        "routed_odb_hash": recorded.get("routed_odb", {}).get("sha256")
        == sha256(ODB),
        "routed_sdc_hash": recorded.get("routed_sdc", {}).get("sha256")
        == sha256(SDC),
        "no_prior_phase7_attempt": not any(path.exists() for path in REFUSE_IF_PRESENT),
        "no_openroad_process": not openroad_processes,
    }
    passed = all(checks.values())
    payload = {
        "schema_version": 1,
        "phase": 7,
        "variant": "B7_PHASE7_DETAILED_ROUTE",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "decision": "PASS" if passed else "BLOCKED",
        "checks": checks,
        "openroad_processes": openroad_processes,
        "inputs": {
            "phase6_post_cts_manifest": item(SOURCE),
            "routed_odb": item(ODB),
            "routed_sdc": item(SDC),
            **{name: item(path) for name, path in PINNED_TOOLS.items()},
        },
        "resource_contract": {
            "minimum_mem_available_gib": 32,
            "minimum_output_free_gib": 12,
            "basis": (
                "B2/B7 ODBs are approximately 3.3-4.4 GiB; 12 GiB retains "
                "headroom for ODB, DEF, reports, and logs in the bounded tmpfs."
            ),
        },
        "invocation_limit": 1,
        "authorizes": ["B7_PHASE7_DETAILED_ROUTE_COMPUTE"] if passed else [],
        "next_stage": "B7_PHASE7_DETAILED_ROUTE_COMPUTE" if passed else None,
    }
    with OUTPUT.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2)
        stream.write("\n")
    print(f"WBQ_B7_PHASE7_DETAILED_ROUTE_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

