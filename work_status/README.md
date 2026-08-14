# STOB PIM2 프로젝트 진행 현황

> HBM2 메모리 가까이에 연산기를 배치하고, AI 워크로드의 데이터 이동을 줄이는 PIM 구조를 소프트웨어 시뮬레이션부터 RTL, 배치·배선, 3D 적층 연구용 GDS까지 검증하는 프로젝트입니다.

## 한눈에 보기

일반적인 컴퓨터는 연산을 프로세서에서 수행하고 데이터를 메모리에서 계속 가져옵니다. AI 모델처럼 같은 데이터를 대량으로 읽고 쓰는 작업에서는 계산보다 **데이터 이동 시간과 전력**이 더 큰 병목이 될 수 있습니다.

이 프로젝트는 HBM2의 bank 주변과 logic die에 PIM 연산기를 배치해 다음 질문에 답하려고 합니다.

1. 메모리 내부 대역폭을 활용하면 실제 AI 연산의 데이터 이동과 실행 시간을 얼마나 줄일 수 있는가?
2. bank-side PIM과 logic-die PIM을 어떻게 나눠야 다양한 AI workload에 공통으로 사용할 수 있는가?
3. 메모리 컨트롤러, command queue, buffer, broadcast/reduction network를 어떤 구조로 연결해야 하는가?
4. 시뮬레이션에서 빠른 구조가 실제 RTL 합성·배치·배선에서도 구현 가능한가?
5. 성능뿐 아니라 면적, 전력, 온도, 패키징 및 비용까지 함께 비교할 수 있는가?

현재 연구의 핵심은 **기능적으로 검증된 normalization RTL이 실제 칩 레이아웃에서도 배치·배선 가능한지 확인하는 물리 검증**입니다.

## 문제와 접근 방법

### 풀려는 문제

STOB리그 반도체 분야 6번 문제는 PIM을 실제 Edge Server 및 On-device 환경에서 활용하기 위한 기술 장벽을 찾고, 특정 workload 하나에만 맞춘 가속기가 아니라 여러 AI workload에 적용 가능한 구조와 그 효과를 제시하는 것을 요구합니다.

이 프로젝트가 다루는 장벽은 다음과 같습니다.

- CPU/GPU와 HBM 사이의 큰 데이터 이동량
- HBM channel·bank 병렬성을 충분히 사용하지 못하는 scheduling
- bank-side 연산기와 logic-die 연산기 사이의 역할 분담
- command fanout, queue backpressure, shared buffer 및 memory timing 충돌
- LayerNorm/RMSNorm의 reduction·replay·writeback 배선 집중
- RTL 규모 증가에 따른 fanout, 배치 밀도, routing congestion
- PPA, 온도, TSV·micro-bump 및 패키징 비용의 동시 평가

### 제안하는 방향

하나의 거대한 PIM 연산기를 모든 bank에 연결하는 대신 다음과 같은 **계층형 PIM 구조**를 연구합니다.

```text
Host / AI workload
└─ Memory Controller
   ├─ HBM channel scheduler와 command queue
   ├─ Logic-die PIM
   │  ├─ shared PCU pipeline
   │  ├─ broadcast queue / epoch barrier
   │  └─ shared weight·source buffer
   └─ Bank-side PIM
      ├─ bank-local MAC/MAD 및 element-wise 연산
      ├─ quad-local reduction / replay / writeback
      └─ HBM bank array
```

큰 연산과 공유 제어는 logic die에서 처리하고, 데이터가 있는 곳에서 바로 수행할 수 있는 연산은 bank-side에 배치합니다. 최근 normalization RTL에서는 16개 bank를 4개 quad로 묶는 **WBQ(Writeback Quad Slice)** 구조를 사용해 중앙 writeback 배선 집중을 줄이는 방향을 검증하고 있습니다.

## 현재까지의 핵심 성과

| 영역 | 현재 상태 | 확인된 결과 |
|---|---|---|
| HBM2 PIM cycle simulator | 구현·확장 완료 | channel/bank timing, PIM 명령, traffic 및 cycle 계측 |
| Bank-side + logic-die 계층 구조 | 구현·실험 완료 | shared scheduler, buffer, queue, backpressure 모델 비교 |
| MobileNetV4 UIB | 기능·성능 검증 완료 | 실제 UIB 출력 18,816개 일치, 여러 mapping 정책 비교 |
| GR00T normalization | workload/RTL 검증 완료 | LayerNorm/RMSNorm, FP16/BF16 구조 및 병렬화 후보 비교 |
| WBQ 기능 회귀 | 완료 | unit test와 4개 통합 조합 모두 PASS |
| Sky130HD technology mapping | 완료 | 최신 WBQ RTL 전용 mapped netlist와 hash evidence 확보 |
| Phase 3 물리 배치 | **진행 중** | floorplan·PDN·global placement 완료, resize/repair 실행 중 |
| Global/detailed route 및 GDS | 대기 | Phase 3 legal ODB 검증 후 순차 실행 |
| 열·비용·3D 구조 분석 | 연구 파이프라인 확보 | source-traceable assumption과 sensitivity 분석 제공 |

