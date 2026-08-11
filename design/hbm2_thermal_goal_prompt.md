# HBM2 PIM 전력 매핑 및 3D 열 해석 파이프라인 골 프롬프트

현재 저장소에 RTL 수정과 독립적으로 실행되는 HBM2 PIM 전력 매핑 및 3D 열 해석 파이프라인을 구축한다.

작업 시간보다 신뢰성, 재현성, 출처 추적성 및 검증 완성도를 우선한다. 단순 시각화나 임의의 온도 색칠로 완료하지 말고, 실제 power trace를 입력받아 공간·시간별 온도를 계산하고 결과를 검증할 수 있는 전체 파이프라인을 구현한다.

## 핵심 목표

1. HBM2의 DRAM die, base/logic die, TSV, micro-bump, interposer, substrate, TIM 및 lid를 포함한 열 구조 모델을 구축한다.
2. block별·channel별·bank별 전력을 3D 공간에 매핑한다.
3. steady-state 및 transient thermal analysis를 수행한다.
4. 온도 결과를 KLayout, OpenSCAD 또는 별도 3D viewer에서 확인할 수 있게 한다.
5. 현재 수정 중인 RTL과 독립적으로 동작하게 하며 RTL은 기본적으로 수정하지 않는다.
6. 나중에 실제 RTL activity와 OpenROAD floorplan을 연결할 수 있는 입력 인터페이스를 제공한다.

## 현재 기반

- `design/hbm2_architecture.json`
- `tools/generate_hbm2_architecture.py`
- `output/hbm2_arch/`
- `ini/HBM2_samsung_2M_16B_x64.ini`
- `references/hbm2/DRAMsim3_HBM2_8Gb_x128.ini`
- `output/hbm2_arch/parameter_provenance.json`
- `output/hbm2_arch/thermal_metadata.json`

## 중요 원칙

- 기존 RTL과 사용자의 미완성 변경사항을 보존한다.
- RTL 파일은 읽기 전용 선택 입력으로만 사용한다.
- RTL 변경 없이 synthetic 또는 CSV power trace만으로 전체 열 해석이 가능해야 한다.
- 공개 근거가 없는 물성·치수·전력을 확정값으로 사용하지 않는다.
- 모든 값에 source, unit, confidence 및 classification을 기록한다.
- 실제 제조용 HBM2 layout이나 signoff thermal result라고 주장하지 않는다.
- 절대온도 결과와 상대 비교 결과의 신뢰 범위를 구분한다.
- 파일 생성 성공만으로 완료하지 말고 물리적·수치적 검증을 수행한다.

## 1. 선행 조사 및 출처 고정

다음을 조사하고 신뢰할 수 있는 1차 출처를 우선한다.

- JEDEC HBM2 stack/channel/interface 구조
- SAITPublic/PIMSimulator HBM2/PIM 구조
- DRAMsim3 HBM2 timing, power, refresh 및 thermal 구현
- HotSpot thermal model과 입력 형식
- 3D-ICE 또는 동등한 공개 3D IC thermal solver
- silicon, copper, SiO2, TIM, substrate 및 lid의 공개 열 물성
- 공개 논문의 HBM2 die thickness, TSV, micro-bump 및 package 구조
- 공개된 HBM/HBM2 온도 측정 또는 검증 사례

각 외부 자료에 대해 프로젝트/문서 이름, URL, commit 또는 버전, 파일 경로나 section, 라이선스, 실제 사용값, 단위, confidence 및 classification을 기록한다.

classification은 최소한 다음을 지원한다.

- `standard`
- `open_source_model`
- `project_config`
- `measured_public`
- `literature_estimate`
- `derived`
- `estimated`
- `illustrative`

실제 공개 HBM2 제조용 GDS, DRAM cell layout, PHY floorplan 또는 정확한 TSV pin map이 없으면 그 사실을 명시한다.

## 2. 열 구조 모델

