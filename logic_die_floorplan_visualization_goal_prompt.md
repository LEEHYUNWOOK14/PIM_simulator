# 로직 다이 좌표·TSV 배치 최적화 및 물리 시각화 강화 골 프롬프트

현재 `STOB_PIM2` 저장소에 이미 존재하는 HBM2 아키텍처 생성, RTL-to-3D 전력 매핑, OpenROAD 물리 구현, 열해석, 하드웨어 비용 회귀 및 KLayout 시각화 파이프라인을 폐기하거나 별도로 재구축하지 말고, **공통 좌표 모델을 중심으로 연결하고 강화**하라.

이 작업은 다른 채팅에서 진행 중인 다음 작업과 독립적으로 수행한다.

```text
실제 GR00T workload 추출
  -> BF16 trace
  -> RTL 변환
  -> 정확도 검증
  -> 구조 비교
  -> 조건부 production RTL 확장
```

진행 중인 RTL, 인터페이스, 프로토콜 및 GR00T 결과를 임의로 수정하거나 확정하지 않는다. 현재 이용 가능한 합성·배치·전력 자료는 입력 snapshot으로 소비하고, 이후 RTL 구조가 변경되면 manifest만 갱신하여 동일한 분석을 재실행할 수 있게 한다.

## 1. 최종 목표

1. logic die의 기능 블록, TSV bundle, micro-bump, PHY 예약 영역, PDN, keep-out zone 및 routing corridor를 하나의 공통 좌표계로 표현한다.
2. 열, 배선, 혼잡, 면적, TSV/범프 수, keep-out 손실, timing 및 IR-drop 관점에서 좌표 후보를 비교한다.
3. 단일 임의 가중치 최적안이 아니라 `cost_first`, `balanced`, `thermal_first` 후보와 Pareto frontier를 생성한다.
4. 후보를 OpenROAD, 기존 RTL-to-3D/열해석, 하드웨어 비용 모델로 교차 검증한다.
5. TSV를 대표 장식 도형이 아닌 bundle별 연결 대상·신호 종류·pitch·keep-out·좌표가 기록된 구조로 구체화한다.
6. KLayout에는 정확한 2D 계층과 검증 overlay를, 무료 3D viewer에는 적층·TSV·온도장을 표시하여 논문용 재현 가능한 그림을 만든다.
7. 모든 결과를 `measured`, `rtl_simulated`, `synthesized`, `placed`, `modeled`, `estimated`, `illustrative`로 구분하고 signoff 범위를 과장하지 않는다.

## 2. 반드시 재사용할 현재 기반

- `design/hbm2_architecture.json`
- `design/hbm2_package.json`
- `design/hbm2_logic_3d.py`
- `design/sky130hd_3d.py`
- `design/rtl_to_3d/input_schema.json`
- `design/rtl_to_3d/mapping_rules.json`
- `design/thermal/rtl_floorplan_mapping.json`
- `tools/generate_hbm2_architecture.py`
- `tools/collect_rtl_physical_inputs.py`
- `tools/rtl_to_3d_power_map.py`
- `tools/run_rtl_to_3d_analysis.ps1`
- `tools/run_hbm2_thermal_analysis.ps1`
- `tools/run_hbm2_hardware_cost_analysis.ps1`
- `tools/export_hbm2_hotspot.py`
- `tools/validate_hbm2_architecture.py`
- `tools/validate_hbm2_thermal.py`
- `tools/validate_hbm2_hardware_cost.py`
- `verification/rtl_to_3d/`
- `verification/hardware_cost_regression/`
- `flow/designs/sky130hd/stob_pim2/`
- `output/hbm2_arch/`
- `output/rtl_to_3d/`
- `output/hbm2_thermal/`

기존 파일의 역할과 데이터 흐름을 먼저 감사하라. 동일 기능을 수행하는 새 구현을 만들기 전에 기존 구현을 확장할 수 없는 이유를 기록한다.

## 3. 핵심 작업 원칙과 경계

