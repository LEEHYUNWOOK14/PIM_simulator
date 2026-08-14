#!/usr/bin/env python3
"""Build an evidence-backed HTML report for unusually expensive log stages."""

from __future__ import annotations

import html
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "REPORT/long_running_tasks"
ORFS = Path("/home/forstobpim/OpenROAD-flow-scripts/flow/logs/sky130hd/normalization_hbm_wbq")
ELAPSED = re.compile(r"Elapsed time:\s*(\d+):(\d+(?:\.\d+)?)\[h:\]min:sec\. CPU time: user ([\d.]+) sys ([\d.]+) \((\d+)%\)\. Peak memory: (\d+)KB")
TOOK = re.compile(r"Took\s+(\d+)\s+seconds:\s*(.+)")
RUNNING = re.compile(r"Running\s+\S+,\s+stage\s+(\S+)")


def scan_logs() -> tuple[list[dict], int, int]:
    paths = list(ROOT.rglob("*.log"))
    if ORFS.exists():
        paths += list(ORFS.rglob("*.log"))
    seen, stages, total_bytes = set(), [], 0
    for path in paths:
        key = str(path.resolve())
        if key in seen:
            continue
        seen.add(key)
        try:
            total_bytes += path.stat().st_size
            text = path.read_text(errors="replace")
        except OSError:
            continue
        last_command = "unattributed command"
        current_stage = "unattributed stage"
        for lineno, line in enumerate(text.splitlines(), 1):
            running = RUNNING.search(line)
            if running:
                current_stage = running.group(1)
            took = TOOK.search(line)
            if took:
                last_command = took.group(2).strip()
                stages.append({"seconds": int(took.group(1)), "cpu": None,
                               "memory_mb": None, "command": last_command,
                               "path": key, "line": lineno, "kind": "Took"})
            elapsed = ELAPSED.search(line)
            if elapsed:
                seconds = int(elapsed.group(1)) * 60 + float(elapsed.group(2))
                stages.append({"seconds": seconds, "cpu": int(elapsed.group(5)),
                               "memory_mb": int(elapsed.group(6)) / 1024,
                               "command": current_stage, "path": key,
                               "line": lineno, "kind": "Elapsed"})
    return stages, len(seen), total_bytes


def fmt(seconds: float) -> str:
    seconds = int(round(seconds))
    h, seconds = divmod(seconds, 3600)
    m, s = divmod(seconds, 60)
    return f"{h:d}:{m:02d}:{s:02d}"


def short(path: str) -> str:
    try:
        return str(Path(path).relative_to(ROOT))
    except ValueError:
        return path


def svg_bars(items: list[dict]) -> str:
    width, row, label = 1050, 34, 410
    maximum = max(x["seconds"] for x in items) or 1
    rows = []
    for i, item in enumerate(items):
        y = 25 + i * row
        bar_width = (width - label - 110) * item["seconds"] / maximum
        name = html.escape(item["command"][:50])
        rows.append(f'<text x="8" y="{y+15}" class="axis">{name}</text>')
        rows.append(f'<rect x="{label}" y="{y}" width="{bar_width:.1f}" height="22" rx="4"/>')
        rows.append(f'<text x="{label+bar_width+8:.1f}" y="{y+16}" class="value">{fmt(item["seconds"])}</text>')
    return f'<svg viewBox="0 0 {width} {40+row*len(items)}" role="img" aria-label="장시간 단계 비교">' + "".join(rows) + "</svg>"


