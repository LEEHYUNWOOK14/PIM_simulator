# HBM2 PIM 하드웨어 비용 분석 채팅 인수인계 보고서

작성일: 2026-08-12  
저장소: `LEEHYUNWOOK14/PIM_simulator`  
작업 브랜치: `PIM_Simulator`  
이 문서의 범위: **하드웨어 비용·전력·열·물리 구현 분석만 포함**

## 1. 새 채팅에서 유지해야 할 작업 경계

현재 RTL 안정화와 GR00T workload 분석은 다른 작업 흐름에서 동시에 진행
중이다. 새 채팅에서는 다음 원칙을 유지한다.

- RTL 기능이나 GR00T workload 계산 코드를 직접 수정하지 않는다.
- 다른 작업이 생성한 RTL·합성·workload 결과는 읽기 전용 입력으로만 사용한다.
- GR00T 결과와 RTL이 안정화되기 전에는 lane 수, pipeline 수, buffer 크기,
  bank별 PIM 수와 같은 최종 architecture parameter를 확정하지 않는다.
- generic Yosys cell 수를 실제 면적이라고 표현하지 않는다.
- generic topological path length를 ns 단위 timing으로 표현하지 않는다.
- synthetic 전력·면적·온도를 실측값이나 signoff 결과라고 표현하지 않는다.
- vendor GDS, 실제 수율, wafer 가격, package BOM이 없으면 상대 비교와
  불확실성 범위로만 다룬다.
- dirty worktree의 RTL·GR00T 변경은 사용자의 병행 작업이므로 staging하거나
  덮어쓰지 않는다.

## 2. 지금까지의 의사결정

### 2.1 HBM2 구조 모델

HBM2 구조를 임의로 새로 발명하지 않고 다음 계층을 결합했다.

- JEDEC HBM2: stack/die/channel/interface의 표준 구조
- SAIT PIMSimulator: bank, PIM block, timing과 프로젝트 설정의 기준
- DRAMsim3 HBM2: channel/bank/timing/refresh/thermal 교차검증
- 사용자 RTL: logic die와 bank-side PIM 확장

공개 모델은 제조사 GDS가 아니므로 DRAM cell layout, 정확한 PHY floorplan,
TSV pin map과 제조원가를 재현한다고 주장하지 않는다.

### 2.2 하드웨어 비용의 정의

하드웨어 비용은 열을 제외한 비용이 아니라 다음 다섯 축을 모두 포함한다.

1. silicon area
2. 3D package/TSV/micro-bump/interposer 복잡도
3. die/bond/TSV/assembly yield 위험
4. power/performance 및 energy
5. thermal/cooling burden

통합 cost index는 제조사 견적이 아니라 설계 대안의 상대 비교 지표다.

### 2.3 RTL과 독립적으로 먼저 수행한 작업

RTL이 완성되지 않아도 synthetic fixture로 파이프라인을 검증하고, RTL 완료
후 합성·배치·VCD/SAIF 기반 결과 파일만 교체하도록 설계했다.

## 3. 완료된 주요 구현

### 3.1 HBM2 3D 구조와 열해석

- HBM2 stack, logic die, DRAM die, TSV와 bump 구조 모델
- KLayout/OpenSCAD/GDS 기반 3D 시각화
- finite-volume 기반 steady/transient 열해석
- HotSpot 및 3D-ICE adapter/reference
- layer/block temperature, heatmap, VTK, GDS temperature bin 출력
- 열 물성·경계조건·source registry와 검증

주요 문서:

- `design/hbm2_architecture.json`
- `design/thermal/hbm2_thermal_config.json`
- `docs/HBM2_THERMAL_ANALYSIS.md`
- `references/thermal/SOURCES.md`

### 3.2 전체 하드웨어 비용 파이프라인

- area/package/yield/power-performance/thermal 분석기
- 5축 동일 가중 기하평균 기반 통합 비교
- capacity 및 thermal feasibility gate
- Monte Carlo uncertainty와 Pareto 결과
- 출처와 프로젝트 가정을 분리한 traceability
- 전자공학 전공자가 읽기 쉬운 HTML 안내서

주요 문서와 결과:

- `hardware_cost/README.md`
- `hardware_cost/config.json`
- `hardware_cost/sources.json`
- `hardware_cost/RESEARCH_BASIS.md`
- `docs/HBM2_HARDWARE_COST_GUIDE.html`
- `output/hbm2_hardware_cost/hardware_cost_report.md`