- RTL과 프로토콜은 기본적으로 읽기 전용이다.
- 다른 채팅이 수정 중인 dirty worktree 파일을 덮어쓰거나 되돌리지 않는다.
- 현재 `logic_block_x_um`, `logic_block_y_um`만으로 표현된 단일 이동 모델을 다중 블록 좌표 manifest로 확장한다.
- OpenROAD에서 실배치 결과가 없는 블록은 `provisional` 또는 `illustrative` rectangle로 표시한다.
- 공개 HBM2 PHY floorplan, 제조용 TSV pin map 또는 package rule이 없으면 임의 값임을 명시하고 sensitivity range를 둔다.
- raw toggle count를 전력으로 간주하지 않는다. 전력 근거가 없으면 thermal 결과는 상대 비교로 제한한다.
- KLayout은 GDS/레이어/DRC·LVS/overlay 시각화에 사용하며 timing, routability, thermal 또는 PI signoff 근거로 단독 사용하지 않는다.
- OpenROAD 결과도 공개 PDK 기반 연구용 구현 결과로 표현하고 HBM 제조 signoff라고 주장하지 않는다.
- GPU는 3D 렌더링과 대형 결과 시각화에 우선 사용한다. CPU 기반 solver를 근거 없이 GPU solver라고 표현하지 않는다.

## 4. 공통 좌표 및 연결 데이터 계약

기존 schema와 호환되는 canonical floorplan manifest를 정의한다. 권장 경로는 다음과 같다.

```text
design/floorplan/logic_die_floorplan.schema.json
design/floorplan/logic_die_floorplan.json
design/floorplan/tsv_connectivity.csv
design/floorplan/placement_objectives.json
```

좌표계는 기존 RTL-to-3D 계약과 동일하게 die 좌하단 원점, `+x` 오른쪽, `+y` 위쪽, 길이 단위 `um`으로 고정한다.

각 logic block은 최소한 다음 필드를 가진다.

```text
instance, module, role
x_um, y_um, width_um, height_um, orientation
area_source, placement_source, status
dynamic_W, leakage_W, power_source
clock_domain, voltage_domain
traffic_endpoints, timing_criticality
movable, halo_um, allowed_region
classification, confidence, provenance
```

각 TSV/micro-bump bundle은 최소한 다음 필드를 가진다.

```text
bundle_id, kind, signal_class
source, destinations
x_um, y_um, rows, columns, pitch_um, diameter_um
keepout_um, redundancy_count
bandwidth_bits, direction
geometry_source, connectivity_source
classification, confidence, provenance
```

`signal_class`는 최소 `data`, `command_address`, `clock`, `power`, `ground`, `spare`, `unknown`을 지원한다. 실제 pin map이 없으면 channel 수준 또는 bundle 수준 연결로 유지하고 bit-level 정확도를 주장하지 않는다.

## 5. 최적화 문제 정의

### 설계 변수

- 블록별 `x`, `y`, orientation
- 선택적으로 허용되는 block aspect ratio 후보
- TSV bundle 좌표와 배열 크기
- routing corridor 폭
- block halo 및 TSV keep-out
- thermal spacing 및 symmetry constraint

### hard constraint

- die boundary 이탈 금지
- logic block 및 금지 영역 overlap 금지
- TSV/micro-bump keep-out 침범 금지
- PHY, pad, PDN, clock 및 package 예약 영역 보존
- 연결 대상 channel과 허용 영역의 일관성
- 최소 spacing, pitch 및 정렬 제약
- 고정 macro 좌표 보존
- OpenROAD에서 표현 가능한 placement region 사용

### 평가 metric

- `peak_temperature_C`
- `temperature_gradient_C_per_mm`
- `hotspot_overlap_score`
- traffic-weighted Manhattan wirelength
- TSV 접근 거리와 channel별 거리 편차
- global-route congestion 및 overflow
- setup/hold timing 지표
- static IR-drop 지표
- die/core area와 utilization
- TSV/micro-bump 개수
- keep-out 및 routing corridor로 손실된 면적
- buffer/repeater 및 PDN overhead proxy
- redundancy 및 channel balance

각 metric을 정규화한 뒤 후보 비교에 사용하되, 가중합 하나로 결론을 숨기지 않는다. 가중치, 정규화 범위 및 민감도를 출력하고 Pareto dominance 결과를 별도로 제공한다.

## 6. 페이즈별 작업

### Phase 0 — 기준선 감사와 작업 경계 고정

작업:

1. 기존 architecture, RTL-to-3D, thermal, hardware-cost, OpenROAD, KLayout 흐름의 입력·출력·명령을 표로 정리한다.
2. dirty worktree와 다른 채팅의 수정 대상 파일을 식별한다.
3. 실제 OpenROAD 배치인지, 합성 면적 기반 rectangle인지, illustrative package geometry인지 분류한다.
4. 기존 생성 결과를 변경하지 않은 상태에서 baseline 명령을 실행하고 성공·실패를 기록한다.
5. 외부 solver와 viewer 설치 여부를 검사하되 자동 설치나 환경 파괴를 하지 않는다.

산출물:

- `reports/floorplan_optimization/00_baseline_audit.md`
- `reports/floorplan_optimization/results/baseline_artifacts.json`

