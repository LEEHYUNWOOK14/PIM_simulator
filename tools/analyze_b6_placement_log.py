#!/usr/bin/env python3
"""Create compact numeric evidence from the completed B6 placement log."""

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
    iteration_ids = [int(value) for value in re.findall(r"Routability iteration: (\d+)", text)]
    weighted = [
        float(value)
        for value in re.findall(
            r"Routability iteration weighted routing congestion: ([-+0-9.eE]+)", text
        )
    ]
    overflow = [
        float(value)
        for value in re.findall(r"Total overflow:\s+([-+0-9.eE]+)", text)
    ]
    locked = re.findall(
        r"^WBQ_B6_ANCHOR_LOCKED name=\{(.+?)\} origin_dbu=\{(\d+) (\d+)\} orient=\{(\S+)\}$",
        text,
        re.MULTILINE,
    )
    verified = re.findall(
        r"^WBQ_B6_ANCHOR_VERIFIED name=\{(.+?)\} origin_dbu=\{(\d+) (\d+)\} "
        r"orient=\{(\S+)\} status=\{(\S+)\}$",
        text,
        re.MULTILINE,
    )
    legality = last(r"^WBQ_B6_PLACE_LEGALITY violations=\{(.*)\}$", text)
    exit_code = last(r"^WBQ_B6_PLACE_EXIT_CODE=(\d+)$", text)
    elapsed = last(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(\S+)", text)
    peak_rss = last(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    recorded_log = manifest.get("outputs", {}).get("log", {})
    checks = {
        "placement_manifest_pass": manifest.get("status") == "PASS",
        "log_hash_matches_manifest": recorded_log.get("sha256") == sha256(args.log),
        "exit_zero": exit_code == "0",
        "rudy_complete": "WBQ_B6_RUDY_GLOBAL_PLACEMENT PASS" in text,
        "post_rudy_checkpoint": "WBQ_B6_RUDY_CHECKPOINT PASS" in text,
        "post_legalize_checkpoint": "WBQ_B6_POST_LEGALIZE_CHECKPOINT PASS" in text,
        "final_place_token": "WBQ_B6_TARGETED_ANCHOR_PLACE PASS" in text,
        "two_locked_anchors": len(locked) == 2,
        "two_verified_locked_anchors": len(verified) == 2
        and all(item[4] == "LOCKED" for item in verified),
        "legal_placement": legality == "",
        "numeric_iteration_alignment": bool(iteration_ids)
        and len(iteration_ids) == len(weighted),
    }
    passed = all(checks.values())
    payload = {
        "schema_version": 1,
        "variant": "B6",
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
            "routability_iterations": len(iteration_ids),
            "iteration_ids": iteration_ids,
            "weighted_congestion": weighted,
            "weighted_congestion_initial": weighted[0] if weighted else None,
            "weighted_congestion_final": weighted[-1] if weighted else None,
            "weighted_congestion_minimum": min(weighted) if weighted else None,
            "total_overflow_samples": len(overflow),
            "total_overflow_initial": overflow[0] if overflow else None,
            "total_overflow_final": overflow[-1] if overflow else None,
            "anchors_locked": len(locked),
            "anchors_verified": len(verified),
            "placement_violations": 0 if legality == "" else None,
            "elapsed_wall": elapsed,
            "peak_rss_kib": int(peak_rss) if peak_rss else None,
        },
        "authorizes": ["B6_TARGETED_PLACEMENT_REOPEN_AUDIT"] if passed else [],
        "next_stage": "B6_TARGETED_PLACEMENT_REOPEN_AUDIT" if passed else None,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2)
        stream.write("\n")
    print(f"WBQ_B6_PLACEMENT_NUMERIC_ANALYSIS {payload['status']} iterations={len(iteration_ids)}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