HTML에는 JEDEC, Samsung, SK hynix, SAIT PIMSimulator, DRAMsim3, CACTI,
McPAT, stacked yield, Roofline, HotSpot, 3D-ICE, NIST 물성 등 파이프라인
구성에 사용한 전체 출처와 각각의 용도·한계가 포함돼 있다.

### 3.3 RTL-to-3D power mapping adapter

다음 흐름이 구현됐다.

```text
합성 면적 + OpenROAD 배치 + VCD/SAIF 기반 block power
  -> normalized input
  -> HBM2 logic/DRAM die 좌표와 block power density
  -> 3D thermal grid
  -> thermal result
  -> hardware-cost result
```

구현 내용:

- 명시적 입력 스키마와 단위 계약
- logic die 좌표 및 channel/bank tile 좌표 매핑
- block별 area, dynamic/leakage/total power와 power density
- 미매핑 RTL block 검출
- die 영역 이탈 검출
- 입력부터 thermal grid까지 전력 보존 검증
- synthetic report 수집기와 단일 PowerShell 실행 스크립트

중요한 물리적 제한:

> VCD/SAIF는 switching activity이며 그 자체가 W 단위 전력이 아니다. 실제
> power는 합성 netlist, cell library, 전압, 주파수와 parasitic을 결합한 power
> tool 결과가 필요하다.

주요 파일:

- `design/rtl_to_3d/README.md`
- `design/rtl_to_3d/input_schema.json`
- `design/rtl_to_3d/mapping_rules.json`
- `tools/collect_rtl_physical_inputs.py`
- `tools/rtl_to_3d_power_map.py`
- `tools/run_rtl_to_3d_analysis.ps1`
- `docs/RTL_TO_3D_POWER_MAPPING_REPORT.md`

### 3.4 Hardware-cost revision regression

현재 RTL과 synthetic 물리 결과를 임시 baseline으로 고정하고 이후 revision을
같은 형식으로 비교하는 파이프라인이 구현됐다.

수집 가능한 항목:

- generic cell 수와 generic path proxy
- technology-mapped area
- critical path와 timing slack
- block별 dynamic/leakage/total power
- throughput과 Energy/op
- 최고온도와 hotspot
- baseline 및 직전 revision 대비 변화량

비용 분류:

- `bf16_fp16`
- `normalization_rounding`
- `accumulator_reduction`
- `buffer_register`
- `control_routing`

GR00T는 입력 스키마와 `pending` adapter만 만들었으며 최종 architecture
선택에는 아직 사용하지 않는다. 파이프라인은
`final_architecture_parameters_selected: true`인 입력을 거부한다.

주요 파일:

- `hardware_cost/regression/README.md`
- `hardware_cost/regression/snapshot_schema.json`
- `hardware_cost/regression/baseline_manifest.json`
- `hardware_cost/regression/gr00t_workload_schema.json`
- `hardware_cost/regression/gr00t_pending.json`
- `tools/capture_hardware_cost_revision.py`
- `tools/compare_hardware_cost_revisions.py`
- `tools/run_hardware_cost_regression.ps1`
- `tools/validate_hardware_cost_regression.py`

## 4. 현재 고정된 임시 baseline

Baseline ID: `provisional_baseline_2026_08_11`

| 항목 | 현재 값 | 증거 수준 |
|---|---:|---|
| FP16 normalization candidate | 129,805 generic cells | Yosys generic synthesis |
| FP16 generic path proxy | 666 | 구조 proxy, timing 아님 |
| BF16 normalization candidate | 104,699 generic cells | Yosys generic synthesis |
| BF16 generic path proxy | 563 | 구조 proxy, timing 아님 |
| Synthetic mapped area | 10,900,000 um² | synthetic floorplan |
| Dynamic power | 3.57 W | synthetic |
| Leakage power | 0.43 W | synthetic |
| Total mapped power | 4.0 W | synthetic |
| Peak temperature | 322.581811 K | architectural thermal model |
| Peak temperature rise | 22.581811 K | 300 K ambient 기준 |
| Hotspot | `dram_0`, grid `(0,1)` | architectural thermal model |
| Technology-mapped area | N/A | 아직 입력되지 않음 |
| Critical path/slack | N/A | 아직 입력되지 않음 |
| Throughput/Energy per op | N/A | GR00T 결과 대기 |

Baseline 파일:

- `hardware_cost/regression/revisions/provisional_baseline_2026_08_11.json`
- `hardware_cost/regression/baseline_synthesis_observations.json`

