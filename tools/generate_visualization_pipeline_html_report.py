#!/usr/bin/env python3
"""Generate a self-contained Korean HTML report for the visualization pipeline."""
from __future__ import annotations

import base64
import csv
import hashlib
import html
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIG = ROOT / "output/floorplan_optimization/visualization/paper_figures"
OUT = ROOT / "reports/floorplan_optimization/visualization_pipeline_report.html"


def data_uri(path: Path) -> str:
    mime = "image/svg+xml" if path.suffix.lower() == ".svg" else "image/png"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def figure_card(number: int, title: str, filename: str, badge: str, summary: str,
                inputs: str, transform: str, render: str, claim: str, boundary: str) -> str:
    path = FIG / filename
    return f"""
    <article class="figure-card" id="figure-{number}">
      <div class="figure-head"><div><span class="eyebrow">FIGURE {number:02d}</span><h3>{html.escape(title)}</h3></div><span class="badge modeled">{html.escape(badge)}</span></div>
      <button class="image-button" data-full="fig-{number}" aria-label="그림 {number} 확대"><img src="{data_uri(path)}" alt="{html.escape(title)}"></button>
      <p class="figure-summary">{summary}</p>
      <div class="how-grid">
        <div><b>① 입력</b><p>{inputs}</p></div>
        <div><b>② 변환</b><p>{transform}</p></div>
        <div><b>③ 렌더</b><p>{render}</p></div>
      </div>
      <div class="claim-grid"><div class="claim"><b>논문에서 말할 수 있는 것</b><p>{claim}</p></div><div class="boundary"><b>말할 수 없는 것</b><p>{boundary}</p></div></div>
      <details><summary>파일 및 재현 정보</summary><code>{html.escape(str(path.relative_to(ROOT)).replace(chr(92), '/'))}</code><br><code>SHA-256 {sha(path)}</code></details>
    </article>"""


