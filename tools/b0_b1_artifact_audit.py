#!/usr/bin/env python3
"""Freeze-safe B0/B1 artifact audit and comparison report generator.

The guarded experiment trees are never opened until a separate completion token
asserts that the producer exited successfully.  Capture then performs a metadata-
only stability check before hashing or parsing any artifact.  Comparisons consume
only the resulting snapshot JSON files, never live ORFS output.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import math
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


STATUS_PASS = "PASS"
STATUS_FAIL = "FAIL"
STATUS_PENDING = "PENDING"
STATUS_NOT_COMPARABLE = "NOT_COMPARABLE"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False, sort_keys=True)
        stream.write("\n")
    os.replace(temporary, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def group_digest(files: Iterable[dict[str, Any]]) -> str:
    # Paths deliberately do not participate: B0/B1 may store the same contract
    # under different directory names. Multiplicity and content both participate.
    hashes = sorted(item["sha256"] for item in files)
    digest = hashlib.sha256()
    for value in hashes:
        digest.update(value.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def load_profile(profile_path: Path) -> tuple[dict[str, Any], Path]:
    profile = read_json(profile_path)
    if profile.get("schema_version") != 1:
        raise ValueError("unsupported audit profile schema_version")
    configured_root = Path(profile.get("repository_root", "."))
    root = (profile_path.parent.parent / configured_root).resolve() if not configured_root.is_absolute() else configured_root.resolve()
    # The shipped profile lives in design/, so '.' means repository root rather
    # than the profile directory.
    if not (root / "design").is_dir() and (profile_path.parent.parent / "design").is_dir():
        root = profile_path.parent.parent.resolve()
    return profile, root


def resolve_profile_path(root: Path, path_text: str) -> Path:
    candidate = Path(path_text)
    return candidate.resolve() if candidate.is_absolute() else (root / candidate).resolve()


def pending_snapshot(experiment: str, reason: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "experiment": experiment,
        "captured_at": utc_now(),
        "status": STATUS_PENDING,
        "reasons": [reason],
        "comparison_context": {},
        "groups": {},
        "artifacts": [],
        "metrics": {},
    }


def validate_completion_token(token: dict[str, Any], experiment: str) -> list[str]:
    errors: list[str] = []
    if token.get("status") != "COMPLETE":
        errors.append("completion token status must be COMPLETE")
    if str(token.get("experiment_id", "")).lower() != experiment.lower():
        errors.append(f"completion token experiment_id must be {experiment}")
    if token.get("producer_exit_code") != 0:
        errors.append("producer_exit_code must be 0")
    context = token.get("comparison_context")
    if not isinstance(context, dict):
        errors.append("comparison_context must be an object")
    return errors


def file_metadata(path: Path) -> tuple[int, int]:
    stat = path.stat()
    return stat.st_size, stat.st_mtime_ns


def collect_declared_paths(profile: dict[str, Any], experiment_spec: dict[str, Any]) -> tuple[dict[str, list[str]], list[str]]:
    groups: dict[str, list[str]] = {}
    for name, group in experiment_spec.get("groups", {}).items():
        if "paths_from" in group:
            values = profile.get(group["paths_from"], [])
        else:
            values = group.get("paths", [])
        groups[name] = list(values)
    other = list(experiment_spec.get("required_artifacts", [])) + list(experiment_spec.get("metric_sources", []))
    return groups, list(dict.fromkeys(other))


def stability_gate(paths: list[Path], token_path: Path, settle_seconds: float, min_age_seconds: float) -> list[str]:
    errors: list[str] = []
    token_mtime = token_path.stat().st_mtime_ns
    first: dict[Path, tuple[int, int]] = {}
    now_ns = time.time_ns()
    for path in paths:
        if not path.is_file():
            continue
        metadata = file_metadata(path)
        first[path] = metadata
        if metadata[1] > token_mtime:
            errors.append(f"changed after completion token: {path}")
        age_seconds = (now_ns - metadata[1]) / 1_000_000_000
        if age_seconds < min_age_seconds:
            errors.append(f"too new for stable snapshot ({age_seconds:.2f}s): {path}")
    if errors:
        return errors
    if settle_seconds > 0:
        time.sleep(settle_seconds)
    for path, metadata in first.items():
        if not path.is_file() or file_metadata(path) != metadata:
            errors.append(f"changed during stability window: {path}")
    return errors


def normalize_evidence(raw: str) -> str:
    value = raw.strip().upper()
    if "ROUT" in value:
        return "ROUTED"
    if "PLAC" in value or "OPENROAD" in value:
        return "PLACED"
    if "YOSYS" in value or "SYNTH" in value:
        return "SYNTHESIZED"
    if "RTL" in value or "SIM" in value:
        return "RTL_SIMULATED"
    if "ESTIM" in value or "ASSUM" in value:
        return "ESTIMATED"
    if "MODEL" in value:
        return "MODELED"
    if "DERIV" in value:
        return "DERIVED"
    return "MEASURED"


def metric_lookup(metric_contract: dict[str, Any]) -> dict[str, str]:
    aliases: dict[str, str] = {}
    for canonical, spec in metric_contract["metrics"].items():
        aliases[canonical.lower()] = canonical
        for alias in spec.get("aliases", []):
            aliases[alias.lower()] = canonical
    return aliases


def parse_metrics(paths: list[Path], contract: dict[str, Any], root: Path) -> tuple[dict[str, Any], list[str]]:
    found: dict[str, Any] = {}
    errors: list[str] = []
    aliases = metric_lookup(contract)
    for path in paths:
        if not path.is_file():
            continue
        try:
            with path.open("r", encoding="utf-8-sig", newline="") as stream:
                reader = csv.DictReader(stream)
                if not reader.fieldnames or not {"metric", "value", "unit"}.issubset(reader.fieldnames):
                    errors.append(f"invalid metric CSV header: {path}")
                    continue
                for row in reader:
                    canonical = aliases.get(str(row.get("metric", "")).strip().lower())
                    if canonical is None:
                        continue
                    try:
                        value = float(str(row.get("value", "")).strip())
                    except ValueError:
                        errors.append(f"non-numeric metric {canonical}: {path}")
                        continue
                    if not math.isfinite(value):
                        errors.append(f"non-finite metric {canonical}: {path}")
                        continue
                    expected_unit = contract["metrics"][canonical]["unit"]
                    metric_spec = contract["metrics"][canonical]
                    unit = str(row.get("unit", "")).strip()
                    if unit != expected_unit:
                        errors.append(f"unit mismatch for {canonical}: expected {expected_unit}, got {unit or '<empty>'}")
                        continue
                    if "valid_exclusive_min" in metric_spec and value <= metric_spec["valid_exclusive_min"]:
                        errors.append(f"metric outside valid range {canonical}: {value}")
                        continue
                    if "valid_min" in metric_spec and value < metric_spec["valid_min"]:
                        errors.append(f"metric outside valid range {canonical}: {value}")
                        continue
                    if "valid_max" in metric_spec and value > metric_spec["valid_max"]:
                        errors.append(f"metric outside valid range {canonical}: {value}")
                        continue
                    if "pass_max" in metric_spec and value > metric_spec["pass_max"]:
                        errors.append(f"metric gate failed {canonical}: {value} > {metric_spec['pass_max']}")
                    if canonical in found:
                        errors.append(f"duplicate metric {canonical}: {path}")
                        continue
                    found[canonical] = {
                        "name": canonical,
                        "value": value,
                        "unit": unit,
                        "evidence": normalize_evidence(str(row.get("evidence", "MEASURED"))),
                        "source": path.relative_to(root).as_posix(),
                    }
        except (OSError, UnicodeError, csv.Error) as exc:
            errors.append(f"cannot parse metric CSV {path}: {exc}")
    for name, spec in contract["metrics"].items():
        if spec.get("required") and name not in found:
            errors.append(f"missing required metric: {name}")
    return found, errors


def capture(profile_path: Path, experiment: str, output: Path, settle_seconds: float, min_age_seconds: float) -> dict[str, Any]:
    profile, root = load_profile(profile_path)
    experiment = experiment.lower()
    if experiment not in profile.get("experiments", {}):
        raise ValueError(f"unknown experiment: {experiment}")
    spec = profile["experiments"][experiment]
    token_path = resolve_profile_path(root, spec["completion_token"])

    # Critical invariant: without the independent token, do not enumerate, open,
    # hash, or parse anything under the experiment result tree.
    if not token_path.is_file():
        snapshot = pending_snapshot(experiment, f"completion token absent: {spec['completion_token']}")
        write_json(output, snapshot)
        return snapshot

    token = read_json(token_path)
    token_errors = validate_completion_token(token, experiment)
    if token_errors:
        snapshot = pending_snapshot(experiment, "; ".join(token_errors))
        write_json(output, snapshot)
        return snapshot

    groups, other_paths = collect_declared_paths(profile, spec)
    all_text_paths = list(dict.fromkeys(path for values in groups.values() for path in values) | dict.fromkeys(other_paths))
    resolved = {text: resolve_profile_path(root, text) for text in all_text_paths}
    missing = [text for text, path in resolved.items() if not path.is_file() or path.stat().st_size == 0]
    stability_errors = stability_gate([path for path in resolved.values() if path.is_file()], token_path, settle_seconds, min_age_seconds)
    if stability_errors:
        snapshot = {
            **pending_snapshot(experiment, "snapshot stability gate failed"),
            "reasons": stability_errors,
        }
        write_json(output, snapshot)
        return snapshot

    captured_groups: dict[str, Any] = {}
    for group_name, path_texts in groups.items():
        entries = []
        for text in path_texts:
            path = resolved[text]
            if path.is_file() and path.stat().st_size > 0:
                entries.append({"path": text, "size": path.stat().st_size, "sha256": sha256_file(path)})
        captured_groups[group_name] = {"digest": group_digest(entries), "files": entries, "complete": len(entries) == len(path_texts)}

    artifact_entries = []
    for text in spec.get("required_artifacts", []):
        path = resolved[text]
        if path.is_file() and path.stat().st_size > 0:
            artifact_entries.append({"path": text, "size": path.stat().st_size, "sha256": sha256_file(path)})

    metric_contract_path = resolve_profile_path(root, profile["metric_schema"])
    metric_contract = read_json(metric_contract_path)
    metric_paths = [resolved[text] for text in spec.get("metric_sources", [])]
    metrics, metric_errors = parse_metrics(metric_paths, metric_contract, root)
    reasons = [f"missing or empty artifact: {text}" for text in missing] + metric_errors
    snapshot = {
        "schema_version": 1,
        "experiment": experiment,
        "captured_at": utc_now(),
        "completion_token_sha256": sha256_file(token_path),
        "status": STATUS_FAIL if reasons else STATUS_PASS,
        "reasons": reasons,
        "comparison_context": token.get("comparison_context", {}),
        "groups": captured_groups,
        "artifacts": artifact_entries,
        "metrics": metrics,
    }
    write_json(output, snapshot)
    return snapshot


def placeholder_snapshot(experiment: str, path: Path) -> dict[str, Any]:
    if not path.is_file():
        return pending_snapshot(experiment, f"snapshot absent: {path}")
    return read_json(path)


def compare_snapshots(profile_path: Path, b0_path: Path, b1_path: Path) -> dict[str, Any]:
    profile, root = load_profile(profile_path)
    contract = read_json(resolve_profile_path(root, profile["metric_schema"]))
    b0 = placeholder_snapshot("b0", b0_path)
    b1 = placeholder_snapshot("b1", b1_path)
    reasons: list[str] = []

    if STATUS_PENDING in {b0.get("status"), b1.get("status")}:
        reasons.extend([f"{name}: {reason}" for name, snap in (("b0", b0), ("b1", b1)) for reason in snap.get("reasons", [])])
        status = STATUS_PENDING
        comparable = False
    elif STATUS_FAIL in {b0.get("status"), b1.get("status")}:
        reasons.extend([f"{name}: {reason}" for name, snap in (("b0", b0), ("b1", b1)) for reason in snap.get("reasons", [])])
        status = STATUS_FAIL
        comparable = False
    else:
        for key in profile.get("comparison_keys", []):
            left = b0.get("comparison_context", {}).get(key)
            right = b1.get("comparison_context", {}).get(key)
            if left is None or right is None:
                reasons.append(f"comparison context missing: {key}")
            elif left != right:
                reasons.append(f"comparison context mismatch {key}: b0={left!r}, b1={right!r}")
        for group in profile.get("equal_digest_groups", []):
            left = b0.get("groups", {}).get(group, {})
            right = b1.get("groups", {}).get(group, {})
            if not left.get("complete") or not right.get("complete"):
                reasons.append(f"incomplete hash group: {group}")
            elif left.get("digest") != right.get("digest"):
                reasons.append(f"hash mismatch: {group}")
        comparable = not reasons
        status = STATUS_PASS if comparable else STATUS_NOT_COMPARABLE

    rows: list[dict[str, Any]] = []
    for name, spec in contract["metrics"].items():
        left_record = b0.get("metrics", {}).get(name)
        right_record = b1.get("metrics", {}).get(name)
        left = left_record.get("value") if isinstance(left_record, dict) else None
        right = right_record.get("value") if isinstance(right_record, dict) else None
        row_status = STATUS_PASS if comparable and left is not None and right is not None else (STATUS_PENDING if status == STATUS_PENDING or left is None or right is None else STATUS_NOT_COMPARABLE)
        delta = right - left if row_status == STATUS_PASS else None
        delta_pct = (delta / left * 100.0) if row_status == STATUS_PASS and left != 0 else None
        rows.append({"name": name, "unit": spec["unit"], "status": row_status, "b0": left, "b1": right, "delta": delta, "delta_pct": delta_pct})

    return {
        "schema_version": 1,
        "generated_at": utc_now(),
        "status": status,
        "comparable": comparable,
        "reasons": reasons,
        "experiments": {"b0": {"status": b0.get("status"), "snapshot": str(b0_path)}, "b1": {"status": b1.get("status"), "snapshot": str(b1_path)}},
        "metrics": rows,
    }


def format_number(value: Any) -> str:
    if value is None:
        return "—"
    return f"{value:,.4g}"


def render_html(result: dict[str, Any], path: Path) -> None:
    reasons = "".join(f"<li>{html.escape(reason)}</li>" for reason in result["reasons"]) or "<li>None</li>"
    table_rows = []
    charts = []
    for row in result["metrics"]:
        delta_pct = "—" if row["delta_pct"] is None else f"{row['delta_pct']:+.2f}%"
        table_rows.append(
            "<tr>" + "".join(f"<td>{html.escape(str(value))}</td>" for value in (
                row["name"], row["status"], format_number(row["b0"]), format_number(row["b1"]),
                format_number(row["delta"]), delta_pct, row["unit"],
            )) + "</tr>"
        )
        if row["b0"] is not None and row["b1"] is not None:
            scale = max(abs(row["b0"]), abs(row["b1"]), 1e-30)
            b0_width = max(1, int(abs(row["b0"]) / scale * 240))
            b1_width = max(1, int(abs(row["b1"]) / scale * 240))
            charts.append(
                f"<section class='chart'><h3>{html.escape(row['name'])} <small>{html.escape(row['unit'])}</small></h3>"
                f"<div><span>B0</span><i class='b0' style='width:{b0_width}px'></i>{format_number(row['b0'])}</div>"
                f"<div><span>B1</span><i class='b1' style='width:{b1_width}px'></i>{format_number(row['b1'])}</div></section>"
            )
        else:
            charts.append(f"<section class='chart pending'><h3>{html.escape(row['name'])}</h3><p>PENDING — metric not available</p></section>")
    document = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><title>B0/B1 Baseline Comparison</title>
<style>body{{font:14px system-ui;margin:32px;color:#172033;background:#f6f8fb}}main{{max-width:1100px;margin:auto}}.hero,.panel,.chart{{background:white;border:1px solid #dce2ea;border-radius:10px;padding:18px;margin:14px 0}}.status{{font-size:28px;font-weight:700}}table{{width:100%;border-collapse:collapse;background:white}}th,td{{padding:9px;border-bottom:1px solid #e5e9ef;text-align:right}}th:first-child,td:first-child{{text-align:left}}.chart div{{display:flex;align-items:center;gap:10px;margin:7px 0}}.chart span{{width:28px}}.chart i{{display:inline-block;height:14px;border-radius:3px}}.b0{{background:#4d7cff}}.b1{{background:#f59e42}}.pending{{color:#6b7280}}small{{font-weight:400;color:#6b7280}}</style></head>
<body><main><section class="hero"><h1>B0/B1 Artifact Audit Comparison</h1><div class="status">{html.escape(result['status'])}</div><p>Comparable: {str(result['comparable']).lower()}</p></section>
<section class="panel"><h2>Comparison gate</h2><ul>{reasons}</ul></section>
<section class="panel"><h2>Metrics</h2><table><thead><tr><th>Metric</th><th>Status</th><th>B0</th><th>B1</th><th>B1−B0</th><th>Delta %</th><th>Unit</th></tr></thead><tbody>{''.join(table_rows)}</tbody></table></section>
<section><h2>Charts</h2>{''.join(charts)}</section></main></body></html>"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(document, encoding="utf-8", newline="\n")


def write_comparison_csv(result: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["name", "status", "b0", "b1", "delta", "delta_pct", "unit"])
        writer.writeheader()
        writer.writerows(result["metrics"])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, default=Path("design/b0_b1_artifact_audit_profile.json"))
    subparsers = parser.add_subparsers(dest="command", required=True)
    capture_parser = subparsers.add_parser("capture", help="capture one completed experiment into an immutable JSON snapshot")
    capture_parser.add_argument("experiment", choices=["b0", "b1"])
    capture_parser.add_argument("--output", type=Path)
    capture_parser.add_argument("--settle-seconds", type=float, default=2.0)
    capture_parser.add_argument("--min-age-seconds", type=float, default=5.0)
    compare_parser = subparsers.add_parser("compare", help="compare snapshot JSON files and generate JSON/CSV/HTML")
    compare_parser.add_argument("--b0", type=Path, default=Path("reports/b0_b1_artifact_audit/snapshots/b0.json"))
    compare_parser.add_argument("--b1", type=Path, default=Path("reports/b0_b1_artifact_audit/snapshots/b1.json"))
    compare_parser.add_argument("--json", type=Path, default=Path("reports/b0_b1_artifact_audit/comparison.json"))
    compare_parser.add_argument("--csv", type=Path, default=Path("reports/b0_b1_artifact_audit/comparison.csv"))
    compare_parser.add_argument("--html", type=Path, default=Path("reports/b0_b1_artifact_audit/comparison.html"))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    profile_path = args.profile.resolve()
    try:
        if args.command == "capture":
            output = args.output or Path(f"reports/b0_b1_artifact_audit/snapshots/{args.experiment}.json")
            result = capture(profile_path, args.experiment, output.resolve(), args.settle_seconds, args.min_age_seconds)
            print(f"{args.experiment}: {result['status']} -> {output}")
            for reason in result["reasons"]:
                print(f"  - {reason}")
            return 0 if result["status"] == STATUS_PASS else (2 if result["status"] == STATUS_PENDING else 1)
        result = compare_snapshots(profile_path, args.b0.resolve(), args.b1.resolve())
        write_json(args.json.resolve(), result)
        write_comparison_csv(result, args.csv.resolve())
        render_html(result, args.html.resolve())
        print(f"comparison: {result['status']} comparable={result['comparable']} -> {args.html}")
        for reason in result["reasons"]:
            print(f"  - {reason}")
        return 0 if result["status"] == STATUS_PASS else (1 if result["status"] == STATUS_FAIL else 2)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"audit error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
