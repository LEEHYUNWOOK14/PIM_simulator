#!/usr/bin/env python3
"""Create compact numeric evidence from the completed B9 placement log."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def last(pattern: str, text: str) -> str | None:
    values = re.findall(pattern, text, re.MULTILINE)
    return values[-1] if values else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--placement-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite {args.output}")
    for path in (args.log, args.placement_manifest):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)

    text = args.log.read_text(encoding="utf-8", errors="replace")
    manifest = json.loads(args.placement_manifest.read_text(encoding="utf-8"))
    verified = re.findall(
        r"^WBQ_B9_ANCHOR_VERIFIED name=\{(.+?)\} origin_dbu=\{(\d+) (\d+)\} "
        r"orient=\{(\S+)\} status=\{(\S+)\} mode=\{(existing|added)\}$",
        text,
        re.MULTILINE,
    )
    legality = last(r"^WBQ_B9_PLACE_LEGALITY violations=\{(.*)\}$", text)
    exit_code = last(r"^WBQ_B9_PLACE_EXIT_CODE=(\d+)$", text)
    elapsed = last(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(\S+)", text)
    peak_rss = last(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    dpl_runtime = last(r"\[INFO DPL-0500\] Runtime:\s*([-+0-9.eE]+)s", text)
    initial_violations = last(r"^\s*0 \|\s*(\d+) \|", text)
    remaining_violations = last(r"Violations remain:\s*(\d+)", text)
    recorded_log = manifest.get("outputs", {}).get("log", {})
    existing = [item for item in verified if item[5] == "existing"]
    added = [item for item in verified if item[5] == "added"]
    checks = {
        "placement_manifest_pass": manifest.get("status") == "PASS",
        "log_hash_matches_manifest": recorded_log.get("sha256") == sha256(args.log),
        "exit_zero": exit_code == "0",
        "sealed_b7_rudy_input": manifest.get("policy", {}).get("sealed_b7_rudy_checkpoint") is True
        and bool(manifest.get("inputs", {}).get("b7_rudy_odb", {}).get("sha256")),
        "post_legalize_checkpoint": "WBQ_B9_POST_LEGALIZE_CHECKPOINT PASS" in text,
        "nine_anchor_runtime_marker": "WBQ_B9_ANCHOR_RECOVERY_POLICY anchor_targets=9 added_targets=7 max_displacement={1000 1000} site_window=100 row_window=20 drc_penalty=100 full_design_diamond=0" in text,
        "failed_legality_signature_absent": "DPL-0033" not in text
        and "Overlap check failed" not in text
        and "Padding check failed" not in text,
        "final_place_token": "WBQ_B9_NINE_ANCHOR_PLACE PASS" in text,
        "nine_verified_locked_anchors": len(verified) == 9
        and len(existing) == 2
        and len(added) == 7
        and all(item[4] == "LOCKED" for item in verified),
        "legal_placement": legality == "",
        "generic_placement_audit_pass": "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS" in text,
        "detailed_placement_runtime_present": dpl_runtime is not None,
    }
    passed = all(checks.values())
    payload = {
        "schema_version": 1,
        "variant": "B9",
        "stage": "placement_numeric_analysis",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": "PASS" if passed else "FAIL",
        "checks": checks,
        "inputs": {
            "placement_manifest": {
                "path": str(args.placement_manifest),
                "bytes": args.placement_manifest.stat().st_size,
                "sha256": sha256(args.placement_manifest),
            },
            "placement_log": {
                "path": str(args.log),
                "bytes": args.log.stat().st_size,
                "sha256": sha256(args.log),
            },
        },
        "metrics": {
            "locked_anchor_targets_before": 2,
            "locked_anchor_targets_after": 9,
            "added_anchor_targets": 7,
            "drc_penalty": 100,
            "anchors_verified": len(verified),
            "existing_anchors_verified": len(existing),
            "added_anchors_verified": len(added),
            "negotiation_initial_violations": int(initial_violations) if initial_violations else None,
            "negotiation_pre_mirroring_remaining_violations": int(remaining_violations) if remaining_violations else None,
            "detailed_placement_runtime_seconds": float(dpl_runtime) if dpl_runtime else None,
            "placement_violations": 0 if legality == "" else None,
            "elapsed_wall": elapsed,
            "peak_rss_kib": int(peak_rss) if peak_rss else None,
        },
        "authorizes": ["B9_TARGETED_PLACEMENT_REOPEN_AUDIT"] if passed else [],
        "next_stage": "B9_TARGETED_PLACEMENT_REOPEN_AUDIT" if passed else None,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2)
        stream.write("\n")
    print(
        f"WBQ_B9_PLACEMENT_NUMERIC_ANALYSIS {payload['status']} "
        f"anchors={len(verified)} initial={initial_violations} remaining={remaining_violations}"
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