def main() -> int:
    vis = load_json(ROOT / "output/floorplan_optimization/visualization/thermal_first/visualization_manifest.json")
    pv = load_json(ROOT / "output/floorplan_optimization/visualization/thermal_first/paraview/paraview_manifest.json")
    candidates = load_csv(ROOT / "output/floorplan_optimization/candidate_comparison.csv")
    stress = load_json(ROOT / "reports/floorplan_optimization/results/historical_routed_gds_merge_stress_report.json")
    candidate_rows = "".join(
        f"<tr><td>{html.escape(r['strategy'])}</td><td>{float(r['reference_peak_temperature_C']):.3f}</td>"
        f"<td>{float(r['openroad_global_route_wirelength_um'])/1000:.3f}</td><td>{float(r['global_route_overflow_sum']):.0f}</td>"
        f"<td>{float(r['candidate_structural_cost_proxy']):.3f}</td></tr>" for r in candidates
    )
    figures = "".join([
        figure_card(1, "HBM stack 3D 온도 시각화", "figure_01_hbm_stack_3d.png", "modeled · illustrative",
          "21개 적층 열 격자와 logic block, TSV 중심선을 하나의 3D 장면으로 합친 그림이다. 얇은 실제 적층을 읽기 쉽게 만들기 위해 Z축만 20배 과장했다.",
          "thermal-first 후보 manifest, reference solver의 <code>temperature_field.npz</code>, 8개 block과 320개 TSV 좌표.",
          "<code>export_floorplan_paraview.py</code>가 32×16×21 thermal cells, block wireframe, TSV centerline을 VTU cell data로 변환한다. object_type 0/1/2와 temperature_K, signal_class, diameter_um을 기록한다.",
          "ParaView 6.1.1이 thermal surface를 온도 LUT로, block과 TSV를 wireframe으로 분리하고 고정 camera에서 2400×1800 PNG를 저장한다. VisRTX가 RTX 4060을 사용했다.",
          "동일 modeled stack에서 TSV·block·온도장의 공간적 관계와 Z축 과장 방식을 재현할 수 있다.",
          "실제 제조 단면, 실제 재료 미세형상, GPU thermal solver 결과 또는 calibrated junction temperature가 아니다."),
        figure_card(2, "Logic die block과 TSV bundle 좌표도", "figure_02_logic_die_tsv_coordinates.png", "canonical geometry",
          "공통 8×12 mm 좌표계에서 block, TSV bundle, routing corridor와 reserved region이 어디에 놓이는지 보여주는 기본 지도다.",
          "thermal-first candidate JSON의 block rectangle, 48개 TSV bundle, 4개 reserved region, 8개 routing corridor.",
          "각 bundle의 rows·columns·pitch로 중심을 계산하고 signal_class에 따라 data/CA/clock/power/ground/spare 색을 부여한다. 좌표는 µm에서 mm로 변환한다.",
          "Matplotlib이 x=0–8 mm, y=0–12 mm를 고정하고 block label, 범례, 축 단위를 넣어 300 dpi PNG와 편집 가능한 SVG를 동시에 생성한다.",
          "모든 후보와 도구가 같은 canonical 좌표를 사용하며 bundle-level 위치와 signal class를 추적할 수 있다.",
          "공개되지 않은 bit-level HBM pin map이나 제조용 PHY 배치를 뜻하지 않는다."),
        figure_card(3, "Baseline 대비 배치 후보 비교", "figure_03_candidate_placement_comparison.png", "modeled candidates",
          "manual, wirelength-first, thermal-first, balanced 후보를 동일한 축척으로 나란히 놓아 block 이동만 비교하도록 만든 그림이다.",
          "seed 235 최적화에서 선택된 네 candidate manifest. 모든 후보는 동일 die, TSV, reserved constraint를 사용한다.",
          "같은 draw_floorplan 함수를 반복 호출하여 block·TSV·reserved·corridor 표현을 통일한다. sharex/sharey와 고정 extent로 시각적 축척 왜곡을 막는다.",
          "Matplotlib 1×4 panel, 공통 0–8×0–12 mm 축, 동일 색 팔레트와 300 dpi 출력.",
          "목적함수에 따라 합법적인 provisional block 좌표가 어떻게 달라지는지 비교할 수 있다.",
          "standard-cell 실제 배치나 최종 production floorplan은 아니다."),
        figure_card(4, "OpenROAD global-route 배선·혼잡 비교", "figure_04_openroad_routing_congestion.png", "global-routed proxy",
          "각 후보를 16개 fixed conceptual macro로 변환한 뒤 동일한 OpenROAD 조건에서 얻은 layer별 wirelength와 overflow를 보여준다.",
          "후보별 DEF/LEF/Verilog proxy와 <code>openroad_proxy_metrics.csv</code>의 met2–met5 wirelength, violation bins, overflow sum.",
          "OpenROAD가 global route를 수행하고 collector가 congestion report를 직접 파싱한다. figure generator는 layer wirelength를 누적 막대로, overflow와 violation bin을 병렬 막대로 표시한다.",
          "Matplotlib 2-panel plot. 후보 순서와 y축 단위를 고정하고 도구/증거 범위를 제목에 표시한다.",
          "동일 conceptual macro 조건에서 후보의 상대 배선량과 global-route 혼잡 차이를 비교할 수 있다.",
          "최종 RTL detailed route, STA, IR-drop, DRC-clean 결과가 아니다."),
        figure_card(5, "전력 map과 온도 heatmap", "figure_05_power_temperature_heatmaps.png", "modeled · estimated 4 W",
          "동일한 4 W가 block 좌표에 어떻게 rasterize되고 reference finite-volume solver가 어떤 온도장을 계산했는지 좌우로 연결한 그림이다.",
          "thermal-first의 <code>temperature_field.npz</code> 안에 저장된 power_W_cell과 temperature_K 배열.",
          "logic layer의 32×16 power grid와 temperature grid를 선택하고 온도는 K에서 °C로 변환한다. 전력 보존은 모든 후보에서 4.0 W, 오차 ≤1e−12 W로 검증됐다.",
          "동일 0–8×0–12 mm extent의 magma/inferno heatmap과 각각의 단위 colorbar를 300 dpi PNG/SVG로 출력한다.",
          "동일 estimated-power 조건에서 hotspot 위치와 후보의 상대 열 경향을 설명할 수 있다.",
          "실측 전력, calibrated boundary condition 또는 절대 안전온도 판단이 아니다."),
        figure_card(6, "비용–배선–온도 Pareto trade-off", "figure_06_cost_wire_temperature_pareto.png", "normalized proxy",
          "후보 하나가 모든 지표에서 최고가 아님을 보여주기 위해 비용–온도와 배선–온도를 두 패널로 분리한 의사결정 그림이다.",
          "<code>candidate_comparison.csv</code>의 normalized structural cost, reference peak temperature, OpenROAD global-route wirelength와 overflow.",
          "동일 candidate ID인 balanced/cost-first를 중복 geometry로 처리하고, 점 위치는 cost 또는 wirelength와 temperature, 점 색은 overflow를 나타낸다.",
          "Matplotlib scatter/annotation, 동일 온도 단위와 overflow 색 범위, 300 dpi PNG/SVG.",
          "열·배선·normalized cost 간 상충관계와 provisional shortlist 선택 근거를 재현할 수 있다.",
          "실제 wafer/package 견적 또는 단일 production winner를 뜻하지 않는다."),
    ])

    css = r"""
    :root{--ink:#18212b;--muted:#5e6b76;--paper:#f4f1e9;--card:#fffdf8;--line:#d8d2c4;--navy:#16324f;--teal:#157a7a;--orange:#d8752a;--red:#a94442;--green:#297a53;--violet:#6657a3;--shadow:0 12px 30px rgba(26,35,45,.09)}
    *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--paper);color:var(--ink);font-family:"Segoe UI","Noto Sans KR",Arial,sans-serif;line-height:1.68}a{color:var(--teal)}code,pre{font-family:Consolas,"SFMono-Regular",monospace}code{font-size:.9em;background:#ede9df;padding:.12rem .32rem;border-radius:4px;overflow-wrap:anywhere}
    .hero{background:linear-gradient(125deg,#102b44,#164e5b 62%,#7d4b2d);color:white;padding:74px max(5vw,30px) 58px;position:relative;overflow:hidden}.hero:after{content:"";position:absolute;width:440px;height:440px;border:1px solid rgba(255,255,255,.16);border-radius:50%;right:-100px;top:-210px;box-shadow:0 0 0 55px rgba(255,255,255,.035),0 0 0 110px rgba(255,255,255,.025)}.hero-inner{max-width:1200px;margin:auto;position:relative;z-index:1}.kicker{letter-spacing:.16em;text-transform:uppercase;font-size:.78rem;color:#bce8df;font-weight:700}.hero h1{font-size:clamp(2.1rem,5vw,4.6rem);line-height:1.06;margin:.55rem 0 1rem;max-width:980px}.hero p{max-width:840px;font-size:1.1rem;color:#e5f1ef}.hero-meta{display:flex;gap:10px;flex-wrap:wrap;margin-top:24px}.hero-meta span,.badge{padding:5px 11px;border-radius:999px;font-size:.77rem;font-weight:700}.hero-meta span{background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.22)}
    nav{position:sticky;top:0;z-index:20;background:rgba(255,253,248,.94);backdrop-filter:blur(12px);border-bottom:1px solid var(--line);overflow:auto;white-space:nowrap;padding:0 max(3vw,15px)}nav .nav-inner{max-width:1200px;margin:auto;display:flex;gap:20px}nav a{display:inline-block;padding:14px 0;text-decoration:none;color:#33404b;font-size:.87rem;font-weight:650}nav a:hover{color:var(--teal)}main{max-width:1200px;margin:auto;padding:54px 24px 100px}section{scroll-margin-top:65px;margin-bottom:82px}.section-label{color:var(--orange);font-size:.75rem;font-weight:800;letter-spacing:.15em}.section-title{font-size:clamp(1.75rem,3vw,2.7rem);line-height:1.18;margin:.3rem 0 1rem}.lead{font-size:1.08rem;color:#3e4b55;max-width:920px}
    .stat-grid{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;margin:28px 0}.stat{background:var(--card);border:1px solid var(--line);border-top:4px solid var(--teal);padding:18px;border-radius:10px;box-shadow:var(--shadow)}.stat strong{display:block;font-size:1.75rem;line-height:1.1;color:var(--navy)}.stat span{font-size:.78rem;color:var(--muted)}
    .pipeline{background:#132535;color:#edf6f4;border-radius:18px;padding:28px;box-shadow:var(--shadow);overflow:auto}.lane{display:grid;grid-template-columns:1.1fr 38px 1.1fr 38px 1.1fr 38px 1.1fr;align-items:stretch;min-width:950px;margin:14px 0}.node{background:#1d3b4c;border:1px solid #3d6572;border-radius:12px;padding:15px}.node.hub{background:#1c5d62;border-color:#5da5a3}.node.render{background:#514474;border-color:#8f83bc}.node.verify{background:#70482f;border-color:#ba805c}.node b{display:block;color:white}.node small{display:block;color:#bad1d3;margin-top:5px;line-height:1.4}.arrow{display:flex;align-items:center;justify-content:center;color:#74c9c2;font-size:1.5rem}.lane-title{writing-mode:vertical-rl;transform:rotate(180deg);font-size:.65rem;letter-spacing:.12em;color:#8eb4ba;position:absolute}.diagram-legend{display:flex;gap:15px;flex-wrap:wrap;font-size:.75rem;color:#c1d4d5;margin-top:20px}.dot{width:10px;height:10px;display:inline-block;border-radius:50%;margin-right:5px}
    .explain-grid,.two-col,.three-col{display:grid;gap:18px}.two-col{grid-template-columns:repeat(2,1fr)}.three-col{grid-template-columns:repeat(3,1fr)}.panel{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:22px;box-shadow:var(--shadow)}.panel h3{margin-top:0;color:var(--navy)}.step-num{display:inline-grid;place-items:center;width:30px;height:30px;border-radius:50%;background:var(--navy);color:white;font-weight:800;margin-right:6px}
    .figure-card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:24px;margin:26px 0;box-shadow:var(--shadow)}.figure-head{display:flex;justify-content:space-between;gap:15px;align-items:flex-start}.figure-head h3{font-size:1.55rem;margin:.15rem 0 1rem}.eyebrow{font-size:.7rem;letter-spacing:.14em;font-weight:800;color:var(--orange)}.badge.modeled{background:#e4eff0;color:#1c6063;white-space:nowrap}.image-button{display:block;width:100%;padding:0;border:0;background:#e9e6df;cursor:zoom-in;border-radius:10px;overflow:hidden}.image-button img{display:block;width:100%;max-height:720px;object-fit:contain}.figure-summary{font-size:1.02rem}.how-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.how-grid>div{background:#f2efe7;padding:15px;border-radius:9px}.how-grid p,.claim-grid p{margin:.35rem 0 0;font-size:.9rem}.claim-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}.claim,.boundary{padding:15px;border-left:4px solid;border-radius:6px}.claim{background:#eaf4ee;border-color:var(--green)}.boundary{background:#f8eae7;border-color:var(--red)}details{margin-top:13px;color:var(--muted)}summary{cursor:pointer;font-weight:700}
    table{width:100%;border-collapse:collapse;background:var(--card);font-size:.88rem}th,td{padding:10px 12px;text-align:left;border-bottom:1px solid var(--line)}th{background:#e9e5da;color:var(--navy)}.table-wrap{overflow:auto;border-radius:10px;border:1px solid var(--line)}
    .layer-stack{display:flex;flex-direction:column-reverse;gap:3px}.layer{height:30px;border-radius:5px;padding:4px 10px;color:white;font-size:.75rem;display:flex;justify-content:space-between}.metal{background:#557ca5}.vertical{background:#b36e33}.thermal{background:linear-gradient(90deg,#35125d,#c22f53,#f4d35e)}.logic{background:#347b60}.package{background:#6d5f55}
    pre{background:#15222e;color:#dcebe9;padding:18px;border-radius:10px;overflow:auto;font-size:.82rem;line-height:1.5}.callout{padding:18px 20px;border-radius:10px;background:#fff4d8;border-left:5px solid #d69b26}.matrix td:nth-child(2){font-weight:700}.pass{color:var(--green)}.limited{color:var(--orange)}.no{color:var(--red)}
    footer{background:#132535;color:#c9d7d7;padding:30px max(5vw,24px)}footer div{max-width:1200px;margin:auto}.modal{display:none;position:fixed;z-index:50;inset:0;background:rgba(5,12,18,.94);padding:30px;align-items:center;justify-content:center}.modal.open{display:flex}.modal img{max-width:96vw;max-height:94vh;object-fit:contain}.modal button{position:absolute;right:22px;top:18px;background:white;border:0;border-radius:50%;width:40px;height:40px;font-size:1.3rem;cursor:pointer}
    @media(max-width:900px){.stat-grid{grid-template-columns:repeat(3,1fr)}.two-col,.three-col,.how-grid,.claim-grid{grid-template-columns:1fr}.hero{padding-top:48px}}@media(max-width:520px){.stat-grid{grid-template-columns:repeat(2,1fr)}main{padding-left:15px;padding-right:15px}.figure-card{padding:15px}}
    @media print{nav,.image-button:after{display:none}.hero{padding:30px;background:#17384a!important;-webkit-print-color-adjust:exact}.figure-card,.panel,.stat{box-shadow:none;break-inside:avoid}section{margin-bottom:32px}.modal{display:none!important}}
    """

    html_doc = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>STOB-PIM 물리 시각화 파이프라인 보고서</title><style>{css}</style></head>