게이트:

- 기존 파이프라인과 새 강화 지점이 구분되어야 한다.
- baseline 실패는 숨기지 말고 환경 문제와 구현 문제를 분리해야 한다.

### Phase 1 — 공통 floorplan/TSV manifest 구현

작업:

1. canonical floorplan schema와 TSV connectivity schema를 구현한다.
2. 기존 `hbm2_package.json`, architecture JSON, OpenROAD placement CSV 및 RTL-to-3D 입력을 adapter로 읽는다.
3. schema validation, 단위 검사, provenance 및 classification 검사를 구현한다.
4. overlap, die boundary, keep-out, duplicate bundle, dangling endpoint 및 좌표계 불일치를 거부한다.
5. 기존 단일 logic block 좌표 입력에 대한 backward compatibility를 유지한다.

산출물:

- schema 및 예제 manifest
- manifest validator
- synthetic valid/invalid fixtures와 단위 테스트

게이트:

- 모든 geometry가 공통 좌표계로 round-trip되어야 한다.
- 잘못된 좌표와 connectivity가 명확한 오류로 거부되어야 한다.

### Phase 2 — TSV·micro-bump·예약 영역 상세화

작업:

1. 현재 대표 TSV 열을 channel/bundle 단위 객체로 변환한다.
2. signal, power/ground, spare TSV를 구분한다.
3. TSV 직경, pitch, keep-out 및 bundle 수에 provenance와 uncertainty range를 부여한다.
4. micro-bump와 TSV bundle 간 논리적 연결을 기록한다.
5. PHY, PDN, clock, decap 및 routing corridor용 reserved region을 추가한다.
6. exact pin map이 없는 항목은 `illustrative` 또는 `estimated`로 강제 표시한다.

산출물:

- `tsv_connectivity.csv`
- TSV/bump/reserved-region KLayout layers
- 구조 count 및 connectivity validation report

게이트:

- 화면에 보이는 TSV가 manifest의 bundle과 1:1로 추적되어야 한다.
- 장식용 TSV와 연결성이 있는 TSV를 시각적으로 구분해야 한다.

### Phase 3 — 좌표 후보 생성과 빠른 비용 평가

작업:

1. deterministic seed를 갖는 placement candidate generator를 구현한다.
2. 최소한 `manual_baseline`, `wirelength_first`, `thermal_first`, `balanced` 전략을 지원한다.
3. hard constraint를 만족하는 후보만 평가한다.
4. 초기 단계에서는 analytical wirelength, power-density, area/keep-out 및 TSV-distance proxy로 대량 후보를 탐색한다.
5. 상위 후보에 대해 weight sensitivity와 Pareto frontier를 계산한다.
6. 현재 RTL 수치가 바뀔 때 manifest 재생성만으로 다시 실행되도록 한다.

산출물:

- `output/floorplan_optimization/candidates/`
- `placement_candidates.csv`
- `pareto_frontier.csv`
- 후보 생성 seed와 재현 명령

게이트:

- 동일 입력과 seed에서 동일 결과가 나와야 한다.
- 후보 탈락 사유와 constraint violation을 추적할 수 있어야 한다.

### Phase 4 — OpenROAD 물리 검증

작업:

1. 상위 후보를 OpenROAD floorplan/macro placement region으로 변환한다.
2. 가능한 후보에 대해 legalization, global placement, global routing, congestion, STA, PDN 및 static IR-drop을 실행한다.
3. OpenROAD에서 사용할 수 없는 package/TSV 제약은 별도 pre/post validation으로 유지한다.
4. 실제 route가 없는 후보를 routed 결과처럼 표시하지 않는다.
5. 실패 후보도 실패 원인과 로그를 보존한다.

산출물:

- 후보별 DEF/GDS 또는 가능한 중간 산출물
- wirelength, overflow, timing, utilization, IR-drop 결과 CSV
- `reports/floorplan_optimization/04_openroad_validation.md`

게이트:

- 최소한 상위 후보와 baseline이 동일 조건에서 비교되어야 한다.
- tool 미설치나 PDK 부족 시 modeled 결과와 placed/routed 결과를 명확히 분리해야 한다.

### Phase 5 — 기존 열해석 파이프라인 연동

작업:

