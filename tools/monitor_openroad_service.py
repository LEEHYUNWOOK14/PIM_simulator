#!/usr/bin/env python3
"""Read-only heartbeat and silence diagnostics for one OpenROAD systemd service."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "tools/capture_openroad_stage_snapshot.py"
COMPARE = ROOT / "tools/compare_openroad_stage_snapshots.py"


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        return None


def parse_values(text: str | None, separator: str = ":") -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (text or "").splitlines():
        if separator in line:
            key, value = line.split(separator, 1)
            values[key.strip()] = value.strip()
    return values


def service_state(service: str) -> dict[str, str]:
    completed = subprocess.run(
        [
            "systemctl", "--user", "show", service,
            "-p", "LoadState", "-p", "ActiveState", "-p", "SubState",
            "-p", "MainPID", "-p", "ControlGroup", "-p", "ExecMainStatus", "-p", "Result",
        ],
        check=False,
        text=True,
        capture_output=True,
        timeout=15,
    )
    values = parse_values(completed.stdout, separator="=")
    values["query_exit_code"] = str(completed.returncode)
    return values


def cgroup_pids(control_group: str) -> list[int]:
    if not control_group.startswith("/") or ".." in Path(control_group).parts:
        return []
    root = Path("/sys/fs/cgroup") / control_group.lstrip("/")
    pids: set[int] = set()
    for path in [root, *root.glob("**/*")]:
        procs = path / "cgroup.procs" if path.is_dir() else None
        if procs is None:
            continue
        for value in (read_text(procs) or "").split():
            if value.isdigit():
                pids.add(int(value))
    return sorted(pids)


def proc_starttime(pid: int) -> int | None:
    text = read_text(Path("/proc") / str(pid) / "stat")
    if not text or ") " not in text:
        return None
    fields = text.rsplit(") ", 1)[1].split()
    return int(fields[19]) if len(fields) > 19 else None


def openroad_processes(control_group: str) -> list[dict]:
    processes = []
    for pid in cgroup_pids(control_group):
        proc = Path("/proc") / str(pid)
        raw = read_text(proc / "cmdline")
        if raw is None:
            continue
        command = [part for part in raw.split("\0") if part]
        if not command or Path(command[0]).name != "openroad":
            continue
        stage = next((Path(value).stem for value in reversed(command) if value.endswith(".tcl")), "unknown")
        processes.append({"pid": pid, "starttime_ticks": proc_starttime(pid), "stage": stage, "command": command})
    return processes


def stat_item(path: Path, now: float) -> dict:
    try:
        info = path.stat()
    except FileNotFoundError:
        return {"path": str(path), "exists": False, "bytes": 0, "mtime_epoch": None, "age_seconds": None}
    return {
        "path": str(path),
        "exists": True,
        "bytes": info.st_size,
        "mtime_epoch": info.st_mtime,
        "age_seconds": max(0.0, now - info.st_mtime),
    }


def heartbeat(process: dict | None, log: Path, artifacts: list[Path], state: dict[str, str]) -> dict:
    current = time.time()
    payload = {
        "captured_at_utc": now_utc(),
        "service_state": state,
        "compute": process,
        "log": stat_item(log, current),
        "artifacts": [stat_item(path, current) for path in artifacts],
    }
    if process is None:
        return payload
    proc = Path("/proc") / str(process["pid"])
    payload["compute"] = {
        **process,
        "status": parse_values(read_text(proc / "status")),
        "io": parse_values(read_text(proc / "io")),
        "stat": read_text(proc / "stat"),
        "thread_count": len(list((proc / "task").glob("[0-9]*"))),
    }
    return payload


def append_json(path: Path, payload: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def run_checked(command: list[str]) -> None:
    completed = subprocess.run(command, check=False, text=True, capture_output=True, timeout=120)
    if completed.returncode != 0:
        raise RuntimeError(
            f"diagnostic command failed rc={completed.returncode}: {' '.join(command)}\n{completed.stderr}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--service", required=True)
    parser.add_argument("--variant", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--interval-seconds", type=int, default=120)
    parser.add_argument("--warning-seconds", type=int, default=900)
    parser.add_argument("--diagnosis-seconds", type=int, default=1800)
    parser.add_argument("--followup-seconds", type=int, default=600)
    args = parser.parse_args()
    if not 60 <= args.interval_seconds <= 300:
        raise ValueError("interval must be between 60 and 300 seconds")
    if args.warning_seconds >= args.diagnosis_seconds or args.followup_seconds < 600:
        raise ValueError("silence thresholds violate the 15m/30m/10m minimum contract")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    invocation = args.output_dir / "monitor_invocation.json"
    heartbeats = args.output_dir / "heartbeats.jsonl"
    events = args.output_dir / "events.jsonl"
    for path in (invocation, heartbeats, events):
        if path.exists():
            raise FileExistsError(f"refusing to overwrite monitor evidence: {path}")
    invocation.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "started_at_utc": now_utc(),
                "service": args.service,
                "variant": args.variant,
                "log": str(args.log),
                "artifacts": [str(path) for path in args.artifact],
                "interval_seconds": args.interval_seconds,
                "silence_warning_seconds": args.warning_seconds,
                "first_diagnosis_seconds": args.diagnosis_seconds,
                "followup_seconds": args.followup_seconds,
                "monitor_pid": os.getpid(),
                "tools": {
                    "monitor": {"path": str(Path(__file__).resolve()), "sha256": sha256(Path(__file__).resolve())},
                    "capture": {"path": str(CAPTURE), "sha256": sha256(CAPTURE)},
                    "compare": {"path": str(COMPARE), "sha256": sha256(COMPARE)},
                },
                "termination_authorized": False,
            },
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )

    identity: tuple[int, int | None, str] | None = None
    warned = False
    first_snapshot: Path | None = None
    first_snapshot_time: float | None = None
    while True:
        state = service_state(args.service)
        active = state.get("ActiveState") in {"active", "activating", "reloading"}
        processes = openroad_processes(state.get("ControlGroup", ""))
        process = processes[0] if len(processes) == 1 else None
        beat = heartbeat(process, args.log, args.artifact, state)
        beat["openroad_process_count"] = len(processes)
        if len(processes) != 1:
            beat["openroad_candidates"] = processes
        append_json(heartbeats, beat)
        if not active:
            append_json(events, {"captured_at_utc": now_utc(), "event": "SERVICE_TERMINAL", "service_state": state})
            return 0
        if process is not None:
            current_identity = (process["pid"], process["starttime_ticks"], process["stage"])
            if current_identity != identity:
                identity = current_identity
                warned = False
                first_snapshot = None
                first_snapshot_time = None
                append_json(events, {"captured_at_utc": now_utc(), "event": "COMPUTE_STAGE", "identity": identity})
            log_age = beat["log"].get("age_seconds")
            if log_age is not None and log_age >= args.warning_seconds and not warned:
                warned = True
                append_json(events, {"captured_at_utc": now_utc(), "event": "SILENCE_WARNING", "identity": identity, "log_age_seconds": log_age})
            if log_age is not None and log_age < args.warning_seconds:
                warned = False
                first_snapshot = None
                first_snapshot_time = None
            if log_age is not None and log_age >= args.diagnosis_seconds and first_snapshot is None:
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                first_snapshot = args.output_dir / f"snapshot_{process['pid']}_{process['stage']}_{stamp}_first.json"
                command = [
                    sys.executable, str(CAPTURE), "--stage", process["stage"], "--variant", args.variant,
                    "--service", args.service, "--compute-pid", str(process["pid"]), "--log", str(args.log),
                    "--output", str(first_snapshot),
                ]
                for artifact in args.artifact:
                    command.extend(["--artifact", str(artifact)])
                run_checked(command)
                first_snapshot_time = time.time()
                append_json(events, {"captured_at_utc": now_utc(), "event": "FIRST_DIAGNOSIS", "identity": identity, "snapshot": str(first_snapshot)})
            if (
                first_snapshot is not None and first_snapshot_time is not None
                and time.time() - first_snapshot_time >= args.followup_seconds
                and current_identity == identity
            ):
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                second = args.output_dir / f"snapshot_{process['pid']}_{process['stage']}_{stamp}_second.json"
                comparison = args.output_dir / f"comparison_{process['pid']}_{process['stage']}_{stamp}.json"
                command = [
                    sys.executable, str(CAPTURE), "--stage", process["stage"], "--variant", args.variant,
                    "--service", args.service, "--compute-pid", str(process["pid"]), "--log", str(args.log),
                    "--output", str(second),
                ]
                for artifact in args.artifact:
                    command.extend(["--artifact", str(artifact)])
                run_checked(command)
                run_checked([sys.executable, str(COMPARE), "--first", str(first_snapshot), "--second", str(second), "--output", str(comparison)])
                append_json(events, {"captured_at_utc": now_utc(), "event": "FOLLOWUP_DIAGNOSIS", "identity": identity, "snapshot": str(second), "comparison": str(comparison), "termination_authorized": False})
                first_snapshot = None
                first_snapshot_time = None
        time.sleep(args.interval_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