<body><header class="hero"><div class="hero-inner"><div class="kicker">STOB-PIM · REPRODUCIBLE VISUAL EVIDENCE</div><h1>로직 다이·TSV·열·배선을<br>논문 그림으로 바꾸는 과정</h1><p>공통 좌표 manifest에서 KLayout 2D, ParaView 3D, OpenROAD 배선 지표와 열해석 결과를 만들고, 각 그림의 주장 범위를 검증하는 전체 시각화 파이프라인을 설명한다.</p><div class="hero-meta"><span>Self-contained HTML</span><span>300 dpi + SVG</span><span>KLayout 0.30.10</span><span>ParaView 6.1.1 · RTX 4060</span><span>Not signoff</span></div></div></header>
<nav><div class="nav-inner"><a href="#overview">개요</a><a href="#architecture">전체 도식</a><a href="#coordinates">좌표·데이터</a><a href="#figures">그림 생성법</a><a href="#klayout">KLayout</a><a href="#three-d">3D</a><a href="#merge">최종 GDS 병합</a><a href="#validation">검증·한계</a><a href="#reproduce">재현</a></div></nav>
<main>
<section id="overview"><div class="section-label">01 · EXECUTIVE OVERVIEW</div><h2 class="section-title">그림은 직접 그린 장식물이 아니라, 검증된 중간 산출물의 마지막 표현이다</h2><p class="lead">이 파이프라인의 중심은 하나의 공통 좌표계다. block, TSV, micro-bump, reserved region, 배선 proxy와 온도 격자가 모두 logic die 좌하단 원점의 µm 좌표로 연결된다. 렌더러는 이 데이터를 보기 좋게 표현하지만, 값이나 연결을 새로 발명하지 않는다.</p>
<div class="stat-grid"><div class="stat"><strong>{vis['counts']['blocks']}</strong><span>logic blocks</span></div><div class="stat"><strong>{vis['counts']['tsv_bundles']}</strong><span>TSV bundles</span></div><div class="stat"><strong>{vis['counts']['tsv_shapes']}</strong><span>individual TSV shapes</span></div><div class="stat"><strong>{vis['counts']['micro_bump_shapes']}</strong><span>micro-bumps</span></div><div class="stat"><strong>{vis['counts']['thermal_bins']}</strong><span>2D thermal bins</span></div><div class="stat"><strong>{pv['files'][0]['cells']:,}</strong><span>VTU cells / candidate</span></div></div>
<div class="callout"><b>가장 중요한 해석 원칙</b><br>GPU는 많은 형상을 빠르고 선명하게 렌더링하지만, GDS·PHY pin map·power report에 없는 물리 사실을 만들어주지 않는다. 그래서 모든 출력에 <i>modeled, estimated, illustrative, placed, global-routed proxy</i> 분류와 signoff 한계를 붙인다.</div></section>