기존 architecture model을 다음을 포함하는 열 해석용 grid/floorplan 모델로 확장한다.

- package substrate
- silicon interposer와 effective interconnect layer
- base/logic die
- PHY, channel controller, arbiter, routing, PCU/reduction 및 shared buffer
- 8개의 DRAM die
- die별 8 physical channels
- channel별 16 banks와 peripheral logic
- channel별 8 bank-side PIM blocks
- signal 및 power/ground TSV groups
- TSV keep-out zone
- die 사이와 interposer/base die 사이 micro-bump
- TIM
- heat spreader/lid
- heatsink 또는 top convection boundary

기본 구조는 1 stack, 8Hi, 8×128-bit physical channel, 1024-bit interface, 16 banks/channel, 4 bank groups/channel, 8 PIM blocks/channel이다. 프로젝트의 64 logical partitions는 물리 채널과 분리한다.

4Hi, 8Hi, 12Hi, multi-stack, pseudo-channel, TSV group 수, PIM block 수, logic block 배치 및 방열조건 변경을 설정으로 지원한다.

## 3. 재료 및 열 파라미터

각 layer와 구조에 다음 값을 부여한다.

- thickness
- thermal conductivity 또는 kx/ky/kz
- density
- specific heat
- volumetric heat capacity
- interface thermal resistance
- fill ratio
- source metadata
- confidence
- uncertainty range

최소 재료는 silicon, copper TSV, TSV liner, solder/micro-bump effective material, underfill, silicon interposer, organic substrate, TIM, copper lid 및 heatsink effective layer다.

TSV와 bump에는 detailed geometry와 fill-ratio 기반 homogenized effective model을 모두 제공하고 결과 차이를 비교한다.

## 4. 전력 입력 인터페이스

RTL 없이 동작하는 표준 power trace schema를 구현한다.

```csv
time_ns,duration_ns,stack,die,physical_channel,bank,block,power_mw,source,confidence
0,1000,0,dram_0,0,0,bank_array,3.2,synthetic,estimated
0,1000,0,dram_0,0,-1,peripheral_logic,1.1,synthetic,estimated
0,1000,0,dram_0,0,-1,bank_pim_0,7.4,synthetic,estimated
0,1000,0,logic_die,0,-1,phy,12.3,synthetic,estimated
0,1000,0,logic_die,0,-1,pcu,18.7,synthetic,estimated
```

다음 입력을 지원한다.

1. uniform power
2. single-bank hotspot
3. single-channel hotspot
4. bank-side PIM hotspot
5. logic-die PCU hotspot
6. all-channel balanced load
7. refresh-heavy load
8. bursty transient load
9. user CSV
10. 향후 simulator activity trace adapter

음수 전력, 잘못된 위치, interval 중첩, 누락 block, 단위 변환, total power 보존 및 physical/logical channel 혼동을 검증한다.

## 5. DRAM 이벤트 기반 전력 모델

SAIT PIMSimulator와 DRAMsim3를 이용해 ACT, PRE, RD, WR, REF, per-bank refresh, idle/background, power-down, bank-side PIM, logic-die PIM 및 TSV/I/O 이벤트를 전력으로 변환하는 독립 adapter를 구현한다.

```text
energy_interval = Σ(event_count × event_energy) + background_power × interval
power_interval = energy_interval / interval
```

- SAIT 설정의 `IDD*` 값이 0이면 유효한 전력 근거로 사용하지 않는다.
- DRAMsim3 또는 공개 논문 값을 사용하면 출처를 기록한다.
- source가 충돌하면 비교 보고서를 생성한다.
- voltage, clock 및 단위를 일치시킨다.
- 근거가 부족한 event energy는 `estimated`로 분류하고 sensitivity range를 제공한다.

## 6. Solver 구조

solver-independent IR을 먼저 정의한다.

- 3D grid/block floorplan
- layer order
- block geometry
- material properties
- adjacency
- boundary conditions
- power trace
- initial temperature
- timestep
- tolerance