진행 상태 기준은 2026-08-14 UTC, Git `PIM_Simulator` 브랜치 `2e5365a`입니다. Phase 3은 장시간 OpenROAD 작업이므로 최종 PASS는 `3_place.odb`, `3_place.sdc`, legality audit 및 evidence manifest가 모두 생성된 뒤에만 선언합니다.

## 사용하는 도구와 시뮬레이터

| 구분 | 도구 | 프로젝트에서의 역할 |
|---|---|---|
| System simulation | C++, DRAMSim2 기반 PIMSimulator | HBM command, bank timing, PIM cycle, traffic, bandwidth 모델링 |
| Build/Test | SCons, GoogleTest | C++ simulator 빌드와 기능·성능 회귀 |
| Workload/분석 | Python, NumPy, SciPy, Matplotlib | trace 생성, metric 수집, 비교 실험, 보고서 생성 |
| AI workload | MobileNetV4 UIB, NVIDIA Isaac GR00T N1.7 | 범용성을 확인하기 위한 convolution·normalization 평가 |
| RTL | SystemVerilog | bank-side PCU, logic-die PCU, controller, adapter, normalization 구현 |
| RTL simulation | Icarus Verilog, Verilator | unit/integration test, protocol 및 lint 검증 |
| Logic synthesis | Yosys | RTL 구조 검사, generic synthesis, Sky130HD technology mapping |
| Physical design | OpenROAD-flow-scripts, OpenROAD | floorplan, placement, CTS, global/detailed route, GDS stream-out |
| Open PDK | Sky130HD | 공개 표준 셀·LEF·Liberty 기반 연구용 물리 검증 |
| Layout/3D | KLayout, gdstk, OpenSCAD | GDS readback, TSV·micro-bump overlay, 2.5D/3D 시각화 |
| 비교 모델 | DRAMsim3, CACTI, McPAT | HBM timing 및 area/power 방법론 교차 확인 |
| Thermal reference | HotSpot, 3D-ICE, compact thermal model | architecture 수준의 온도·열부담 분석과 교차검증 기준 |

OpenROAD와 Sky130HD 결과는 공개 공정을 이용한 연구용 결과입니다. 실제 HBM 제조 공정의 signoff PPA를 의미하지 않습니다.

## 주요 기술

- 64 logical channel과 HBM bank-level parallelism 모델링
- `ADD`, `MUL`, `MAC`, `MAD`, `MOV`, `FILL` PIM command 실행
- bank-only, fixed hybrid, compact hybrid, spatial-group hybrid 비교
- shared PCU pipeline과 finite command/source/broadcast queue
- epoch·ordinal·ready-mask 기반 command release와 online backpressure
- channel striping, bank-aware 및 row-interleaved buffer fill
- LayerNorm/RMSNorm reduction, replay, affine, writeback pipeline
- FP16/BF16 arithmetic 및 mixed-precision normalization
- 16-bank/4-quad WBQ locality와 wide-bus fanout 완화
- source/netlist/config/ODB/GDS SHA-256 연결
- 동일 metric collector를 이용한 architecture A/B 비교
- TSV·micro-bump·HBM overlay와 RTL GDS 좌표계 병합
- PPA·thermal·yield·cost assumption의 provenance 분리

## 전체 작업 트리