<section id="architecture"><div class="section-label">02 · PIPELINE ARCHITECTURE</div><h2 class="section-title">전체 시각화 파이프라인 구조</h2><p class="lead">왼쪽의 설계·해석 입력이 공통 좌표 허브로 모이고, 2D·3D·정량 비교의 세 갈래로 나뉜 뒤 검증 gate를 통과해 논문 그림이 된다.</p>
<div class="pipeline" role="img" aria-label="시각화 파이프라인 구조도">
  <div class="lane"><div class="node"><b>설계 입력</b><small>HBM2 architecture<br>package geometry<br>RTL physical snapshot</small></div><div class="arrow">→</div><div class="node hub"><b>Canonical floorplan IR</b><small>8×12 mm · µm<br>block / TSV / bump<br>provenance / classification</small></div><div class="arrow">→</div><div class="node"><b>후보 생성</b><small>manual · wire · thermal · balanced<br>seed 235 · hard constraints</small></div><div class="arrow">→</div><div class="node verify"><b>Geometry gate</b><small>schema · boundary · overlap<br>connectivity · round-trip</small></div></div>
  <div class="lane"><div class="node"><b>물리 근거</b><small>OpenROAD DEF/ODB/GDS<br>global route metrics<br>final routed GDS hook</small></div><div class="arrow">→</div><div class="node"><b>GDS / layer adapter</b><small>DBU · orientation · layer map<br>namespace · PHY anchors</small></div><div class="arrow">→</div><div class="node render"><b>KLayout 2D</b><small>hierarchy · metal/via · TSV<br>bump · keep-out · overlays</small></div><div class="arrow">→</div><div class="node verify"><b>Readback gate</b><small>top · bbox · layer counts<br>SHA-256 · anchor residual</small></div></div>
  <div class="lane"><div class="node"><b>열·전력 근거</b><small>mapped 4 W power<br>reference FVM · HotSpot<br>3D-ICE cross-check</small></div><div class="arrow">→</div><div class="node"><b>Field exporters</b><small>NPZ → GDS bins<br>NPZ + manifest → VTU<br>object_type / temperature_K</small></div><div class="arrow">→</div><div class="node render"><b>ParaView 3D / Matplotlib</b><small>physical Z · Z×20<br>VisRTX GPU render<br>300 dpi PNG + SVG</small></div><div class="arrow">→</div><div class="node verify"><b>Evidence gate</b><small>power conservation<br>fixed axes · captions<br>claim boundary</small></div></div>
  <div class="lane"><div class="node"><b>비교 지표</b><small>wirelength · overflow<br>temperature · cost proxy<br>Pareto / sensitivity</small></div><div class="arrow">→</div><div class="node"><b>Evidence tables</b><small>candidate_comparison.csv<br>thermal_results.csv<br>openroad_proxy_metrics.csv</small></div><div class="arrow">→</div><div class="node render"><b>Paper figure pack</b><small>6 figures · same scale<br>legends · units · provenance</small></div><div class="arrow">→</div><div class="node verify"><b>Regression package</b><small>26 floorplan tests<br>generation manifest<br>requirement matrix</small></div></div>
  <div class="diagram-legend"><span><i class="dot" style="background:#1c5d62"></i>공통 데이터 계약</span><span><i class="dot" style="background:#514474"></i>렌더링</span><span><i class="dot" style="background:#70482f"></i>검증 gate</span></div>
