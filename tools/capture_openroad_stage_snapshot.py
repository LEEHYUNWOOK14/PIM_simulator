#!/usr/bin/env python3
"""Capture one read-only OpenROAD progress snapshot for silence diagnosis."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        return None


def parse_key_values(text: str | None, separator: str = ":") -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (text or "").splitlines():
        if separator in line:
            key, value = line.split(separator, 1)
            values[key.strip()] = value.strip()
    return values


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


def parse_proc_stat(text: str | None) -> dict:
    if not text or ") " not in text:
        return {}
    _, fields_text = text.rsplit(") ", 1)
    fields = fields_text.split()
    if len(fields) < 22:
        return {}
    # fields[0] is Linux proc stat field 3 after removing pid/comm.
    return {
        "state": fields[0],
        "ppid": int(fields[1]),
        "utime_ticks": int(fields[11]),
        "stime_ticks": int(fields[12]),
        "cutime_ticks": int(fields[13]),
        "cstime_ticks": int(fields[14]),
        "num_threads": int(fields[17]),
        "starttime_ticks": int(fields[19]),
        "vsize_bytes": int(fields[20]),
        "rss_pages": int(fields[21]),
    }


def task_snapshot(task: Path) -> dict:
    tid = int(task.name)
    stat = parse_proc_stat(read_text(task / "stat"))
    wchan = (read_text(task / "wchan") or "").strip() or None
    stack = read_text(task / "stack")
    return {
        "tid": tid,
        "state": stat.get("state"),
        "utime_ticks": stat.get("utime_ticks"),
        "stime_ticks": stat.get("stime_ticks"),
        "wchan": wchan,
        "kernel_stack": stack.splitlines() if stack else None,
        "kernel_stack_available": stack is not None,
    }


def run_command(command: list[str]) -> dict:
    try:
        completed = subprocess.run(command, check=False, text=True, capture_output=True, timeout=15)
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        return {"command": command, "exit_code": None, "stdout": "", "stderr": str(error)}
    return {
        "command": command,
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def filesystem_snapshot(path: Path) -> dict:
    usage = shutil.disk_usage(path if path.exists() else path.parent)
    return {"path": str(path), "total_bytes": usage.total, "used_bytes": usage.used, "free_bytes": usage.free}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True)
    parser.add_argument("--variant", required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--compute-pid", type=int, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite diagnostic snapshot: {args.output}")

    proc = Path("/proc") / str(args.compute_pid)
    cmdline_text = read_text(proc / "cmdline")
    if cmdline_text is None:
        raise ProcessLookupError(f"compute PID does not exist: {args.compute_pid}")
    cmdline = [part for part in cmdline_text.split("\0") if part]
    executable = Path(cmdline[0]).name if cmdline else ""
    if executable != "openroad":
        raise ValueError(f"PID {args.compute_pid} is not the exact OpenROAD compute process: {cmdline}")

    now = datetime.now(timezone.utc)
    now_epoch = now.timestamp()
    status = parse_key_values(read_text(proc / "status"))
    io_values = parse_key_values(read_text(proc / "io"))
    proc_stat = parse_proc_stat(read_text(proc / "stat"))
    ticks_per_second = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
    cpu_ticks = sum(
        int(proc_stat.get(key, 0))
        for key in ("utime_ticks", "stime_ticks", "cutime_ticks", "cstime_ticks")
    )
    tasks = []
    task_root = proc / "task"
    try:
        tasks = [task_snapshot(path) for path in sorted(task_root.iterdir(), key=lambda value: int(value.name))]
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        tasks = []

    service_show = run_command(
        [
            "systemctl", "--user", "show", args.service,
            "-p", "ActiveState", "-p", "SubState", "-p", "MainPID", "-p", "ControlGroup",
            "-p", "ExecMainStatus", "-p", "Result",
        ]
    )
    payload = {
        "schema_version": 1,
        "captured_at_utc": now.isoformat(),
        "stage": args.stage,
        "variant": args.variant,
        "service": args.service,
        "service_state": parse_key_values(service_show["stdout"], separator="="),
        "service_command": service_show,
        "compute": {
            "pid": args.compute_pid,
            "cmdline": cmdline,
            "proc_stat": proc_stat,
            "cpu_ticks": cpu_ticks,
            "cpu_seconds": cpu_ticks / ticks_per_second,
            "clock_ticks_per_second": ticks_per_second,
            "status": status,
            "io": {key: int(value) for key, value in io_values.items() if value.isdigit()},
            "threads": tasks,
            "thread_count_captured": len(tasks),
            "kernel_stacks_available": sum(1 for task in tasks if task["kernel_stack_available"]),
        },
        "progress_artifacts": {
            "log": stat_item(args.log, now_epoch),
            "artifacts": [stat_item(path, now_epoch) for path in args.artifact],
        },
        "resources": {
            "meminfo": parse_key_values(read_text(Path("/proc/meminfo"))),
            "loadavg": (read_text(Path("/proc/loadavg")) or "").strip(),
            "filesystems": [
                filesystem_snapshot(Path("/dev/shm")),
                filesystem_snapshot(Path("/home/forstobpim")),
            ],
        },
        "diagnostic_boundary": (
            "Read-only snapshot only. PATHOLOGICAL_STALL requires a later comparison plus stage budget, "
            "source/stack evidence, and resource checks; this file alone never authorizes termination."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"OPENROAD_STAGE_SNAPSHOT PASS variant={args.variant} stage={args.stage} pid={args.compute_pid} "
        f"cpu_seconds={payload['compute']['cpu_seconds']:.2f} log_age_seconds={payload['progress_artifacts']['log']['age_seconds']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