1. 후보별 block placement와 power를 기존 RTL-to-3D adapter에 전달한다.
2. 전력 근거가 같은 조건에서 후보별 steady-state 및 필요한 transient 해석을 수행한다.
3. peak temperature, gradient, hotspot 위치, die별 온도 및 energy-balance 결과를 수집한다.
4. 기존 reference solver와 HotSpot exporter를 우선 재사용한다.
5. 가능하면 무료 3D-ICE adapter를 추가하되, 기존 solver-independent IR을 유지하고 결과를 교차 비교한다.
6. GPU 사용 여부와 무관하게 solver 종류, 버전, CPU/GPU 실행 조건을 기록한다.

산출물:

- 후보별 power map 및 temperature field
- `thermal_results.csv`
- solver comparison 및 uncertainty report

게이트:

- 모든 후보에서 총전력이 보존되어야 한다.
- solver residual, energy balance 및 기존 thermal validation을 통과해야 한다.
- 전력이 estimated이면 절대 안전온도 결론을 내리지 않는다.

### Phase 6 — 하드웨어 비용 및 다목적 구조 비교

작업:

1. 기존 hardware-cost pipeline에 die/core area, TSV/bump 수, keep-out 손실, routing/PDN overhead를 연결한다.
2. 제조사 견적이 없는 비용은 normalized proxy로 유지한다.
3. baseline과 모든 상위 후보를 동일한 cost revision에서 비교한다.
4. thermal, wirelength, timing, congestion, IR-drop 및 cost를 하나의 비교표에 통합한다.
5. 후보 차이가 모델 uncertainty보다 작은 경우 공동 후보로 유지한다.

산출물:

- `candidate_comparison.csv`
- `cost_thermal_pareto.csv`
- `reports/floorplan_optimization/06_candidate_tradeoff.md`

게이트:

- 모든 수치에 evidence class와 source artifact가 연결되어야 한다.
- `cost_first`, `balanced`, `thermal_first` 후보의 선택 근거가 재현 가능해야 한다.

### Phase 7 — KLayout 및 고급 3D 시각화

작업:

1. 기존 KLayout GDS/LYP 생성기에 logic block, TSV signal class, bump, keep-out, routing corridor, PDN 및 thermal bin layer를 추가한다.
2. bundle ID와 block ID를 hierarchy 또는 properties로 추적 가능하게 한다.
3. 후보별 동일 camera/scale/legend 조건의 논문용 2D 이미지를 생성한다.
4. OpenSCAD 흐름을 유지하면서, 가능하면 무료 ParaView용 VTK/VTU 또는 Blender용 glTF/GLB exporter를 추가한다.
5. 3D 그림에는 실제 종횡비와 과장된 Z scale을 구분하고 온도 범례·단위·solver·timestep을 표시한다.
6. architecture illustration, placed/routed evidence, thermal result를 서로 다른 figure로 분리한다.

필수 논문 그림:

1. 전체 HBM2 stack 및 logic die 구조
2. logic die block과 TSV bundle 좌표도
3. baseline 대비 3개 대표 후보 배치 비교
4. OpenROAD congestion 또는 routing 결과
5. power map과 temperature heatmap
6. cost-temperature 및 wirelength-temperature Pareto plot

게이트:

- 그림의 모든 색, 축, 단위, provenance 및 signoff 한계가 caption 또는 legend에 있어야 한다.
- KLayout 색상을 온도나 실제 재료 특성처럼 오해할 여지를 제거해야 한다.

### Phase 8 — 회귀, 논문 근거 패키지 및 최종 감사

작업:

1. architecture, RTL-to-3D, thermal, hardware-cost 및 새 floorplan 검증을 한 번에 실행하는 orchestration entrypoint를 제공한다.
2. 기존 회귀를 실행하고 이번 변경으로 발생한 실패가 없는지 확인한다.
3. requirement-to-evidence matrix를 작성한다.
4. 입력 snapshot, tool/version, seed, 명령, 로그, CSV, GDS, 이미지와 보고서를 generation manifest에 연결한다.
5. 논문에서 주장 가능한 내용과 아직 주장할 수 없는 내용을 구분한다.
6. RTL 구조가 확정된 뒤 다시 실행해야 하는 항목을 handoff 목록으로 작성한다.

권장 진입점:

```powershell
.\tools\run_logic_die_floorplan_analysis.ps1
```

산출물:

- `reports/floorplan_optimization/08_final_audit.md`
- `reports/floorplan_optimization/requirement_to_evidence.csv`
- `output/floorplan_optimization/generation_manifest.json`
- `reports/floorplan_optimization/paper_figure_index.md`
- `reports/floorplan_optimization/rtl_refresh_handoff.md`

게이트:

- 필수 요구사항마다 실제 artifact와 검증 결과가 있어야 한다.
- 미검증, 추정, tool unavailable 항목이 하나라도 있으면 해당 항목을 완료 또는 signoff로 표시하지 않는다.

