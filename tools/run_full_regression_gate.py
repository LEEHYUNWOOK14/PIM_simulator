#!/usr/bin/env python3
"""Run the project regression manifest and emit machine-readable evidence."""
from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def resolve_command(command: list[str]) -> list[str]:
    if command and command[0] == "python":
        return [sys.executable, *command[1:]]
    return command


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--manifest", type=Path, default=Path("verification/reproducibility/regression_manifest.json"))
    parser.add_argument("--output-dir", type=Path, default=Path("reports/reproducibility"))
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = (root / args.manifest).resolve() if not args.manifest.is_absolute() else args.manifest.resolve()
    output_dir = (root / args.output_dir).resolve() if not args.output_dir.is_absolute() else args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    results = []
    for item in manifest["commands"]:
        command = resolve_command(item["command"])
        started = time.monotonic()
        started_at = datetime.now(timezone.utc).isoformat()
        executable = shutil.which(command[0])
        if executable is None:
            results.append({"id": item["id"], "category": item["category"],
                            "required": item.get("required", True), "status": "BLOCKED_TOOL_UNAVAILABLE",
                            "command": command, "started_at": started_at, "duration_s": 0.0,
                            "exit_code": None, "output": f"executable not found: {command[0]}"})
            continue
        try:
            completed = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, timeout=args.timeout,
                                       env=os.environ.copy())
            status = "PASS" if completed.returncode == 0 else "FAIL"
            output = completed.stdout
            code = completed.returncode
            if status == "PASS" and any(marker in output for marker in ("result=FAIL", "REGRESSION FAIL", "ASSERTION FAILED")):
                status = "FAIL_SEMANTIC_MARKER"
        except subprocess.TimeoutExpired as exc:
            status, output, code = "FAIL_TIMEOUT", (exc.stdout or "") + "\nTIMEOUT\n", None
        results.append({"id": item["id"], "category": item["category"],
                        "required": item.get("required", True), "status": status,
                        "command": command, "started_at": started_at,
                        "duration_s": round(time.monotonic() - started, 3),
                        "exit_code": code, "output": output})
        print(f"{item['id']}: {status}")
    overall = "PASS" if all(r["status"] == "PASS" for r in results if r["required"]) else "FAIL"
    result_json = output_dir / f"regression_gate_{run_id}.json"
    result_csv = output_dir / f"regression_gate_{run_id}.csv"
    payload = {"gate_version": 1, "run_id": run_id, "started_at": results[0]["started_at"] if results else None,
               "overall_status": overall, "manifest": str(manifest_path.relative_to(root)).replace("\\", "/"),
               "results": results}
    result_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    with result_csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["id", "category", "required", "status", "duration_s", "exit_code"])
        writer.writeheader()
        writer.writerows({k: row.get(k) for k in writer.fieldnames} for row in results)
    print(f"FULL_REGRESSION_GATE {overall} json={result_json} csv={result_csv}")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