</div>
<div class="three-col" style="margin-top:18px"><div class="panel"><h3><span class="step-num">1</span>데이터를 고정</h3><p>좌표·단위·출처·분류를 manifest에 기록한다. 그림 생성기가 임의 좌표를 갖지 않게 한다.</p></div><div class="panel"><h3><span class="step-num">2</span>도구별 형식으로 변환</h3><p>동일 정보를 GDS/LYP, VTU, CSV/NPZ로 바꾸되 ID와 단위를 유지한다.</p></div><div class="panel"><h3><span class="step-num">3</span>표현과 근거를 함께 검증</h3><p>bbox·shape·전력·anchor·축척을 검사하고 caption에 가능한 주장과 불가능한 주장을 구분한다.</p></div></div></section>

<section id="coordinates"><div class="section-label">03 · COORDINATE & DATA CONTRACT</div><h2 class="section-title">모든 그림을 연결하는 공통 좌표와 객체</h2><div class="two-col"><div class="panel"><h3>좌표 계약</h3><ul><li>원점: logic die 좌하단</li><li>+x: 오른쪽, +y: 위쪽</li><li>길이 단위: µm</li><li>die: 8,000 × 12,000 µm</li><li>bundle anchor: 좌하단 element center</li><li>paper axis: 0–8 × 0–12 mm 고정</li></ul><p>후보가 바뀌어도 die·TSV·범례·축척이 변하지 않으므로 위치 차이를 정직하게 비교할 수 있다.</p></div><div class="panel"><h3>객체별 추적 정보</h3><ul><li><b>Block:</b> instance, rectangle, orientation, power, classification</li><li><b>TSV/bump:</b> bundle ID, signal class, rows×columns, pitch, diameter, keep-out</li><li><b>Region:</b> PHY, PDN, clock, decap, routing corridor</li><li><b>Thermal:</b> grid index, temperature_K, power_W_cell</li><li><b>Physical:</b> GDS top, DBU, layer/datatype, SHA-256, anchors</li></ul></div></div>
<h3>후보별 동일 조건 비교 데이터</h3><div class="table-wrap"><table><thead><tr><th>전략</th><th>Reference peak (°C)</th><th>Global-route WL (mm)</th><th>Overflow 합</th><th>Cost proxy</th></tr></thead><tbody>{candidate_rows}</tbody></table></div></section>