## 7. 무료 도구 사용 우선순위

1. **OpenROAD/OpenROAD-flow-scripts**: floorplan, placement, routing, STA, PDN, IR-drop 근거
2. **KLayout**: GDS/OASIS 계층, layer inspection, overlay, DRC/LVS 및 2D 논문 그림
3. **기존 reference thermal solver + HotSpot exporter**: 빠른 후보 탐색과 기존 회귀 유지
4. **3D-ICE**: 설치와 라이선스·재현성이 확인되는 경우 상세 3D 적층 열 교차검증
5. **ParaView 또는 Blender**: GPU를 활용한 고품질 3D 온도장과 적층 구조 시각화

새 도구는 pinned version, 공식 출처, license, 설치 명령 및 재현 명령을 기록한다. 도구를 설치하지 못한 경우 placeholder 결과를 만들지 말고 adapter와 unavailable 상태를 명시한다.

## 8. 권장 출력 구조

```text
design/floorplan/
  logic_die_floorplan.schema.json
  logic_die_floorplan.json
  tsv_connectivity.csv
  placement_objectives.json

output/floorplan_optimization/
  baseline/
  candidates/
    manual_baseline/
    wirelength_first/
    balanced/
    thermal_first/
  openroad/
  thermal/
  visualization/
  placement_candidates.csv
  pareto_frontier.csv
  candidate_comparison.csv
  generation_manifest.json

reports/floorplan_optimization/
  00_baseline_audit.md
  04_openroad_validation.md
  06_candidate_tradeoff.md
  08_final_audit.md
  requirement_to_evidence.csv
  paper_figure_index.md
  rtl_refresh_handoff.md

verification/floorplan_optimization/
  fixtures/
  test_floorplan_schema.py
  test_geometry_constraints.py
  test_tsv_connectivity.py
  test_candidate_reproducibility.py
  test_pipeline_integration.py
```

## 9. 최종 완료 조건

다음을 모두 만족한 경우에만 Goal을 완료 처리한다.

1. 기존 파이프라인을 재사용한 지점과 실제로 추가한 기능이 문서화되어 있다.
2. 공통 floorplan manifest가 schema validation과 geometry round-trip을 통과한다.
3. block, TSV, bump, keep-out 및 reserved region이 동일한 좌표계에서 추적된다.
4. invalid overlap, boundary, unit, connectivity 및 provenance 입력이 거부된다.
5. baseline과 최소 3개 목적별 후보가 동일 입력 조건으로 생성된다.
6. 후보 생성은 seed 기반으로 재현 가능하다.
7. Pareto frontier와 weight sensitivity가 생성된다.
8. 가능한 후보에 대해 OpenROAD 결과 또는 실행 불가의 구체적 근거가 존재한다.
9. 후보별 전력 보존과 열해석 검증이 수행된다.
10. 비용 결과는 실제 가격과 proxy를 구분한다.
11. KLayout에 TSV 연결, keep-out, logic block 및 thermal overlay가 구분되어 보인다.
12. 논문용 그림이 동일 축척·범례·단위와 provenance를 가진다.
13. 기존 architecture, RTL-to-3D, thermal 및 hardware-cost 회귀가 통과한다.
14. 진행 중인 RTL과 사용자 변경을 삭제하거나 덮어쓰지 않았다.
15. 모든 요구사항이 requirement-to-evidence matrix의 실제 파일·로그·수치와 연결된다.
16. 실제 GR00T/최종 RTL snapshot이 아직 확정되지 않았다면 최종 배치를 `provisional recommendation`으로 표시한다.

## 10. 최종 보고 시 반드시 포함할 내용

- 변경한 파일과 변경 이유
- 재사용한 기존 파이프라인 구성요소
- 실행한 명령과 tool/version
- baseline 및 후보 비교표
- 선택한 후보와 선택하지 않은 후보의 근거
- measured/synthesized/placed/modeled/estimated/illustrative 구분
- 테스트·OpenROAD·thermal·cost 결과
- 논문용 figure 목록과 각 그림의 주장 범위
- 남아 있는 PHY, package, SI/PI, DRC/LVS, thermal calibration 및 silicon signoff 한계
- 최종 RTL 확정 후 교체해야 할 입력과 재실행 명령

부분 구현, 파일 생성 성공, 보기 좋은 렌더링 또는 임의 좌표 하나만으로 완료 처리하지 않는다. 각 단계의 게이트를 실제 결과 파일과 검증 로그로 증명한 뒤 다음 단계로 진행하라.
