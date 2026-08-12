# HBM2 PIM 하드웨어 비용 파이프라인 인수인계

작성 기준일: 2026-08-12

저장소: `LEEHYUNWOOK14/PIM_simulator`

브랜치: `PIM_Simulator`

이 문서는 **하드웨어 비용 분석 파이프라인만** 인수인계한다. RTL 기능 구현,
GR00T 모델 실행, mixed-precision 알고리즘 개발과 floorplan 최적화 자체의 진행
내용은 포함하지 않는다. 해당 작업에서 확정된 결과가 생기면 이 파이프라인의
입력으로만 받아들인다.

## 1. 파이프라인의 목적

HBM2 PIM 설계 대안을 다음 다섯 비용축으로 비교한다.

1. `area`: logic/DRAM/PIM/TSV keep-out 면적
2. `package`: interposer, micro-bump, TSV, 접합면과 routing 복잡도
3. `yield`: logic/DRAM die, bond, TSV와 assembly 수율 위험
4. `power_performance`: 전력, 대역폭, 처리량, energy/work
5. `thermal`: 최고온도, 온도상승, 열저항, 열 여유와 냉각부담

이 파이프라인은 제조사 판매가격이나 실제 제조견적을 계산하지 않는다. 공개된
물리 사양과 명시적인 프로젝트 가정을 이용해 설계 대안의 상대 비용·효율·위험을
재현 가능하게 비교한다.

## 2. 전체 데이터 흐름

```text
HBM2 architecture JSON
        │
        ├── area ───────────┐
        ├── package ────────┤
        ├── yield ──────────┤
        │                   ├── integration
RTL physical reports       │      ├── physical metrics
        │                   │      ├── normalized indices
        ├── block area      │      ├── feasibility/Pareto
        ├── placement       │      └── uncertainty/provenance
        └── block power ────┤
                 │          │
                 └── 3D thermal
```

RTL이 아직 완성되지 않았을 때는 synthetic fixture를 사용한다. 실제 합성·배치·
전력 결과가 준비되면 동일한 입력 계약으로 파일만 교체한다.

## 3. 통합 비용 계산

각 축은 기준 설계를 1.0으로 정규화한다.

```text
area_index       = candidate area / baseline area
package_index    = candidate package burden / baseline package burden
yield_cost_index = baseline yield / candidate yield
energy_index     = candidate energy/work / baseline energy/work
thermal_index    = candidate cooling burden / baseline cooling burden
```

통합 지수는 현재 동일 가중치의 기하평균이다.

```text
combined_cost_index = exp(Σ w_i × ln(index_i))
w_area = w_package = w_yield = w_energy = w_thermal = 0.20
```

성능은 비용과 별도로 유지한다.

```text
performance_per_cost = normalized_performance / combined_cost_index
```

가중치에 따른 편향을 드러내기 위해 Pareto frontier와 Monte Carlo uncertainty도
함께 생성한다.

## 4. 구현된 구성요소

### 4.1 비용축별 분석

| 구성요소 | 위치 | 역할 |
|---|---|---|
| 공통 설정 | `hardware_cost/config.json` | baseline, scenario, 가정, 가중치와 불확실성 |
| 출처 원장 | `hardware_cost/sources.json` | 식·수치의 출처, 적용 범위와 한계 |
| Area | `hardware_cost/area/README.md` | 누적 silicon, PIM 면적, TSV KOZ |
| Package | `hardware_cost/package/README.md` | interposer, bump, TSV, bond, routing proxy |
| Yield | `hardware_cost/yield/README.md` | negative-binomial die yield와 3D 적층 수율 |
| Power/performance | `hardware_cost/power_performance/README.md` | bandwidth, power, energy와 performance |
| Thermal | `hardware_cost/thermal/README.md` | 3D 열 결과와 cooling burden |
| Integration | `hardware_cost/integration/README.md` | 정규화, 기하평균, feasibility, Pareto |
| 실행기 | `tools/run_hbm2_hardware_cost.py` | 전체 비용 계산과 보고서 생성 |
| 검증기 | `tools/validate_hbm2_hardware_cost.py` | 수식·단위·출처·출력 invariant 검증 |