원본 Yosys 로그가 병행 작업으로 변경돼도 baseline이 움직이지 않도록 추출값과
원본 로그 SHA-256을 별도 evidence 파일에 동결했다.

## 5. 현재 논문용 출력

위치: `reports/hardware_cost_regression/`

- `paper_revision_table.csv`: revision별 전체 비교
- `paper_category_table.csv`: 비용 범주별 비교
- `paper_delta_table.csv`: baseline 및 직전 revision 대비 변화
- `paper_regression_report.md`: 논문 표 형태의 보고서
- `paper_revision_overview.png`: cell/power/temperature 개요
- `paper_category_power.png`: 범주별 power breakdown
- `validation_report.json`: 독립 검증 결과

현재 revision은 baseline 하나뿐이므로 delta는 0이며, 다음 revision부터 실제
비교 그래프가 형성된다.

## 6. 완료된 검증

- hardware-cost regression 테스트 6개 통과
- RTL-to-3D adapter 테스트 7개 통과
- category power conservation 통과
- block power conservation 통과
- source SHA-256 기록 검증 통과
- baseline delta zero 검증 통과
- 논문용 CSV/Markdown/PNG 생성 검증 통과
- final architecture parameter가 보류 상태인지 검증 통과

재실행 명령:

```powershell
.\tools\run_rtl_to_3d_analysis.ps1
.\tools\run_hardware_cost_regression.ps1
```

## 7. 관련 Git 커밋

| Commit | 내용 |
|---|---|
| `183e9c2` | 전체 하드웨어 비용 파이프라인과 최초 HTML 보고서 |
| `e9864ab` | thermal/cooling burden을 통합 비용축에 포함 |
| `1eb7330` | HTML에 전체 파이프라인 출처 목록 추가 |
| `eb4fb6f` | RTL-to-3D power mapping 파이프라인 |
| `eb03227` | 임시 baseline과 hardware-cost revision regression |

2026-08-12 확인 당시 branch HEAD는 `eb03227`이며 원격
`personal/PIM_Simulator`에 push된 상태였다. 새 채팅에서는 작업 시작 전에
반드시 `git log -1`과 `git status --short`를 다시 확인한다.

## 8. 현재 저장소 상태에 대한 주의

2026-08-12 현재 worktree에는 다른 작업 흐름이 수정 중인 RTL, GR00T 보고서,
mixed-precision 결과, floorplan 결과와 다수의 untracked 파일이 존재한다. 이들은
이 문서 작성 시점의 하드웨어 비용 작업 소유가 아니다.

새 채팅에서 지켜야 할 Git 규칙:

1. 관련 파일만 명시적으로 `git add`한다.
2. `git add .`를 사용하지 않는다.
3. RTL·GR00T·floorplan 변경을 되돌리거나 삭제하지 않는다.
4. 새 revision을 캡처할 때 입력 파일의 commit/hash와 calibration level을 기록한다.
5. 다른 작업 결과가 아직 uncommitted이면 이를 최종 논문 결과로 확정하지 않는다.

## 9. 앞으로 수행할 작업

### 우선순위 1: 새 RTL/GR00T 결과의 안정 상태 확인

새 채팅 시작 후 다음을 먼저 조사한다.

- RTL/GR00T 작업이 어느 commit까지 완료됐는가?
- 기능·정확성·합성 테스트가 모두 통과했는가?
- 사용하려는 합성/STA/power/workload 결과가 committed evidence인가?
- 결과가 후보 비교인지 최종 architecture 결정인지 구분돼 있는가?

아직 변경 중이면 읽기 전용으로 상태만 파악하고 baseline을 갱신하지 않는다.

### 우선순위 2: 두 번째 provisional revision 캡처

RTL과 산출물이 안정되면 `baseline_manifest.json`을 복사해 새 manifest를 만든다.

예시:

```text
hardware_cost/regression/manifests/revision_<date>_<name>.json
```

manifest에서 다음만 새 결과로 교체한다.

- revision ID와 label
- frozen synthesis observation
- technology-mapped area/timing/slack가 있으면 해당 값
- 새 `mapped_power.json`
- 새 thermal `summary.json`
- 사용 가능해진 GR00T workload JSON
- block category override

`primary_observation`은 해당 revision에서 평가 중인 후보를 표시할 수 있지만,
최종 architecture parameter 확정이라는 의미로 사용하지 않는다.

### 우선순위 3: 실제 물리 결과로 calibration 상향