<section id="figures"><div class="section-label">04 · PAPER FIGURE PROVENANCE</div><h2 class="section-title">논문 그림 6개는 어떻게 만들어졌는가</h2><p class="lead">각 카드에서 그림을 클릭하면 확대된다. 생성 과정은 입력, 데이터 변환, 최종 렌더의 세 단계로 나누어 설명한다.</p>{figures}</section>

<section id="klayout"><div class="section-label">05 · KLAYOUT 2D</div><h2 class="section-title">KLayout은 구조를 확인하고 선택적으로 겹쳐 보는 물리 캔버스다</h2><div class="two-col"><div class="panel"><h3>현재 overlay layer map</h3><div class="table-wrap"><table><tr><th>내용</th><th>Layer</th></tr><tr><td>Die / block</td><td>100 / 110</td></tr><tr><td>TSV signal classes</td><td>120–126</td></tr><tr><td>TSV keep-out</td><td>130</td></tr><tr><td>Micro-bump classes</td><td>140–146</td></tr><tr><td>Reserved regions</td><td>150–158</td></tr><tr><td>Connectivity / labels</td><td>170 / 199</td></tr><tr><td>Thermal low→high</td><td>200–215</td></tr></table></div><p>48개 TSV와 48개 bump bundle은 각각 child cell이며, 개별 형상은 TSV 320개, bump 320개다.</p></div><div class="panel"><h3>보기 좋은 layer 조합</h3><ol><li><b>구조:</b> 100, 110, 120–146, 150–158</li><li><b>TSV/bump 확대:</b> 120–146만 켜고 thermal 200–215를 끈다.</li><li><b>열 중첩:</b> block 110과 thermal 200–215를 켠다.</li><li><b>최종 route:</b> merger가 추가한 RTL metal/via와 PHY 관련 bundle만 켠다.</li></ol><p>LYP 색은 display convention이지 실제 mask 재료색이 아니다.</p></div></div>
<div class="callout"><b>실제 배선 표현 조건</b><br>최종 routed GDS가 들어오면 metal/via polygon을 그대로 계층형 overlay에 합칠 수 있다. 현재 Figure 4는 conceptual macro global-route 지표이며 detailed-route 그림으로 해석하면 안 된다.</div></section>