def main() -> int:
    stages, log_count, total_bytes = scan_logs()
    elapsed = sorted((x for x in stages if x["kind"] == "Elapsed"), key=lambda x: x["seconds"], reverse=True)
    took = sorted((x for x in stages if x["kind"] == "Took"), key=lambda x: x["seconds"], reverse=True)
    # Elapsed records are authoritative wrappers; retain the longest unique path/line entries.
    top, signatures = [], set()
    for item in elapsed:
        # Mirrored ORFS aggregate/stage logs contain identical wrapper records.
        signature = (round(item["seconds"], 2), item["cpu"],
                     round(item["memory_mb"], 1))
        if signature not in signatures:
            signatures.add(signature)
            top.append(item)
        if len(top) == 18:
            break
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    incidents = [
        {"name": "WBQ repair_design gap A", "start": "2026-08-14 00:50:36 UTC",
         "end": "2026-08-14 03:41:57 UTC", "seconds": 10281,
         "marker": "2,983,000 → 2,984,000", "delta": "+13 resized, +12 buffers, +13 repaired",
         "cause": "High-terminal net의 Steiner 후보 edge 탐색으로 추정. 당시 함수 프로파일은 없어 inference.",
         "resolution": "개입 없이 계산 완료 후 1,000-driver marker 출력."},
        {"name": "WBQ repair_design gap B", "start": "2026-08-14 03:41:57 UTC",
         "end": "2026-08-14 06:34:20 UTC", "seconds": 10343,
         "marker": "2,984,000 → 2,985,000", "delta": "+13 resized, +12 buffers, +13 repaired",
         "cause": "perf 2회에서 CPU 99.3~100%가 pdr::get_nearest_neighbors()에 집중. 중첩 순회 O(N²).",
         "resolution": "개입 없이 nearest-neighbor 계산 완료 후 marker 출력."},
        {"name": "WBQ buffer explosion", "start": "marker 2,980,000",
         "end": "marker 2,981,000", "seconds": 0,
         "marker": "2,980,000 → 2,981,000", "delta": "+15 resized, +1,485 buffers, +16 repaired",
         "cause": "소수의 초대형 fanout/high-terminal net에 region repeater가 대량 삽입된 정황.",
         "resolution": "buffer 삽입 완료. 이후 STA graph와 Steiner 입력 크기를 키워 후속 비용을 증폭했을 가능성."},
    ]
    chart_items = [dict(command=x["name"], seconds=x["seconds"]) for x in incidents if x["seconds"]]
    chart_items += top[:6]
    table_rows = "".join(
        f'<tr><td>{i+1}</td><td>{html.escape(x["command"][:100])}</td><td>{fmt(x["seconds"])}</td>'
        f'<td>{x["cpu"] if x["cpu"] is not None else "—"}%</td><td>{x["memory_mb"]:.0f}</td>'
        f'<td><code>{html.escape(short(x["path"]))}:{x["line"]}</code></td></tr>'
        for i, x in enumerate(top)
    )
    incident_cards = "".join(
        f'<article><h3>{html.escape(x["name"])}</h3><div class="metric">{fmt(x["seconds"]) if x["seconds"] else "연산량 이상"}</div>'
        f'<p><b>시간</b> {x["start"]} → {x["end"]}<br><b>진행</b> {x["marker"]}<br><b>변화</b> {x["delta"]}</p>'
        f'<p><b>원인</b> {x["cause"]}</p><p><b>종료/해결</b> {x["resolution"]}</p></article>' for x in incidents
    )
    report = f'''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>장시간·고연산 작업 분석</title><style>
:root{{--bg:#08111f;--card:#101d31;--text:#e8f0fb;--muted:#9bb0c9;--blue:#46a6ff;--amber:#ffb84d;--red:#ff6577;--line:#263a55}}
*{{box-sizing:border-box}}body{{margin:0;background:linear-gradient(145deg,#07101e,#0d1830);color:var(--text);font:15px/1.55 system-ui,sans-serif}}
main{{max-width:1200px;margin:auto;padding:34px}}h1{{font-size:32px;margin:0 0 8px}}h2{{margin-top:38px}}.sub{{color:var(--muted)}}.summary,.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px}}
.kpi,article,.panel{{background:rgba(16,29,49,.94);border:1px solid var(--line);border-radius:14px;padding:18px}}.kpi strong,.metric{{font-size:27px;color:var(--amber)}}
article h3{{margin-top:0;color:#8bc7ff}}code{{color:#a9d3ff;white-space:normal}}table{{width:100%;border-collapse:collapse;font-size:13px}}th,td{{padding:9px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}}th{{color:#9fd0ff;position:sticky;top:0;background:#101d31}}
.scroll{{overflow:auto;max-height:620px}}svg{{width:100%;height:auto}}svg rect{{fill:var(--blue)}}svg .axis{{fill:var(--text);font-size:12px}}svg .value{{fill:var(--amber);font-size:12px;font-weight:700}}.warn{{border-left:4px solid var(--amber);padding-left:14px}}li{{margin:6px 0}}
</style></head><body><main><h1>장시간·비정상 고연산 작업 분석</h1><p class="sub">생성: {now} · 정적 로그 전수 스캔 + WBQ 실시간 관측 + perf 함수 표본</p>
<section class="summary"><div class="kpi"><strong>{log_count:,}</strong><br>순회한 *.log 파일</div><div class="kpi"><strong>{total_bytes/1024/1024:.1f} MiB</strong><br>읽은 로그 용량</div><div class="kpi"><strong>{len(stages):,}</strong><br>시간 표식</div><div class="kpi"><strong>{len([x for x in elapsed if x["seconds"]>=120]):,}</strong><br>2분 이상 wrapper 단계</div></section>
<h2>핵심 이상 구간</h2><div class="cards">{incident_cards}</div>
<h2>시간 비교</h2><div class="panel">{svg_bars(chart_items)}</div>
<h2>로그 전수 스캔 상위 단계</h2><p class="sub">ORFS의 <code>Elapsed time</code> wrapper를 우선 사용했습니다. 같은 작업의 <code>Took</code> 행과 wrapper 행은 중복될 수 있어 표에는 wrapper만 표시합니다.</p>
<div class="panel scroll"><table><thead><tr><th>#</th><th>귀속 명령</th><th>Wall</th><th>CPU</th><th>Peak MB</th><th>근거</th></tr></thead><tbody>{table_rows}</tbody></table></div>
<h2>원인 계산</h2><div class="panel"><p>현재 WBQ gap B의 프로파일은 <code>pdr::get_nearest_neighbors(points)</code>가 CPU의 99.3~100%를 소비함을 보였습니다. 구현은 정렬된 점마다 이전 점을 위/아래 방향으로 각각 순회합니다.</p>
<pre>비교 횟수 ≈ 2 × Σ(i=0..N-1) i = N(N-1) = O(N²)</pre><p>따라서 terminal 수가 10배 늘면 후보 비교는 약 100배가 됩니다. 최종 buffer 수가 작더라도 탐색 입력 pin 수가 크면 wall time이 폭증할 수 있습니다.</p>
<p>WBQ gap A는 동일한 marker 패턴과 자원 상태를 보이지만 당시 perf가 없어 같은 함수였다는 결론은 <b>추정</b>입니다. 반면 gap B의 함수 병목은 <b>측정</b>입니다.</p></div>
<h2>대표 과다 연산 분류</h2><div class="panel"><ul><li><b>WBQ global placement 21m42s + parasitic 15m17s:</b> 406만 driver 규모, placement 및 RC 추정 자체가 큰 입력.</li><li><b>Baseline detailed route 3m49s:</b> CPU 306%, 218,388 routing objects와 maze/detail routing.</li><li><b>과거 floorplan global placement 2m49s:</b> routability iteration 1,674회, artificial inflation +29.69%, timing delta +18.78%.</li><li><b>WBQ repair gap:</b> 메모리/I/O 병목이 아니라 단일 코어 O(N²) PDR nearest-neighbor 계산.</li></ul></div>
<h2>판정 기준과 한계</h2><div class="panel warn"><ul><li>2분 이상 wrapper 또는 같은 marker의 30분 이상 무출력을 장시간 후보로 분류.</li><li>CPU%가 높고 CPU tick이 증가하면 계산 중, I/O wait·swap·major fault가 없으면 자원 stall로 판정하지 않음.</li><li>과거 로그에 행별 timestamp가 없으면 내부 gap은 복원할 수 없습니다. WBQ gap은 Codex 세션의 주기 관측 시각을 결합했습니다.</li><li>파일 크기는 연산량의 직접 지표가 아니며, 원인은 명령·iteration·CPU·메모리·프로파일 근거를 함께 사용했습니다.</li><li>보고서는 생성 시점 snapshot입니다. 활성 WBQ 작업 완료 후 다시 생성해야 최종 시간이 반영됩니다.</li></ul></div>
</main></body></html>'''
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "long_running_task_analysis.html").write_text(report, encoding="utf-8")
    payload = {"generated_at": now, "log_count": log_count, "bytes_scanned": total_bytes,
               "time_markers": len(stages), "incidents": incidents, "top_elapsed": top,
               "top_took": took[:25]}
    (OUT / "long_running_task_analysis.json").write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(OUT / "long_running_task_analysis.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