```text
STOB PIM2
├─ 1. 문제 정의와 연구 가설
│  ├─ AI memory wall과 데이터 이동 비용 정의
│  ├─ Edge Server / On-device 적용 장벽 분석
│  └─ 범용 계층형 PIM 구조와 평가 지표 정의
│
├─ 2. HBM2 PIM 시스템 시뮬레이터
│  ├─ DRAMSim2 기반 channel/rank/bank timing
│  ├─ PIM command 및 CRF/GRF/SRF 모델
│  ├─ MemoryController와 address mapping
│  ├─ bank-side PCU + logic-die PCU
│  └─ cycle/read/write/traffic/power 통계
│
├─ 3. AI workload 검증
│  ├─ GEMV / element-wise microbenchmark
│  ├─ MobileNetV4 UIB mapping
│  ├─ spatial-group / wave scheduling
│  ├─ NVIDIA GR00T N1.7 normalization inventory
│  └─ LayerNorm / RMSNorm FP16·BF16 검증
│
├─ 4. RTL microarchitecture
│  ├─ bank-local compute와 shared logic pipeline
│  ├─ broadcast queue / epoch / backpressure
│  ├─ reduction / replay / affine / writeback
│  ├─ HBM boundary adapter와 protocol
│  └─ WBQ: 16 bank → 4 quad locality
│
├─ 5. RTL 기능·구조 검증
│  ├─ SystemVerilog unit test
│  ├─ PCU → WBQ → HBM adapter integration
│  ├─ generic structural audit
│  └─ source manifest와 regression evidence
│
├─ 6. Sky130HD 물리 검증
│  ├─ Phase 0: 환경·도구·PDK provenance 고정        [완료]
│  ├─ Phase 1: 최신 WBQ 기능 기준선                [완료]
│  ├─ Phase 2: WBQ technology mapping              [완료]
│  ├─ Phase 3: floorplan·repair·placement·legalize  [진행 중]
│  ├─ Phase 4: global route와 V4 혼잡 비교          [대기]
│  ├─ Phase 5: congestion 기반 RTL 계층화 반복      [조건부]
│  ├─ Phase 6: CTS와 post-CTS route                [대기]
│  ├─ Phase 7: detailed route와 RTL GDS            [대기]
│  ├─ Phase 8: TSV·micro-bump·HBM overlay          [대기]
│  ├─ Phase 9: 최종 통합 GDS merge                 [대기]
│  └─ Phase 10: 독립 readback·재현성 감사          [대기]
│
├─ 7. 시스템 수준 평가
│  ├─ PPA와 physical feasibility
│  ├─ RTL activity → block power → 3D mapping
│  ├─ thermal sensitivity와 hotspot
│  ├─ TSV/package/yield/cost sensitivity
│  └─ workload별 성능·전력·비용 trade-off
│
└─ 8. 연구 산출물
   ├─ source와 configuration
   ├─ machine-readable JSON/CSV evidence
   ├─ HTML 보고서와 재현 명령
   ├─ RTL/ODB/GDS hash manifest
   └─ STOB_PIM2_FINAL_INTEGRATED_RESEARCH_GDS
```

## 현재 작업: Phase 3 상세 트리

Phase 3의 목적은 최신 WBQ mapped netlist를 사용해 **겹침과 placement rule violation이 없는 재사용 가능한 legal ODB checkpoint**를 만드는 것입니다. 이전 WBQ 이전 구조의 ODB는 입력으로 재사용하지 않습니다.

```text
Phase 3 — WBQ floorplan / repair / placement / legalization
├─ 3.0 입력 고정                                           [완료]
│  ├─ top: logic_die_normalization_hbm_top
│  ├─ variant: normalization_hbm_wbq
│  ├─ mapped netlist·SDC·config hash 기록
│  └─ Git / ORFS / OpenROAD version 기록
│
├─ 3.1 synthesis checkpoint 재생성                         [완료]
│  ├─ 1_1 Yosys canonicalize
│  ├─ 1_2 Yosys netlist import
│  └─ 1_synth.odb / 1_synth.sdc
│
├─ 3.2 floorplan                                           [완료]
│  ├─ die/core 크기와 33% core utilization 설정
│  ├─ macro placement 단계
│  ├─ tapcell/endcap 삽입
│  ├─ PDN 생성
│  └─ 2_floorplan.odb / 2_floorplan.sdc
│
├─ 3.3 global placement 준비                               [완료]
│  ├─ initial global placement
│  ├─ I/O pin placement
│  ├─ current pin 위치를 반영한 global placement
│  └─ 3_3_place_gp.odb checkpoint
│
├─ 3.4 resize / repair                                     [실행 중]
│  ├─ high-fanout net 분석
│  ├─ slew·capacitance·fanout repair
│  ├─ cell resize와 buffer 삽입
│  ├─ area 증가·repair 수·remaining violation 수집
│  └─ 장시간 OpenROAD 실행과 peak RSS 기록
│
├─ 3.5 detailed placement / legalization                   [대기]
│  ├─ standard-cell row 정렬
│  ├─ overlap 제거
│  ├─ placement rule 검사
│  └─ 3_place.odb / 3_place.sdc 생성
│
├─ 3.6 독립 audit                                          [대기]
│  ├─ 새 OpenROAD 프로세스에서 ODB·SDC 재개방
│  ├─ top / instance / net / boundary terminal 확인
│  ├─ legalization violation 0 확인
│  └─ 현재 파일과 audit 대상 SHA-256 일치 확인
│
├─ 3.7 evidence 동결                                       [대기]
│  ├─ wbq_placement_manifest.json
│  ├─ 03_wbq_placement_report.html
│  ├─ 실행 시간·메모리·면적·utilization 기록
│  └─ PASS / FAIL / PARTIAL 판정과 한계 기록
│
└─ 3.8 Phase 4 handoff gate                                [대기]
   ├─ placement_complete = true
   ├─ independent_reopen_and_legality_pass = true
   ├─ latest WBQ input hash 일치
   └─ legal ODB가 확인된 경우에만 global route 시작
```