### 4.2 RTL-to-3D 전력 매핑

합성 면적, OpenROAD 배치와 VCD/SAIF 기반 block power를 HBM2 stack의 공간
전력분포로 변환한다.

```text
synthesis area CSV + placement CSV + block power CSV
    -> normalized_input.json
    -> mapped_power.json
    -> 3D thermal grid
```

주요 파일:

- `design/rtl_to_3d/input_schema.json`
- `design/rtl_to_3d/mapping_rules.json`
- `tools/collect_rtl_physical_inputs.py`
- `tools/rtl_to_3d_power_map.py`
- `tools/run_rtl_to_3d_analysis.ps1`

검증 항목:

- 길이·면적·전력 단위
- die 영역 이탈
- channel/bank 좌표 범위
- 미매핑 block
- input → mapped block → thermal grid 전력 보존

VCD/SAIF는 activity이지 W 단위 전력이 아니다. 실제 block power는 netlist,
cell library, 전압, 주파수와 parasitic을 이용한 power tool 결과여야 한다.

### 4.3 Revision regression

RTL/물리 결과 revision별 비용 변화를 동일한 형식으로 보존한다.

수집 항목:

- FP16/BF16 generic cell과 structural path proxy
- technology-mapped area
- critical path와 slack
- block별 dynamic/leakage/total power
- throughput과 Energy/op
- 최고온도와 hotspot
- baseline 및 직전 revision 대비 변화

비용 범주:

- `bf16_fp16`
- `normalization_rounding`
- `accumulator_reduction`
- `buffer_register`
- `control_routing`

주요 파일:

- `hardware_cost/regression/baseline_manifest.json`
- `hardware_cost/regression/snapshot_schema.json`
- `hardware_cost/regression/category_rules.json`
- `tools/capture_hardware_cost_revision.py`
- `tools/compare_hardware_cost_revisions.py`
- `tools/validate_hardware_cost_regression.py`
- `tools/run_hardware_cost_regression.ps1`

## 5. 현재 provisional baseline

Baseline ID: `provisional_baseline_2026_08_11`

| Metric | 값 | Calibration |
|---|---:|---|
| FP16 candidate | 129,805 generic cells | `synthesis_generic` |
| FP16 path proxy | 666 | timing 아님 |
| BF16 candidate | 104,699 generic cells | `synthesis_generic` |
| BF16 path proxy | 563 | timing 아님 |
| Mapped area | 10,900,000 um² | `synthetic` |
| Dynamic power | 3.57 W | `synthetic` |
| Leakage power | 0.43 W | `synthetic` |
| Total power | 4.0 W | `synthetic` |
| Peak temperature | 322.581811 K | `synthetic_architectural` |
| Peak rise | 22.581811 K | 300 K ambient 기준 |
| Hotspot | `dram_0`, grid `(0,1)` | architectural thermal grid |
| Technology area | N/A | 아직 입력 없음 |
| Critical path/slack | N/A | 아직 입력 없음 |
| Throughput/Energy-op | N/A | workload 결과 대기 |

Baseline snapshot:

`hardware_cost/regression/revisions/provisional_baseline_2026_08_11.json`

합성 관측값은 원본 로그 SHA-256과 함께
`hardware_cost/regression/baseline_synthesis_observations.json`에 동결돼 있다.

## 6. 현재 비용 결과

기준 HBM2 8Hi 1-stack PIM을 1.0으로 정규화한 기존 architectural 비교는
다음과 같다.

