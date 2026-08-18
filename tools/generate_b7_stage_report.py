#!/usr/bin/env python3
"""Render compact, hash-pinned HTML for a completed B7 stage."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BOUNDARY = "RESEARCH ARTIFACT — NOT FOR FABRICATION"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def flatten(prefix: str, value: Any) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            rows.extend(flatten(f"{prefix}.{key}" if prefix else str(key), child))
    elif isinstance(value, list):
        if len(value) <= 12 and all(not isinstance(item, (dict, list)) for item in value):
            rows.append((prefix, json.dumps(value, ensure_ascii=False)))
        else:
            rows.append((prefix, f"list[{len(value)}]"))
    else:
        rows.append((prefix, str(value)))
    return rows


def artifact_rows(label: str, doc: dict) -> list[tuple[str, str, str, str]]:
    rows = []
    for section in ("inputs", "outputs", "artifacts"):
        for name, item in doc.get(section, {}).items():
            if not isinstance(item, dict) or not item.get("path"):
                continue
            rows.append(
                (
                    f"{label}.{section}.{name}",
                    str(item["path"]),
                    str(item.get("bytes", "—")),
                    str(item.get("sha256", "—")),
                )
            )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--manifest", action="append", required=True, help="LABEL=PATH")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--command", action="append", default=[])
    parser.add_argument("--summary", default="")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    if output.exists() and not args.replace:
        raise FileExistsError(f"refusing to overwrite {output}; pass --replace for an intentional report update")

    manifests = []
    for spec in args.manifest:
        if "=" not in spec:
            raise ValueError(f"manifest must be LABEL=PATH: {spec}")
        label, text = spec.split("=", 1)
        path = Path(text)
        path = path if path.is_absolute() else ROOT / path
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
        doc = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(doc, dict):
            raise ValueError(f"manifest is not a JSON object: {path}")
        manifests.append((label, path, doc))

    git = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()
    status_rows = []
    metric_rows = []
    artifacts = []
    for label, path, doc in manifests:
        verdict = next(
            (str(doc[key]) for key in ("status", "decision", "verdict", "overall_result") if key in doc),
            "UNKNOWN",
        )
        status_rows.append((label, verdict, str(path), sha256(path)))
        for key, value in flatten(label, doc.get("metrics", {})):
            metric_rows.append((key, value))
        artifacts.extend(artifact_rows(label, doc))

    esc = html.escape
    status_html = "".join(
        f"<tr><th>{esc(label)}</th><td>{esc(verdict)}</td><td><code>{esc(path)}</code></td>"
        f"<td><code>{esc(digest)}</code></td></tr>"
        for label, verdict, path, digest in status_rows
    )
    metric_html = "".join(
        f"<tr><th>{esc(key)}</th><td>{esc(value)}</td></tr>" for key, value in metric_rows
    ) or "<tr><td colspan='2'>No metrics object in the supplied manifests.</td></tr>"
    artifact_html = "".join(
        f"<tr><th>{esc(name)}</th><td><code>{esc(path)}</code></td><td>{esc(size)}</td>"
        f"<td><code>{esc(digest)}</code></td></tr>"
        for name, path, size, digest in artifacts
    ) or "<tr><td colspan='4'>No recorded artifact map in the supplied manifests.</td></tr>"
    commands = "\n".join(args.command) if args.command else "See the hash-pinned invocation manifests above."
    summary = args.summary or "The supplied manifests define the measured result and the next authorized stage."
    document = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(args.title)}</title><style>
body{{font:15px system-ui;max-width:1180px;margin:36px auto;padding:0 24px;color:#172033}}
h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%;margin:14px 0 28px}}
th,td{{border:1px solid #d6dce6;padding:8px;text-align:left;vertical-align:top}}th{{background:#f2f5f9}}
code{{word-break:break-all}}pre{{white-space:pre-wrap;background:#f6f8fa;padding:14px}}
.boundary{{padding:16px;background:#fff3cd;border:1px solid #d6aa22;font-weight:700}}
</style></head><body>
<h1>Phase {esc(args.stage)} — {esc(args.title)}</h1>
<p>{esc(summary)}</p><p>Report UTC: <code>{datetime.now(timezone.utc).isoformat()}</code><br>
Git revision: <code>{esc(git)}</code></p>
<h2>Gate results and manifest hashes</h2><table><tr><th>Evidence</th><th>Verdict</th><th>Path</th><th>SHA-256</th></tr>{status_html}</table>
<h2>Measured metrics</h2><table>{metric_html}</table>
<h2>Recorded inputs and outputs</h2><table><tr><th>Name</th><th>Path</th><th>Bytes</th><th>SHA-256</th></tr>{artifact_html}</table>
<h2>Reproduction commands</h2><pre>{esc(commands)}</pre>
<p class="boundary">{BOUNDARY}</p>
</body></html>
"""
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")
    print(f"B7_STAGE_HTML PASS stage={args.stage} output={output} sha256={sha256(output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

