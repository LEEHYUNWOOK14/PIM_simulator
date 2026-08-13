#!/usr/bin/env python3
"""Generate the self-contained Korean HTML report from the frozen manifest."""
from __future__ import annotations
import html, json
from pathlib import Path

EXP=Path(__file__).resolve().parent
d=json.loads((EXP/"b1_baseline_manifest.json").read_text(encoding="utf-8"))
def badge(s):
    k="pass" if s=="PASS" else "warn" if any(x in s for x in ("PARTIAL","WITH","REPORT")) else "fail"
    return f'<span class="badge {k}">{html.escape(s)}</span>'
gates="".join(f"<tr><td><b>{g['gate']}</b></td><td>{badge(g['status'])}</td><td>{html.escape(g['result'])}</td></tr>" for g in d["gates"])
timing="".join(f"<tr><td>{r['stage']}</td><td>{r['area_um2']:,.3f}</td><td class='neg'>{r['wns_ns']:.2f}</td><td class='neg'>{r['tns_ns']:,.2f}</td><td>미달</td></tr>" for r in d["physical"]["timing"])
doc=f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>B1 Logic-die Baseline Experiment Report</title><style>
:root{{--ink:#16202a;--muted:#5d6975;--line:#dce3e8;--paper:#fff;--bg:#eef2f4;--navy:#12354a;--teal:#087f72;--red:#b42318}}*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,-apple-system,"Segoe UI",sans-serif}}main{{max-width:1120px;margin:auto;background:var(--paper);min-height:100vh;padding:52px 64px 80px;box-shadow:0 0 32px #16202a16}}
h1{{font-size:38px;line-height:1.16;margin:.2em 0}}h2{{margin-top:2.2em;border-bottom:2px solid var(--navy);padding-bottom:.28em;color:var(--navy)}}.eyebrow{{color:var(--teal);font-weight:750;letter-spacing:.12em}}.sub{{font-size:18px;color:var(--muted);max-width:850px}}
.decision{{border-left:7px solid var(--red);background:#fff1f0;padding:18px 22px;margin:28px 0;font-size:18px}}.grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:24px 0}}.card{{border:1px solid var(--line);border-radius:10px;padding:16px;background:#fbfcfd}}.card b{{display:block;font-size:25px;color:var(--navy)}}.card span,.small,footer{{color:var(--muted);font-size:13px}}
table{{width:100%;border-collapse:collapse;margin:14px 0 24px}}th,td{{text-align:left;padding:10px 12px;border-bottom:1px solid var(--line);vertical-align:top}}th{{background:#f4f7f8;color:var(--navy)}}.badge{{display:inline-block;border-radius:999px;padding:2px 9px;font-size:12px;font-weight:750;white-space:nowrap}}.pass{{background:#e5f7f2;color:#086b60}}.warn{{background:#fff1d6;color:#8a5200}}.fail{{background:#ffe5e2;color:#a11a12}}.neg{{color:var(--red);font-weight:700}}
.callout{{border:1px solid #efc46e;background:#fff9ea;border-radius:8px;padding:14px 18px}}code{{background:#eef2f4;padding:.12em .35em;border-radius:4px}}pre{{white-space:pre-wrap;background:#12212c;color:#eaf1f4;padding:16px;border-radius:8px;overflow:auto}}a{{color:#076c82}}ul{{padding-left:22px}}footer{{margin-top:56px;padding-top:18px;border-top:1px solid var(--line)}}@media(max-width:760px){{main{{padding:28px 20px}}.grid{{grid-template-columns:repeat(2,1fr)}}table{{font-size:13px}}}}
</style></head><body><main><div class="eyebrow">STOB PIM2 · BASELINE B1</div><h1>Logic-die 계층 기준선 실험 보고서</h1>
<p class="sub">계획서의 G0–G9 전체 항목을 실행·검토한 결과다. 성공 단계뿐 아니라 구성 계약 위반, 타이밍 미달, 상세 배선 자원 실패도 승인 판단에 포함했다.</p><p class="small">생성 시각: {html.escape(d['generated_at'])} · sky130hd / TT 25°C 1.80 V · 목표 클록 10.0 ns</p>
<div class="decision"><b>최종 판정: NOT APPROVED</b><br>실험 수행은 완료되었으나 계획서 그대로의 구성은 RTL에서 유효하지 않고, 10 ns 타이밍을 만족하지 못했으며 상세 배선·DRC·antenna·GDS가 완료되지 않았다. B1 동결 및 B0 대비 물리/에너지 승인을 내릴 수 없다.</div>
<div class="grid"><div class="card"><b>101,095</b><span>generic B1 cells</span></div><div class="card"><b>56,097</b><span>Sky130 mapped cells</span></div><div class="card"><b>−47.21 ns</b><span>global-route WNS</span></div><div class="card"><b>40%</b><span>detailed-route 도달점</span></div></div>
<h2>1. 게이트 판정</h2><table><thead><tr><th>Gate</th><th>판정</th><th>근거</th></tr></thead><tbody>{gates}</tbody></table>
<h2>2. 구성 고정과 계획 결함</h2><p>Top은 <code>full_pim_system_top</code>, 기능 스위치는 <code>ENABLE_LOGIC_DIE_PCU=1</code>, <code>ENABLE_NORMALIZATION_ENGINE=0</code>이다. 정확 계획 구성은 <code>CHANNELS/BANKS/PIM_BLOCKS/PCUS/ROWS/COLS=1</code>, <code>DATA_WIDTH=16</code>이다.</p>
<div class="callout"><b>정확 계획 구성은 기능 시뮬레이션이 불가능하다.</b> RTL은 <code>BANKS == 2 × PIM_BLOCKS</code>와 <code>DATA_WIDTH % 32 == 0</code>을 요구한다. 정확 구성은 두 assertion의 예상 실패를 남겼고, 기능 경로는 <code>BANKS=2, DATA_WIDTH=32</code>인 최소 유효 구성에서 추가 검증했다. 합성/물리는 assertion이 제거되는 정확 계획 구성으로 실행했다.</div>
<h2>3. 기능 및 구조 검증</h2><ul><li>최소 유효 계층 테스트: <b>PASS</b>, 41 cycles. shared-buffer, response backpressure, epoch, bank→logic 결과, PCU tag/data, reduction, host-router backpressure, normalization idle, protocol error 0을 확인했다.</li><li>RTL audit 회귀: FP16 multiply 4,217 vectors mismatch 0, operand validity, invalid CRF deadlock 방지, DRAM backpressure, timing, CRF jump/repeat, logic tag/channel 모두 PASS.</li><li>Logic result router formal SAT proof: PASS.</li><li>mapped 구조: Logic-die 표식 72,526 occurrences, normalization instance 0, unmapped cell 0.</li></ul>
<p>증거: <a href="logs/b1_functional.log">통합 로그</a>, <a href="logs/b1_contract_probe.log">계약 probe</a>, <a href="metrics/b1_functional_results.csv">결과 CSV</a>, <a href="artifacts/b1_hierarchical.vcd">VCD</a>.</p>
<h2>4. 합성·STA</h2><p>Generic 합성은 101,095 cells다. Sky130HD 매핑은 56,097 cells, 면적 702,769.011 µm²이며 sequential 면적은 418,575.197 µm²(59.56%)다. 매핑은 문제 0/unmapped 0으로 완료됐지만 모든 단계에서 목표 타이밍을 위반했다.</p>
<table><thead><tr><th>단계</th><th>면적 (µm²)</th><th>WNS (ns)</th><th>TNS (ns)</th><th>10 ns</th></tr></thead><tbody>{timing}</tbody></table><p>Pre-layout 최장 경로는 bank CRF PC→bank core GRF이며 arrival 58.2899 ns, required 9.5314 ns였다. 뒤의 10 ns 성능 환산값은 signoff 성능이 아니다.</p>
<h2>5. 물리 구현</h2><table><tbody><tr><th>Floorplan</th><td>die 1534.545 × 1534.545 µm, core 2,338,758.054 µm², 목표 utilization 30%</td></tr><tr><th>Placement</th><td>area 895,637 µm², utilization 38%, legalized HPWL 4,212,992.9 µm, 평균 displacement 2.4 µm</td></tr><tr><th>CTS</th><td>14,058 sinks, 1,603 buffers, 최대 level 7; post-CTS STA 완료. 별도 skew 수치 추출은 자원 한계로 미완료</td></tr><tr><th>Global route</th><td>wirelength 6,853,970 µm, vias 658,010, guides 712,675, resource usage 47.46%, 보고된 max congestion 0</td></tr><tr><th>Detailed route</th><td><b class="neg">실패</b>: iteration 0의 40%에서 13,497 violations, 379 s 후 OOM. 5_2_route.odb/최종 DRC/antenna/GDS 없음</td></tr></tbody></table>
<p>진행 로그는 10%와 20%에서 0 violations, 30%부터 13,497를 기록했다. 종료 직후 kernel 기록의 openroad anon RSS는 21,195,172 kB(약 20.2 GiB)였다. <a href="logs/orfs_do-5_2_route.log">진행 로그</a>, <a href="logs/b1_detailed_route_failure_summary.txt">종료 요약</a>.</p>
<h2>6. 활동도·전력·성능</h2><p>공통 work ID는 <code>B1_HIERARCHICAL_41_CYCLE_TRACE</code>이며 Logic 활성은 확인했다. RTL VCD를 mapped netlist에 직접 연결한 시도는 annotated pin 0이었다. 따라서 VCD aggregate input activity(0.001210916 toggle/bit/cycle, duty 0.30558)를 global-route ODB에 적용해 내부 활동도를 전파한 <b>추정치</b>만 제공한다.</p>
<table><tbody><tr><th>Mapped total power</th><td>0.742 W (internal 0.352 W, switching 0.391 W, leakage 0.346 µW)</td></tr><tr><th>Logic-die leaf subset</th><td>0.059789 W; shared top/global clock 제외</td></tr><tr><th>Latency</th><td>41 cycles; 목표 10 ns 환산 410 ns/work</td></tr><tr><th>Throughput</th><td>2.439 Mwork/s — timing 미달인 정규화 값</td></tr><tr><th>Energy</th><td>304.22 nJ/work — 파생 활동도·미폐쇄 타이밍 기반 추정값</td></tr></tbody></table>
<p>근거: <a href="metrics/b1_vcd_activity_summary.json">활동도</a>, <a href="logs/b1_grt_power_derived.log">전력</a>, <a href="metrics/b1_block_power.json">계층 subset</a>, <a href="metrics/b1_power_performance.csv">정규화 CSV</a>.</p>
<h2>7. B0 비교</h2><table><thead><tr><th>항목</th><th>B0</th><th>B1</th><th>판정</th></tr></thead><tbody><tr><td>Generic cells</td><td>14,945</td><td>101,095</td><td>+86,150 / +576.45%; 구조 비교만 유효</td></tr><tr><td>물리 구성</td><td>BANKS=2, DATA_WIDTH=32 결과만 존재</td><td>BANKS=1, DATA_WIDTH=16</td><td>직접 비교 금지</td></tr><tr><td>Route stage</td><td>별도 B0는 GDS 존재</td><td>global route까지만 완료</td><td>G7 미충족</td></tr><tr><td>동적 비교</td><td>공통-work 자료 없음</td><td>파생 활동도 추정</td><td>에너지 비교 미승인</td></tr></tbody></table><p>Generic cell 증분은 참고 가능하지만 mapped PPA와 energy의 증분은 구성·단계·활동도 증거가 같지 않아 승인하지 않는다.</p>
<h2>8. 다음 조치</h2><ol><li>계획 최소 구성을 <code>BANKS=2, DATA_WIDTH=32</code>로 정정하고 B0/B1을 동일 조건으로 재실행한다.</li><li>bank CRF→GRF 경로를 파이프라이닝하거나 목표 주기를 현실화한다.</li><li>더 큰 메모리 또는 partition/hierarchical flow로 상세 배선을 마치고 DRC·antenna·GDS를 만든다.</li><li>RTL↔mapped name mapping 또는 SAIF flow로 direct annotation 후 동일 work의 B0/B1 전력을 비교한다.</li></ol>
<h2>9. 재현성과 산출물</h2><p>입력·주요 산출물의 SHA-256은 <a href="metrics/hash_manifest.csv">hash manifest</a>, 전체 판정은 <a href="b1_baseline_manifest.json">JSON manifest</a>, 단계별 표는 <a href="metrics/b1_gate_results.csv">gate</a>, <a href="metrics/b1_synthesis_timing.csv">timing</a>, <a href="metrics/b1_physical_metrics.csv">physical CSV</a>에 있다.</p>
<pre>cd STOB_PIM2
wsl -e bash b1_logic_die_experiment/run_functional.sh
wsl -e bash b1_logic_die_experiment/run_orfs.sh
wsl -e python3 b1_logic_die_experiment/collect_results.py
wsl -e python3 b1_logic_die_experiment/generate_report.py</pre><p class="small">run_orfs.sh의 상세 배선은 본 환경에서 OOM으로 실패했다. 재실행 시 메모리 사용량을 감시해야 한다.</p>
<footer>STOB_PIM2 B1 experiment · plan SHA-256 {d['plan']['sha256']}</footer></main></body></html>"""
(EXP/"b1_logic_die_experiment_report.html").write_text(doc,encoding="utf-8")
print("wrote b1_logic_die_experiment_report.html")
