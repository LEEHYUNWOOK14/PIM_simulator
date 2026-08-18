#!/usr/bin/env python3
"""Compare two OpenROAD snapshots without issuing an automatic kill verdict."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def artifact_map(snapshot: dict) -> dict[str, dict]:
    progress = snapshot.get("progress_artifacts", {})
    items = [progress.get("log", {})] + list(progress.get("artifacts", []))
    return {item.get("path", f"unknown-{index}"): item for index, item in enumerate(items)}


def thread_map(snapshot: dict) -> dict[int, dict]:
    return {int(item["tid"]): item for item in snapshot.get("compute", {}).get("threads", [])}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--first", type=Path, required=True)
    parser.add_argument("--second", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite snapshot comparison: {args.output}")
    first = load(args.first)
    second = load(args.second)
    for field in ("variant", "stage", "service"):
        if first.get(field) != second.get(field):
            raise ValueError(f"snapshot {field} mismatch: {first.get(field)!r} != {second.get(field)!r}")
    first_pid = first.get("compute", {}).get("pid")
    second_pid = second.get("compute", {}).get("pid")
    if first_pid != second_pid:
        raise ValueError(f"compute PID changed: {first_pid} != {second_pid}")

    cpu_delta = second["compute"]["cpu_seconds"] - first["compute"]["cpu_seconds"]
    io_keys = sorted(set(first["compute"].get("io", {})) | set(second["compute"].get("io", {})))
    io_delta = {
        key: second["compute"].get("io", {}).get(key, 0) - first["compute"].get("io", {}).get(key, 0)
        for key in io_keys
    }
    first_artifacts = artifact_map(first)
    second_artifacts = artifact_map(second)
    artifact_delta = []
    for path in sorted(set(first_artifacts) | set(second_artifacts)):
        before = first_artifacts.get(path, {})
        after = second_artifacts.get(path, {})
        artifact_delta.append(
            {
                "path": path,
                "exists_before": before.get("exists", False),
                "exists_after": after.get("exists", False),
                "bytes_before": before.get("bytes", 0),
                "bytes_after": after.get("bytes", 0),
                "bytes_delta": after.get("bytes", 0) - before.get("bytes", 0),
                "mtime_changed": before.get("mtime_epoch") != after.get("mtime_epoch"),
            }
        )
    first_threads = thread_map(first)
    second_threads = thread_map(second)
    common_tids = sorted(set(first_threads) & set(second_threads))
    thread_comparison = []
    for tid in common_tids:
        before = first_threads[tid]
        after = second_threads[tid]
        before_ticks = (before.get("utime_ticks") or 0) + (before.get("stime_ticks") or 0)
        after_ticks = (after.get("utime_ticks") or 0) + (after.get("stime_ticks") or 0)
        thread_comparison.append(
            {
                "tid": tid,
                "cpu_ticks_delta": after_ticks - before_ticks,
                "state_same": before.get("state") == after.get("state"),
                "wchan_same": before.get("wchan") == after.get("wchan"),
                "kernel_stack_same": before.get("kernel_stack") == after.get("kernel_stack"),
                "state_before": before.get("state"),
                "state_after": after.get("state"),
                "wchan_before": before.get("wchan"),
                "wchan_after": after.get("wchan"),
            }
        )
    output_progress = any(item["bytes_delta"] != 0 or item["mtime_changed"] for item in artifact_delta)
    io_progress = any(value > 0 for key, value in io_delta.items() if key in {"rchar", "wchar", "read_bytes", "write_bytes"})
    thread_cpu_progress = any(item["cpu_ticks_delta"] > 0 for item in thread_comparison)
    same_wait_signature = bool(thread_comparison) and all(
        item["state_same"] and item["wchan_same"] and item["kernel_stack_same"] for item in thread_comparison
    )
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": first["variant"],
        "stage": first["stage"],
        "service": first["service"],
        "compute_pid": first_pid,
        "first_snapshot": str(args.first),
        "second_snapshot": str(args.second),
        "cpu_seconds_delta": cpu_delta,
        "io_delta": io_delta,
        "artifact_delta": artifact_delta,
        "thread_comparison": thread_comparison,
        "progress_indicators": {
            "cpu_time_advanced": cpu_delta > 0,
            "thread_cpu_advanced": thread_cpu_progress,
            "io_advanced": io_progress,
            "log_or_artifact_advanced": output_progress,
            "all_common_thread_wait_signatures_unchanged": same_wait_signature,
        },
        "no_observed_progress_across_two_snapshots": not (cpu_delta > 0 or io_progress or output_progress or thread_cpu_progress),
        "termination_authorized": False,
        "decision_boundary": (
            "This comparison never declares PATHOLOGICAL_STALL by itself. Confirm unchanged stage/core stacks, "
            "resource safety, source-level complexity or deadlock evidence, and a justified stage-budget overrun first."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        "OPENROAD_STAGE_SNAPSHOT_COMPARE PASS "
        f"cpu_seconds_delta={cpu_delta:.2f} io_advanced={io_progress} artifact_advanced={output_progress} "
        f"termination_authorized={payload['termination_authorized']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