| Scenario | Thermal | Combined cost | Performance | Performance/cost | 비고 |
|---|---:|---:|---:|---:|---|
| 4Hi 1-stack PIM | 0.619 | 0.661 | 1.000 | 1.513 | 4GB, 용량 미달 |
| 8Hi 1-stack PIM | 1.000 | 1.000 | 1.000 | 1.000 | 기준 |
| 12Hi 1-stack PIM | 1.469 | 1.381 | 1.000 | 0.724 | 비용·냉각부담 증가 |
| 8Hi 2-stack PIM | 2.000 | 1.854 | 2.000 | 1.079 | Pareto 후보 |
| 8Hi 1-stack no-PIM | 0.870 | 1.061 | 0.556 | 0.524 | 비교 후보 |

이 표의 power/performance와 절대 면적은 architectural assumption이므로 실제
RTL·workload 결과가 들어오면 반드시 다시 생성한다.

## 7. 생성되는 보고서

### 전체 하드웨어 비용

위치: `output/hbm2_hardware_cost/`

- `hardware_cost_report.md`
- `integrated_metrics.json`
- `design_comparison.csv`
- `pareto_frontier.csv`
- `uncertainty_summary.csv`
- `source_traceability.md`
- `validation/validation_report.md`

### Revision regression

위치: `reports/hardware_cost_regression/`

- `paper_revision_table.csv`
- `paper_category_table.csv`
- `paper_delta_table.csv`
- `paper_regression_report.md`
- `paper_revision_overview.png`
- `paper_category_power.png`
- `validation_report.json`

### 설명 및 출처

- `docs/HBM2_HARDWARE_COST_GUIDE.html`
- `docs/RTL_TO_3D_POWER_MAPPING_REPORT.md`
- `hardware_cost/RESEARCH_BASIS.md`
- `hardware_cost/sources.json`

## 8. 실행 명령

전체 architectural 비용 분석:

```powershell
.\tools\run_hbm2_hardware_cost_analysis.ps1
```

RTL-to-3D mapping부터 열·비용 분석까지:

```powershell
.\tools\run_rtl_to_3d_analysis.ps1
```

현재 revision baseline과 논문용 비교자료 생성:

```powershell
.\tools\run_hardware_cost_regression.ps1
```

새 revision은 새 manifest를 만든 뒤 캡처한다.

```powershell
.\.venv\Scripts\python.exe tools\capture_hardware_cost_revision.py `
  --manifest path\to\new_revision_manifest.json `
  --output hardware_cost\regression\revisions\new_revision.json

.\.venv\Scripts\python.exe tools\compare_hardware_cost_revisions.py `
  --revisions hardware_cost\regression\revisions `
  --baseline provisional_baseline_2026_08_11 `
  --output reports\hardware_cost_regression
```

## 9. 현재 검증 상태

- hardware-cost regression 테스트 6개 PASS
- RTL-to-3D adapter 테스트 7개 PASS
- block/category/total power conservation PASS
- source SHA-256와 provenance 검사 PASS
- paper CSV/Markdown/PNG 생성 검사 PASS
- baseline delta zero 검사 PASS
- 전체 비용 파이프라인 formula/source/output 검사 PASS

검증이 의미하지 않는 것:

- 제조사 HBM2 layout 검증
- 실제 제조수율 검증
- 실제 wafer/package 가격 검증
- silicon power 또는 thermal signoff

## 10. 인수인계 후 다음 작업

### 10.1 새 입력의 증거 수준 감사

새 합성·배치·전력·workload 결과가 들어오면 먼저 다음을 확인한다.

- 결과가 완료된 command에서 생성됐는가?
- 사용한 Git commit, PDK/library와 tool version이 기록됐는가?
- generic synthesis인지 technology-mapped 결과인지 구분됐는가?
- power가 synthetic인지 activity-based인지 구분됐는가?
- 원본 파일 hash가 기록됐는가?

증거가 불완전하면 baseline을 교체하지 않고 후보 revision으로만 보존한다.

### 10.2 두 번째 provisional revision 생성

새로운 안정된 물리 결과가 생기면 다음 값을 manifest에 연결한다.

- synthesis observation
- technology-mapped area
- critical path와 slack
- placement와 block power
- thermal summary
- throughput 또는 completed-work timing

그 후 baseline과 직전 revision 대비 delta를 생성한다. 최종 architecture 선택은
하지 않는다.

### 10.3 Calibration 상향

다음 순서로 synthetic 값을 실제 결과로 교체한다.

```text
synthetic
 -> synthesis_generic
 -> technology_mapped
 -> placed
 -> activity_based
 -> post_route
 -> measured