<section id="three-d"><div class="section-label">06 · 3D MODEL & GPU RENDERING</div><h2 class="section-title">3D 모델은 형상 데이터와 렌더링을 분리한다</h2><div class="two-col"><div class="panel"><h3>VTU 내부 구조</h3><div class="layer-stack"><div class="layer package"><span>substrate / interposer</span><span>modeled</span></div><div class="layer logic"><span>logic die + 8 block overlays</span><span>object 1</span></div><div class="layer vertical"><span>320 TSV centerlines</span><span>object 2</span></div><div class="layer thermal"><span>21-layer temperature grid</span><span>object 0</span></div><div class="layer metal"><span>DRAM / bump repeated stack</span><span>32×16 grid</span></div></div><p>후보당 points {pv['files'][0]['points']:,}, cells {pv['files'][0]['cells']:,}. physical-Z와 Z×20 파일을 모두 저장한다.</p></div><div class="panel"><h3>GPU가 하는 일과 하지 않는 일</h3><p><b class="pass">하는 일:</b> surface/wireframe/volume을 rasterize하고 고해상도 offscreen image를 만든다. RTX 4060은 VisRTX 장치로 실제 인식됐다.</p><p><b class="no">하지 않는 일:</b> reference thermal solve, 3D-ICE solve, GDS export, 좌표 정합을 계산하지 않는다. 이 단계들은 CPU 기반이다.</p><p>향후 Blender Cycles로 TSV cylinder, Cu pillar, UBM, micro-bump와 exploded stack을 더 사실적으로 렌더할 수 있지만 치수 근거가 없는 세부 형상은 illustrative로 표시해야 한다.</p></div></div></section>

<section id="merge"><div class="section-label">07 · FINAL ROUTED GDS INTEGRATION</div><h2 class="section-title">최종 RTL GDS가 오면 배선과 TSV overlay를 안전하게 합치는 과정</h2><div class="pipeline"><div class="lane"><div class="node"><b>Final routed GDS/OASIS</b><small>path · top cell · SHA-256<br>DBU · used layers</small></div><div class="arrow">→</div><div class="node hub"><b>Merge recipe</b><small>layer map · 8 orientations<br>≥2 PHY anchors · tolerance</small></div><div class="arrow">→</div><div class="node"><b>Normalization</b><small>copy_tree DBU conversion<br>namespace · no implicit scaling</small></div><div class="arrow">→</div><div class="node verify"><b>Independent readback</b><small>bbox · layers · anchors<br>die boundary · output hash</small></div></div></div>
<div class="three-col" style="margin-top:18px"><div class="panel"><h3>입력 경로와 top cell</h3><p>어떤 GDS의 어느 최상위 hierarchy를 가져올지 지정한다. 하위 block을 top으로 잘못 선택하는 것을 거부한다.</p></div><div class="panel"><h3>Layer map과 DBU</h3><p>RTL layer/datatype을 overlay와 충돌하지 않는 의미 있는 layer로 연결한다. 서로 다른 DBU는 물리 크기를 보존하여 변환하며 임의 확대는 기본 금지다.</p></div><div class="panel"><h3>PHY anchor</h3><p>서로 떨어진 두 PHY landing 좌표를 대응 TSV/bump 좌표에 맞춘다. 한 점만 맞고 mirror/rotation이 틀린 상태를 방지한다.</p></div></div>
<p>대형 stress 검증은 392 cells, RTL 39 layer pairs, 병합 90 layer pairs, 2 anchors, 최대 residual {stress['max_anchor_residual_um']:.9f} µm, {stress['output']['bytes']/1048576:.2f} MiB GDS에서 PASS했다. 단, 입력은 stale historical GDS이므로 확장성 증거일 뿐 최종 설계 근거가 아니다.</p></section>