두 solver 경로를 제공한다.

### 외부 공개 solver

HotSpot, 3D-ICE 또는 Windows에서 재현 가능한 동등한 공개 solver를 조사해 선택한다. pinned version, license, 설치/빌드 스크립트, exporter, wrapper, parser, 재현 명령 및 오류 진단을 제공한다.

### 내부 reference solver

외부 solver 없이도 검증 가능한 finite-volume 또는 equivalent RC 기반 reference solver를 구현한다.

- 3D conduction
- transient heat capacity
- top/bottom boundary
- lateral conduction
- die 간 coupling
- configurable grid
- sparse solve 가능
- residual과 수렴조건 기록
- energy conservation 검사

내부 solver를 signoff solver라고 주장하지 않는다.

## 7. 경계조건

다음을 지원한다.

- top convection
- top fixed temperature
- bottom fixed temperature
- lid/heatsink equivalent resistance
- adiabatic sidewall
- ambient temperature
- convection coefficient
- initial temperature

기본값의 출처 또는 추정 근거를 기록한다.

## 8. 해석 종류와 출력

### Steady-state

- 최대·최소·평균 온도
- die/channel/bank/logic block별 온도
- hotspot 위치
- vertical thermal gradient
- total power
- equivalent thermal resistance

### Transient

- timestep별 temperature field
- hotspot temperature versus time
- die별 temperature versus time
- thermal time constant
- peak 도달시간
- cooldown behavior
- timestep convergence

## 9. 검증

### 수치·물리 검증

- 1D multilayer slab analytic solution 비교
- uniform power symmetry
- zero-power ambient convergence
- 발생열과 boundary heat flow의 energy conservation
- grid refinement
- timestep refinement
- tolerance sensitivity
- 장시간 transient와 steady-state 비교
- 가능하면 외부 solver와 내부 solver 비교

### 구조 검증

- stack, die, channel, bank, PIM block, TSV group 및 bump layer 수
- material layer 순서
- floorplan overlap과 영역 이탈
- zero/negative thickness
- 잘못된 physical/logical channel mapping

### 회귀 시나리오

1. 4Hi uniform
2. 8Hi uniform
3. 8Hi single-bank hotspot
4. 8Hi bank-side PIM hotspot
5. 8Hi logic-PCU hotspot
6. 12Hi uniform
7. 2-stack asymmetric load
8. TSV detailed/effective 비교
9. transient burst/cooldown
10. invalid input rejection

기존 RTL을 수정하지 않았음을 확인하고 full PIM RTL 회귀 테스트도 실행한다.

## 10. Sensitivity 및 uncertainty

다음을 sweep한다.

- DRAM die thickness
- TIM thickness와 conductivity
- silicon conductivity
- interposer thickness
- bump/TSV fill ratio
- convection coefficient
- bank/PIM power
- logic die power
- ambient temperature

변수별 peak-temperature sensitivity, normalized sensitivity, best/nominal/worst case, uncertainty range와 절대온도 신뢰 한계를 보고한다.

## 11. 시각화

- die/channel/bank/logic block heatmap
- vertical cross-section
- 3D temperature-colored stack
- transient frame 또는 animation
- hotspot trajectory
- power map과 temperature map 비교

KLayout에는 temperature-bin layer, 기존 cell hierarchy, 온도 범례와 timestep 라벨을 포함한 power/temperature GDS를 생성한다.

OpenSCAD 또는 3D 출력에는 온도 색상, TSV, bump, die, interposer, TIM 및 lid를 표시한다. 실제 높이와 visualization exaggeration을 구분한다. 가능하면 self-contained HTML viewer 또는 VTK/ParaView 출력도 제공한다.

## 12. 출력 구조