결과가 준비되는 순서대로 다음 수준으로 교체한다.

```text
synthetic
  -> synthesis_generic
  -> technology_mapped
  -> placed
  -> activity_based
  -> post_route
  -> measured
```

특히 다음 자료가 중요하다.

- Sky130 또는 사용 PDK 기준 technology-mapped area
- STA critical path와 slack
- OpenROAD 배치 좌표와 utilization
- 실제 workload VCD/SAIF 기반 block power
- post-route parasitic 기반 power/timing

generic cell 수와 synthetic area는 실제 값이 들어와도 삭제하지 말고 이전
calibration 단계의 추적 가능한 증거로 남긴다.

### 우선순위 4: GR00T 결과를 비용 분석에 연결

GR00T 결과가 안정되면
`hardware_cost/regression/gr00t_workload_schema.json` 형식으로 adapter를 채운다.

필요 항목:

- workload name과 precision
- operation count와 bytes transferred
- active channel/bank
- PIM utilization
- latency cycles와 clock period
- throughput ops/s
- accuracy metric
- activity trace 경로

그러면 다음을 계산한다.

```text
Energy/op = mapped total power / throughput_ops_s
```

또는 completed-work 시간과 operation count가 있는 경우 동일 차원의 energy/op을
교차검증한다. GR00T 결과가 들어와도
`final_architecture_parameters_selected`는 계속 `false`로 둔다.

### 우선순위 5: 3D 열 및 비용 regression 재실행

새 block power와 placement를 이용해 다음을 실행한다.

```text
새 RTL physical reports
  -> RTL-to-3D mapping
  -> 3D thermal analysis
  -> revision snapshot
  -> baseline/previous delta
  -> paper tables and plots
```

비교에서 반드시 볼 항목:

- 정확성·안정성 개선으로 증가한 cell/area
- FP16/BF16 또는 mixed precision의 비용 차이
- normalization/rounding과 accumulator/reduction 비용
- buffer/register와 control/routing overhead
- power와 Energy/op 변화
- 최고온도와 hotspot 이동
- 성능 개선 대비 비용 증가

### 우선순위 6: 최종 architecture 선택은 마지막에 수행

다음 조건이 모두 충족된 뒤에만 parameter sweep과 Pareto 선택을 수행한다.

- RTL 기능·BF16/FP16 정확성·합성 가능성 안정화
- 실제 GR00T workload 결과 확보
- technology-mapped area/timing 확보
- activity-based power와 3D thermal 결과 확보
- capacity/temperature/timing feasibility gate 정의

그 전까지 lane 수, shared pipeline 수, buffer 크기, bank-side/logic-die 배분은
후보 범위로만 유지한다.

## 10. 새 채팅에서 바로 사용할 시작 프롬프트

아래 내용을 새 채팅에 붙여넣고 이 문서를 함께 참조하면 된다.

```text
이 저장소의 하드웨어 비용 분석 작업을 이어서 수행해줘.
먼저 docs/HARDWARE_COST_CHAT_HANDOFF_2026_08_12.md를 전부 읽고,
git log -1과 git status --short로 현재 상태를 확인해.

이 채팅에서는 하드웨어 비용·전력·열·물리 구현 분석만 수행하고,
병행 중인 RTL 및 GR00T 코드는 수정하지 마. 기존 provisional baseline은
보존하고, 새로운 RTL/GR00T/물리 결과가 안정되고 재현 가능한 증거인지 먼저
감사해. 충분한 증거가 있으면 두 번째 provisional hardware-cost revision을
캡처하고 baseline 및 직전 revision 대비 cell, technology area, timing,
block power, Energy/op, peak temperature와 hotspot 변화를 논문용 표와 그래프로
생성해. 최종 architecture parameter는 아직 확정하지 마.
```

## 11. 완료 기준

다음 단계의 작업은 아래 증거가 모두 있을 때 완료로 판단한다.

- 새 revision snapshot과 입력 source hash
- FP16/BF16 및 5개 비용 분류
- block/category/total power 보존
- technology area/timing이 없으면 명확한 `N/A`
- GR00T throughput이 없으면 Energy/op `N/A`
- 새 placement/power 기반 3D thermal 결과
- baseline 및 직전 revision delta
- 논문용 CSV/Markdown/PNG
- 독립 validation PASS
- 최종 architecture parameter가 여전히 보류 상태임을 확인

이 문서는 새 채팅의 시작점이며, 실제 저장소 상태와 최신 산출물이 항상
최종 권위 자료다.