<section id="validation"><div class="section-label">08 · VALIDATION & CLAIM BOUNDARY</div><h2 class="section-title">보기 좋은 그림보다 먼저 확인하는 검증 gate</h2><div class="table-wrap"><table class="matrix"><thead><tr><th>Gate</th><th>상태</th><th>검사 내용</th><th>남은 한계</th></tr></thead><tbody><tr><td>Manifest geometry</td><td class="pass">PASS</td><td>schema, unit, overlap, boundary, connectivity, provenance</td><td>PHY bit-level map 미확정</td></tr><tr><td>KLayout GDS</td><td class="pass">PASS</td><td>top, 8×12 mm bbox, TSV/bump count, hierarchy, 512 bins</td><td>overlay 자체는 제조 mask 아님</td></tr><tr><td>OpenROAD candidate proxy</td><td class="limited">PASS with limits</td><td>fixed macro DEF round-trip, global route, congestion</td><td>candidate detailed route/STA/IR 없음</td></tr><tr><td>Thermal</td><td class="pass">PASS modeled</td><td>4 W conservation, residual, FVM/3D-ICE ranking cross-check</td><td>calibrated absolute 온도 아님</td></tr><tr><td>3D render</td><td class="pass">PASS</td><td>VTU counts, units, object type, physical/Z×20 구분, GPU detection</td><td>재료 미세형상 illustrative</td></tr><tr><td>Production merger</td><td class="pass">PASS</td><td>DBU, 8 orientations, layer/namespace collision, ≥2 anchors, hash</td><td>최종 GDS/PDK map 입력 대기</td></tr><tr><td>Manufacturing signoff</td><td class="no">NO</td><td>의도적으로 주장하지 않음</td><td>DRC/LVS, timing, IR, SI/PI, silicon 필요</td></tr></tbody></table></div></section>

<section id="reproduce"><div class="section-label">09 · REPRODUCTION</div><h2 class="section-title">같은 그림을 다시 만드는 명령</h2><pre># 전체 분석·시각화·회귀
.\tools\run_logic_die_floorplan_analysis.ps1

# 후보별 KLayout GDS + thermal overlay
.\.venv\Scripts\python.exe tools\export_logic_die_floorplan_gds.py `
  --manifest &lt;candidate.json&gt; --thermal-field &lt;temperature_field.npz&gt; --output &lt;dir&gt;

# ParaView VTU와 GPU 렌더
.\.venv\Scripts\python.exe tools\export_floorplan_paraview.py `
  --manifest &lt;candidate.json&gt; --thermal-field &lt;temperature_field.npz&gt; --output &lt;dir&gt;
pvpython.exe tools\render_floorplan_paraview.py --input &lt;z20.vtu&gt; --output &lt;figure.png&gt;

# 2D 논문 그림 2~6
.\.venv\Scripts\python.exe tools\generate_floorplan_paper_figures.py

# 최종 routed GDS가 있을 때
.\tools\run_final_rtl_gds_merge.ps1 -Recipe &lt;recipe.json&gt; -Force -OpenKLayout</pre>
<div class="two-col"><div class="panel"><h3>주요 도구</h3><ul><li>KLayout 0.30.10</li><li>OpenROAD 26Q3-1080</li><li>ParaView 6.1.1 / VisRTX</li><li>Matplotlib / NumPy</li><li>Reference FVM, HotSpot, 3D-ICE</li><li>gdstk, KLayout DB API, Shapely</li></ul></div><div class="panel"><h3>재현 기록</h3><ul><li>후보 seed: 235</li><li>paper output: 300 dpi PNG + SVG</li><li>generation manifest: 101 artifacts</li><li>floorplan regressions: 26 PASS</li><li>모든 입력/출력의 SHA-256 연결</li></ul></div></div></section>
</main>
<div class="modal" id="modal" role="dialog" aria-modal="true" aria-label="그림 확대"><button aria-label="닫기">×</button><img alt="확대 그림"></div>
<footer><div><b>STOB-PIM visualization pipeline report</b><br>생성 시각: {datetime.now().astimezone().isoformat(timespec='seconds')} · 보고서 자체는 외부 네트워크 의존성이 없는 단일 HTML 파일이다.<br><small>Research/provisional visualization. Not manufacturing, thermal, timing, IR-drop, SI/PI or silicon signoff.</small></div></footer>
<script>const m=document.getElementById('modal'),mi=m.querySelector('img');document.querySelectorAll('.image-button').forEach(b=>b.onclick=()=>{{mi.src=b.querySelector('img').src;mi.alt=b.querySelector('img').alt;m.classList.add('open')}});m.querySelector('button').onclick=()=>m.classList.remove('open');m.onclick=e=>{{if(e.target===m)m.classList.remove('open')}};document.addEventListener('keydown',e=>{{if(e.key==='Escape')m.classList.remove('open')}});</script>
</body></html>"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html_doc, encoding="utf-8")
    print(f"VISUALIZATION_PIPELINE_HTML PASS bytes={OUT.stat().st_size} figures=6 output={OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
