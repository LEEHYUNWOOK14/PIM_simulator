#!/usr/bin/env python3
"""Hash-pin B6's sole post-CTS global-route invocation."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b6"
PHASE6 = REPORT / "phase6"
CTS_MANIFEST = PHASE6 / "b6_phase6_cts_execution_report.json"
RUNNER = ROOT / "verification/groot_normalization/run_wbq_b6_phase6_post_cts_global_route.sh"
TCL = ROOT / "verification/groot_normalization/wbq_b6_phase6_post_cts_global_route.tcl"
AUDIT_TCL = ROOT / "verification/groot_normalization/audit_wbq_b6_phase6_post_cts_route.tcl"
PARSER = ROOT / "tools/analyze_variant_residual_congestion.py"
SNAPSHOT_TOOL = ROOT / "tools/capture_openroad_stage_snapshot.py"
COMPARE_TOOL = ROOT / "tools/compare_openroad_stage_snapshots.py"
OUTPUT = PHASE6 / "b6_phase6_post_cts_route_authorization.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def evidence(path: Path) -> dict:
    return {"path": str(path), "sha256": sha256(path)}


def main() -> int:
    if OUTPUT.exists():
        raise FileExistsError(f"refusing to overwrite B6 post-CTS route authorization: {OUTPUT}")
    cts = load(CTS_MANIFEST)
    runner_text = RUNNER.read_text(encoding="utf-8")
    tcl_text = TCL.read_text(encoding="utf-8")
    audit_text = AUDIT_TCL.read_text(encoding="utf-8")
    odb_item = cts.get("artifacts", {}).get("cts_odb", {})
    sdc_item = cts.get("artifacts", {}).get("cts_sdc", {})
    odb = Path(odb_item.get("path", ""))
    sdc = Path(sdc_item.get("path", ""))
    cts_hashes_match = (
        odb.is_file() and sdc.is_file()
        and sha256(odb) == odb_item.get("sha256")
        and sha256(sdc) == sdc_item.get("sha256")
    )
    route_root = Path("/dev/shm/wbq_b6_phase6_10/phase6_post_cts")
    prior_outputs = [
        PHASE6 / name
        for name in (
            "b6_phase6_post_cts_preflight.json", "b6_phase6_post_cts_global_route_invocation.json",
            "b6_phase6_post_cts_global_route_execution_report.json", "b6_phase6_post_cts_global_route.log",
            "b6_phase6_post_cts_route_audit.log", "b6_phase6_post_cts_congestion_analysis.json",
            "b6_phase6_post_cts_congestion_analysis.md",
        )
    ] + [
        route_root / name
        for name in (
            "b6_phase6_post_cts.route_guide", "b6_phase6_post_cts.congestion.rpt",
            "b6_phase6_post_cts_global_route.odb", "b6_phase6_post_cts_global_route.sdc",
        )
    ]
    conditions = {
        "cts_pass": cts.get("status") == "PASS",
        "cts_authorizes_post_route": "B6_PHASE6_POST_CTS_GLOBAL_ROUTE_AUTHORIZATION" in cts.get("authorizes", []),
        "cts_hashes_match": cts_hashes_match,
        "one_route_invocation": "global_route_invocation_limit\": 1" in runner_text,
        "ten_cugr_iterations": "$iterations != 10" in tcl_text,
        "tcl_single_route_command": tcl_text.count("global_route \\") == 1,
        "runner_refuses_duplicates": "refusing duplicate" in runner_text,
        "runner_records_exact_pids": "launcher_pid" in runner_text and "compute_pid" in runner_text and "audit_compute_pid" in runner_text,
        "runner_has_signal_traps": "trap 'on_signal INT' INT" in runner_text and "trap 'on_signal TERM' TERM" in runner_text,
        "direct_numeric_compact_parser": "--max-windows-in-output 0" in runner_text,
        "audit_requires_clock_and_routes": "clock_net_count < 1" in audit_text and "!$has_routes" in audit_text,
        "no_prior_route_artifact": not any(path.exists() for path in prior_outputs),
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "phase": 6,
        "variant": "B6_PHASE6_POST_CTS",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {key: "PASS" if value else "FAIL" for key, value in conditions.items()},
        "inputs": {
            "cts_execution_report": evidence(CTS_MANIFEST),
            "cts_odb": evidence(odb) if odb.is_file() else {"path": str(odb), "sha256": None},
            "cts_sdc": evidence(sdc) if sdc.is_file() else {"path": str(sdc), "sha256": None},
            "runner": evidence(RUNNER),
            "route_tcl": evidence(TCL),
            "audit_tcl": evidence(AUDIT_TCL),
            "direct_numeric_parser": evidence(PARSER),
            "silence_snapshot_tool": evidence(SNAPSHOT_TOOL),
            "silence_compare_tool": evidence(COMPARE_TOOL),
        },
        "policy": {
            "service": "wbq-b6-phase6-post-cts-route.service",
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 10,
            "skip_large_fanout_nets": 20000,
            "require_no_skipped_nets": True,
            "require_zero_residual_and_overflow": True,
            "fail_closed": True,
        },
        "authorizes": ["B6_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE"] if passed else [],
        "next_stage": "B6_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE" if passed else None,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B6_PHASE6_POST_CTS_ROUTE_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