Phase 3 실행과 Phase 4 이후 작업은 소유권 gate로 분리되어 있습니다. 동일한 OpenROAD 작업을 중복 실행하거나 다른 채팅이 생성 중인 checkpoint를 덮어쓰지 않습니다.

## 앞으로의 구체적인 방향

1. Phase 3 legal placement와 독립 ODB audit를 끝냅니다.
2. 같은 조건에서 WBQ global route를 실행하고 기존 V4 residual congestion `2,620`과 비교합니다.
3. 혼잡이 남으면 router option만 반복하지 않고 quad-local reduction/replay/writeback 구조를 A/B 검증합니다.
4. routability gate를 통과한 후보에 CTS와 detailed route를 적용합니다.
5. RTL routed GDS를 KLayout에서 독립적으로 다시 엽니다.
6. TSV·micro-bump·HBM overlay를 동일 좌표계로 병합합니다.
7. 입력부터 최종 GDS까지 hash-pinned recipe로 재생성 가능한지 감사합니다.
8. 성능·면적·전력·온도·비용 결과를 같은 architecture revision에 연결합니다.

## 결과를 읽는 방법

이 저장소는 결과의 강도를 다음처럼 구분합니다.

| 분류 | 의미 |
|---|---|
| `measured` | 도구 또는 시뮬레이터에서 직접 측정 |
| `rtl_simulated` | RTL testbench로 기능 확인 |
| `synthesized` | technology mapping까지 확인 |
| `placed` | 배치와 legalization까지 확인 |
| `routed_research_artifact` | 연구용 배선 결과와 GDS 확보 |
| `modeled` / `estimated` | 공개 자료와 가정에 기반한 모델 |
| `illustrative` | 구조 설명·시각화를 위한 값 |
| `unknown` | 아직 측정하거나 검증하지 않음 |

현재 목표는 제조용 signoff나 tape-out이 아니라, 재현 가능한 **연구용 placed/routed GDS**를 만드는 것입니다.

```text
RESEARCH ARTIFACT — NOT FOR FABRICATION
```

## 주요 문서와 디렉터리

| 경로 | 내용 |
|---|---|
| `src/` | C++ HBM2/PIM simulator와 controller |
| `rtl/` | bank-side·logic-die·normalization SystemVerilog RTL |
| `verification/groot_normalization/` | RTL 회귀, 합성, OpenROAD 실행·감사 스크립트 |
| `experiment/` | architecture/workload 실험과 결과 |
| `flow/designs/sky130hd/` | ORFS Sky130HD design configuration |
| `reports/final_integrated_gds_execution/` | Phase별 manifest와 HTML evidence |
| `hardware_cost/` | source-traceable area/power/yield/cost 모델 |
| `design/thermal/` | thermal configuration과 물성 provenance |
| `output/` | 생성된 분석 결과와 시각화 산출물 |
| `work_status/` | 프로젝트 진행 기록과 이 README |
| `work_status/sources/` | 외부 출처·provenance·출처 로그 중앙 인덱스 |

세부 실행 계약은 [`final_integrated_research_gds_goal_prompt.md`](../final_integrated_research_gds_goal_prompt.md), GCP 인수인계는 [`GCP_HANDOFF.md`](../GCP_HANDOFF.md), 기존 simulator 사용법은 [`PIMSimulator_GUIDE.md`](../PIMSimulator_GUIDE.md)를 참고합니다.

## 출처와 재현성

외부 논문, 제조사 공개 자료, 공개 simulator, workload repository와 thermal·cost 방법론은 [`work_status/sources/`](sources/README.md)에 모아 두었습니다. 해당 폴더는 다음을 제공합니다.

- HBM2/PIM, AI workload, physical design, thermal, cost/yield 출처 목록
- 기존 source registry와 provenance 파일의 중앙 링크
- 웹 출처가 포함된 orchestration log 스냅샷
- 원본 파일과 수집본의 SHA-256 대응표
- 측정값, 공개자료, project assumption의 구분

출처가 있다는 사실만으로 프로젝트의 모든 수치가 실측값이 되는 것은 아닙니다. 공개 근거가 없는 geometry, 제조비용, yield, thermal boundary 값은 `project_assumption`, `estimated` 또는 `illustrative`로 유지합니다.