```

값을 교체할 때 이전 calibration 결과를 삭제하지 않고 별도 revision으로 남긴다.

### 10.4 Energy/op 연결

안정된 throughput이 주어지면 다음을 계산한다.

```text
Energy/op = mapped total power / throughput_ops_s
```

또는 총 에너지, completed operation count와 실행시간으로 독립 교차검증한다.
workload 결과가 없을 때는 `N/A`를 유지한다.

### 10.5 열 및 비용 재계산

새 placement와 block power마다 3D 열해석을 다시 실행한다. 반드시 비교할 항목:

- peak temperature와 thermal headroom
- hotspot layer/coordinate 이동
- category별 power density
- area/power/energy/thermal의 baseline delta
- feasibility와 Pareto 상태 변화

### 10.6 최종 분석 단계

technology area/timing, activity power, workload throughput과 3D thermal 결과가
모두 준비된 후에만 architecture parameter sweep과 최종 Pareto 선택을 수행한다.

## 11. 작업 시 주의사항

- dirty worktree의 RTL·workload 변경을 staging하거나 되돌리지 않는다.
- `git add .`를 사용하지 않고 하드웨어 비용 관련 파일만 명시한다.
- generic cell을 mm²로 임의 변환하지 않는다.
- topological path를 ns로 취급하지 않는다.
- 미측정 값을 0으로 쓰지 않고 `null`/`N/A`로 기록한다.
- `normalization_rounding`의 physical cost가 0이고 calibration이
  `not_available`이면 “비용이 0”이 아니라 “물리 매핑 데이터가 없음”이다.
- 모든 새 snapshot은 source hash와 calibration level을 포함해야 한다.
- `final_architecture_parameters_selected`는 충분한 실측·workload 증거가 생기기
  전까지 `false`로 유지한다.

## 12. 관련 커밋

| Commit | 하드웨어 비용 파이프라인 작업 |
|---|---|
| `183e9c2` | 최초 전체 비용 분석 파이프라인 |
| `e9864ab` | thermal/cooling burden 통합 |
| `1eb7330` | 전체 출처 목록 문서화 |
| `eb4fb6f` | RTL-to-3D power mapping |
| `eb03227` | provisional baseline과 revision regression |

새 작업을 시작할 때 현재 HEAD와 worktree 상태를 다시 확인한다. 이 문서의 수치보다
저장소의 최신 snapshot·validation 결과가 우선한다.

## 13. 새 채팅 시작 프롬프트

```text
HBM2 PIM 하드웨어 비용 분석 파이프라인 작업을 이어서 수행해줘.
먼저 docs/HARDWARE_COST_PIPELINE_HANDOFF.md를 전부 읽고 git log -1,
git status --short, 현재 regression validation 결과를 확인해.

하드웨어 비용·전력·열·물리 분석 범위만 다루고 다른 작업의 RTL이나 workload
코드는 수정하지 마. 기존 provisional baseline과 source hash를 보존해. 새로운
합성·배치·power·throughput 결과가 재현 가능한 증거인지 먼저 감사하고, 충분하면
두 번째 provisional revision으로 캡처하여 baseline 및 직전 revision 대비 area,
cell, timing, block power, Energy/op, peak temperature와 hotspot delta를 논문용
표와 그래프로 생성해. 근거가 없는 값은 N/A로 두고 최종 architecture parameter는
아직 확정하지 마.
```