```text
output/hbm2_thermal/
  inputs/
    resolved_stack.json
    resolved_materials.json
    resolved_power.csv
  solver/
    thermal_grid.json
    hotspot/
    reference_solver/
  steady/
    temperature_field.csv
    block_temperatures.csv
    summary.json
  transient/
    temperature_timeseries.csv
    frames/
  visualization/
    power_map.gds
    temperature_map.gds
    temperature_stack.scad
    heatmaps/
  validation/
    validation_report.md
    energy_balance.json
    convergence_report.json
    solver_comparison.md
  sensitivity/
    sweep_results.csv
    sensitivity_report.md
  reports/
    thermal_summary.md
    parameter_provenance.json
    uncertainty_report.md
```

## 13. 실행 진입점

```powershell
.\tools\run_hbm2_thermal_analysis.ps1
```

```powershell
.\tools\run_hbm2_thermal_analysis.ps1 `
  -PowerTrace design\thermal\power_uniform.csv `
  -Analysis transient `
  -Solver reference `
  -StackConfig design\hbm2_architecture.json
```

한글과 공백이 있는 Windows 경로를 지원한다. 구조 생성, trace 검증, solve, 결과 검증, 시각화, sensitivity sweep 및 viewer 실행도 별도 명령으로 제공한다.

## 14. 설정 파일

```text
design/thermal/hbm2_thermal_config.json
design/thermal/hbm2_materials.json
design/thermal/hbm2_boundary_conditions.json
design/thermal/power_profiles/
```

각 값은 다음 metadata를 지원한다.

```json
{
  "value": 130,
  "unit": "W/mK",
  "classification": "literature_estimate",
  "source": "...",
  "source_section": "...",
  "confidence": "medium",
  "uncertainty": {"min": 100, "max": 150}
}
```

## 15. 문서

목적, 설치법, power schema, thermal stack, 물성 출처, solver 수식과 가정, boundary condition, 단위, physical/logical channel 차이, steady/transient 해석법, 검증, sensitivity, 실제 HBM2와의 차이, 절대·상대 결과 신뢰도, 향후 RTL/OpenROAD 연결 및 실측 calibration 방법을 문서화한다.

## 16. 향후 RTL 연결 인터페이스

현재 RTL은 수정하지 않지만 다음 adapter 규격을 설계한다.

```text
VCD/SAIF 또는 simulator counters
  → module activity
  → module energy model
  → block power trace
  → thermal floorplan mapping
  → temperature field
```

모듈과 floorplan block mapping은 별도 JSON으로 관리한다. RTL module이 추가·삭제돼도 solver 자체는 변경되지 않아야 한다.

## 완료 조건

1. RTL 없이 synthetic profile로 기본 8Hi 해석이 실행된다.
2. DRAM die 8개, physical channels, banks, PIM, logic die, TSV, bumps, interposer, substrate, TIM 및 lid가 포함된다.
3. steady-state와 transient 결과를 생성한다.
4. block power가 3D 위치에 매핑된다.
5. peak temperature, hotspot, die/channel/bank별 온도를 보고한다.
6. KLayout 또는 3D viewer에서 온도 분포를 확인할 수 있다.
7. analytic slab, symmetry, energy conservation 및 convergence 검증을 통과한다.
8. 4Hi, 8Hi, 12Hi 및 multi-stack 변형을 통과한다.
9. 잘못된 physical/logical mapping을 거부한다.
10. SAIT, DRAMsim3 및 material source가 값별로 추적된다.
11. estimated/illustrative 값과 공개 근거 값을 구분한다.
12. sensitivity 및 uncertainty 결과를 생성한다.
13. 기존 RTL과 사용자 변경사항을 보존한다.
14. 기존 full PIM RTL 회귀 테스트가 통과한다.
15. 제조·signoff 결과가 아니라는 한계와 불확실성을 보고한다.
16. 모든 명령, 출력 및 검증 결과를 최종 요약한다.

부분 구현이나 placeholder를 완료로 간주하지 않는다. 각 완료 조건을 생성 파일, 테스트 출력, solver residual, energy balance 및 시각화 결과로 증명한 후에만 완료 처리한다.
