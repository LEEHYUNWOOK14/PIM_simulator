#!/usr/bin/env python3
"""Live monitor for OpenROAD repair_design verbose progress."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path


ROW = re.compile(
    rb"^\s*(\d+)\s*\|\s*([+-]?[0-9.]+%)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$",
    re.MULTILINE,
)


def cpu_seconds(pid: int) -> float | None:
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().split()
        ticks = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        return (int(fields[13]) + int(fields[14])) / ticks
    except (FileNotFoundError, ProcessLookupError):
        return None


def process_state(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/stat").read_text().split()[2]
    except (FileNotFoundError, ProcessLookupError):
        return "exited"


def latest_row(path: Path) -> tuple[int, str, int, int, int, int] | None:
    # The repair log is currently small. Reading it whole also avoids partial-line races.
    matches = list(ROW.finditer(path.read_bytes()))
    if not matches:
        return None
    m = matches[-1]
    return (
        int(m[1]), m[2].decode(), int(m[3]), int(m[4]), int(m[5]), int(m[6])
    )


def duration(seconds: float | None) -> str:
    if seconds is None or seconds < 0 or seconds == float("inf"):
        return "--"
    seconds = int(seconds)
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    prefix = f"{days}d " if days else ""
    return f"{prefix}{hours:02d}:{minutes:02d}:{seconds:02d}"


def bar(value: float, width: int) -> str:
    filled = round(width * min(100.0, max(0.0, value)) / 100.0)
    return "█" * filled + "░" * (width - filled)


def sparkline(values: list[float], width: int) -> str:
    blocks = "▁▂▃▄▅▆▇█"
    values = values[-width:]
    ceiling = max(values, default=0.0)
    if ceiling <= 0:
        return blocks[0] * len(values)
    return "".join(blocks[min(7, int(value / ceiling * 7))] for value in values)


def dashboard(data: dict[str, object]) -> str:
    width = max(10, min(79, shutil.get_terminal_size((100, 24)).columns - 17))
    status = str(data["status"])
    status_mark = {
        "advancing": "\033[32m● ADVANCING\033[0m",
        "CPU active; counter stalled": "\033[33m● CPU ACTIVE / COUNTER STALLED\033[0m",
        "idle/stalled": "\033[31m● IDLE / STALLED\033[0m",
    }[status]
    percent = float(data["percent"])
    trend = sparkline(list(data["rates"]), min(50, width))
    return "\n".join([
        "\033[1mOpenROAD repair_design — live dashboard\033[0m",
        f'{data["stamp"]}    PID state: {data["state"]}    {status_mark}', "",
        f"[{bar(percent, width)}] {percent:6.2f}%",
        f'Processed  {int(data["iteration"]):>12,} / {int(data["total"]):,}',
        f'Remaining  {int(data["remaining"]):>12,}       ETA  {duration(data["eta"])}', "",
        f'Rate       {float(data["rate"]):>12,.1f} nets/s   CPU  {float(data["cpu"]):5.1f}%',
        f"Rate trend {trend or 'collecting samples...'}",
        f'Log age    {duration(float(data["age"])):>12}       Area {data["area"]}', "",
        f'Resized    {int(data["resized"]):>12,}',
        f'Buffers    {int(data["buffers"]):>12,}',
        f'Repaired   {int(data["repaired"]):>12,}', "",
        "Ctrl-C: close monitor only (OpenROAD keeps running)",
    ])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, default=301271)
    parser.add_argument(
        "--log",
        type=Path,
        default=Path(
            "/home/forstobpim/OpenROAD-flow-scripts/flow/logs/sky130hd/"
            "normalization_hbm_wbq/base/3_4_place_resized.tmp.log"
        ),
    )
    parser.add_argument("--interval", type=float, default=5.0)
    parser.add_argument("--window", type=float, default=300.0,
                        help="Rate window in seconds (default: 300)")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--plain", action="store_true",
                        help="Print lines instead of an updating dashboard")
    args = parser.parse_args()

    samples: deque[tuple[float, int]] = deque()
    previous_cpu = cpu_seconds(args.pid)
    previous_wall = time.monotonic()
    rate_history: deque[float] = deque(maxlen=60)
    interactive = sys.stdout.isatty() and not args.plain and not args.once

    try:
      while True:
        now = time.monotonic()
        row = latest_row(args.log)
        current_cpu = cpu_seconds(args.pid)
        state = process_state(args.pid)
        if row is None:
            print("No repair_design progress row found", flush=True)
            return 2

        iteration, area, resized, buffers, repaired, remaining = row
        total = iteration + remaining
        percent = iteration * 100.0 / total if total else 100.0
        samples.append((now, iteration))
        while len(samples) > 1 and now - samples[0][0] > args.window:
            samples.popleft()
        elapsed = samples[-1][0] - samples[0][0]
        rate = ((samples[-1][1] - samples[0][1]) / elapsed) if elapsed > 0 else 0.0
        eta = remaining / rate if rate > 0 else None
        rate_history.append(rate)

        cpu_rate = 0.0
        if current_cpu is not None and previous_cpu is not None and now > previous_wall:
            cpu_rate = (current_cpu - previous_cpu) / (now - previous_wall) * 100.0
        previous_cpu, previous_wall = current_cpu, now

        age = time.time() - args.log.stat().st_mtime
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        status = "advancing" if rate > 0 else ("CPU active; counter stalled" if cpu_rate > 5 else "idle/stalled")
        if interactive:
            data = dict(stamp=stamp, state=state, status=status, percent=percent,
                        iteration=iteration, total=total, remaining=remaining,
                        rate=rate, eta=eta, cpu=cpu_rate, rates=rate_history,
                        age=age, area=area, resized=resized, buffers=buffers,
                        repaired=repaired)
            print(f"\033[2J\033[H{dashboard(data)}", end="", flush=True)
        else:
            line = (
                f"{stamp}  {iteration:,}/{total:,} ({percent:6.2f}%)  "
                f"remaining={remaining:,}  rate={rate:,.1f} net/s  ETA={duration(eta)}  "
                f"area={area} resized={resized:,} buffers={buffers:,} repaired={repaired:,}  "
                f"log_age={duration(age)} CPU={cpu_rate:5.1f}% state={state} [{status}]"
            )
            print(line, flush=True)
        if args.once or state == "exited":
            return 0
        time.sleep(args.interval)
    except KeyboardInterrupt:
        if interactive:
            print("\nMonitor closed; OpenROAD was not stopped.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
