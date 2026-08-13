#!/usr/bin/env python3
"""Generate the Phase 0 environment/baseline HTML from compact evidence."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


def esc(value: object) -> str:
    return html.escape(str(value))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", type=Path, required=True)
    parser.add_argument("--portability", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    environment = json.loads(args.environment.read_text(encoding="utf-8"))
    portability = json.loads(args.portability.read_text(encoding="utf-8"))
    gate = bool(environment.get("gate_pass")) and portability.get("blocking_count") == 0
    rows = "".join(
        f"<tr><th>{esc(name)}</th><td><code>{esc(value)}</code></td></tr>"
        for name, value in environment["tools"].items()
    )
    hash_rows = "".join(
        f"<tr><th>{esc(name)}</th><td><code>{esc(value)}</code></td></tr>"
        for name, value in environment["hashes"].items()
    )
    findings = "".join(
        f"<tr><td>{esc(item['path'])}</td><td>{esc(item['line'])}</td>"
        f"<td>{esc(item['classification'])}</td></tr>"
        for item in portability.get("findings", [])
    ) or '<tr><td colspan="3">활성 물리 실행 경로에 차단성 하드코딩 없음</td></tr>'

    document = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>최종 통합 GDS Phase 0 환경 기준선</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1100px;margin:32px auto;padding:0 20px;color:#182235}}h1,h2{{color:#173f6b}}.verdict{{padding:18px;border-radius:12px;background:{'#e7f6ed' if gate else '#fff0df'};border-left:6px solid {'#168154' if gate else '#b66a00'}}}table{{width:100%;border-collapse:collapse;margin:14px 0}}th,td{{text-align:left;vertical-align:top;padding:9px;border-bottom:1px solid #dce3eb}}th{{background:#eef3f8}}code{{word-break:break-all}}.boundary{{background:#f2f4f7;padding:14px;border-radius:10px}}</style></head>
<body><h1>Phase 0 — 서버 환경과 기준선 동결</h1>
<div class="verdict"><strong>{'PASS' if gate else 'PARTIAL/FAIL'}</strong><br>캡처 시각: {esc(environment['captured_at_utc'])}<br>Git: <code>{esc(environment['git']['sha'])}</code></div>
<h2>목표</h2><p>GCP 서버의 ORFS/OpenROAD/Sky130HD provenance와 portable 실행 경로를 고정하여 이후 wbq 물리 실험의 재현 가능한 기준선을 만든다.</p>
<h2>도구 버전</h2><table>{rows}</table>
<h2>입력 해시</h2><table>{hash_rows}</table>
<h2>Git 및 EDA provenance</h2><table>
<tr><th>Project branch/SHA</th><td>{esc(environment['git']['branch'])} / <code>{esc(environment['git']['sha'])}</code></td></tr>
<tr><th>ORFS SHA</th><td><code>{esc(environment['git']['orfs_sha'])}</code></td></tr>
<tr><th>OpenROAD SHA</th><td><code>{esc(environment['git']['openroad_sha'])}</code></td></tr>
<tr><th>Environment gate</th><td>{esc(environment['gate_pass'])}</td></tr></table>
<h2>Portability 감사</h2><p>차단 항목: {esc(portability.get('blocking_count'))}, 기록 전용 항목: {esc(portability.get('historical_count'))}</p>
<table><tr><th>파일</th><th>행</th><th>분류</th></tr>{findings}</table>
<h2>서버 자원</h2><pre>{esc(environment['host']['memory'])}\n{esc(environment['host']['disk'])}\n{esc(environment['host']['swap'])}</pre>
<h2>재현 명령</h2><pre>bash verification/groot_normalization/preflight_final_gds_environment.sh
python3 tools/generate_final_gds_phase_report.py --environment reports/final_integrated_gds_execution/environment_manifest.json --portability reports/final_integrated_gds_execution/portability_audit.json --output reports/final_integrated_gds_execution/00_environment_and_baseline_report.html</pre>
<p class="boundary"><strong>Claim boundary:</strong> 이 보고서는 공개 Sky130HD 연구용 환경과 도구 provenance만 증명한다. 제조 signoff, timing closure 또는 routability를 증명하지 않는다. RESEARCH ARTIFACT — NOT FOR FABRICATION.</p>
</body></html>"""
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(document, encoding="utf-8")
    return 0 if gate else 1


if __name__ == "__main__":
    raise SystemExit(main())

