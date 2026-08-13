# Phase 0 — 기준선 감사와 작업 경계

감사일: 2026-08-11  
기준 commit: `eb03227e05575d37e8046418c4302963acff567b`  
작업 트리: dirty, 감사 시점 porcelain 항목 265개

## 판정

Phase 0 게이트는 **PASS WITH RECORDED OPENROAD REPRODUCIBILITY FAILURE**로 판정한다. 기존 architecture, RTL-to-3D, reference thermal, hardware-cost 및 KLayout 흐름은 현재 환경에서 다시 실행되어 통과했다. 다만 현재 OpenROAD launcher는 하드코딩된 경로와 구형 바이너리 ABI 때문에 실패하며, 보존된 GDS는 현재 RTL snapshot과 동기화된 결과가 아니다.

이 판정은 물리 설계 완료 판정이 아니다. 기존 파이프라인과 강화 지점, 데이터의 evidence class, 환경 실패와 모델 한계를 분리했다는 Phase 0 게이트 판정이다.

## 작업 경계

- `rtl/`과 프로토콜 계약은 이 목표에서 읽기 전용이다.
- 다른 채팅이 수정 중인 RTL 39개 항목을 포함한 dirty worktree를 되돌리거나 덮어쓰지 않는다.
- 현재 RTL·합성·배치·전력 자료는 timestamp와 hash가 붙은 snapshot 입력으로만 소비한다.
- floorplan 결과는 새 `design/floorplan`, `output/floorplan_optimization`, `reports/floorplan_optimization`, `verification/floorplan_optimization` 영역에 추가한다.
- 현재 공개 정보로 정확한 HBM2 PHY pin map 또는 제조 TSV rule을 증명할 수 없으므로 bundle 수준 connectivity와 sensitivity range를 사용한다.

## 기존 데이터 흐름

| 흐름 | 주요 입력 | 처리 | 주요 출력 | 현재 근거 | 강화 지점 |
|---|---|---|---|---|---|
| HBM2 architecture | `design/hbm2_architecture.json`, RTL module 이름 | 계층형 GDS/SCAD 생성 | GDS, LYP, layerstack, manifest | `illustrative` geometry, 구조 검사 PASS | 공통 좌표 manifest와 1:1 object ID 연결 |
| RTL physical collection | synthesis area, placement, block power, activity manifest | 보고서 병합·단위 정규화 | `normalized_input.json` | synthetic fixture 5 blocks | 실제 snapshot adapter와 provenance 강화 |
| RTL-to-3D mapping | normalized blocks, mapping rules, architecture | 블록을 logic/DRAM rectangle에 매핑 | `mapped_power.json` | synthetic power 4 W, 보존 PASS | 다중 logic block 좌표를 canonical manifest에서 공급 |
| reference thermal | stack/material/boundary, mapped power | 3-D finite-difference steady/transient 해석 | NPZ, VTK, PNG, CSV, summary | modeled, 미보정 | 후보별 동일 전력 비교, HotSpot/3D-ICE 교차검증 |
| hardware cost | architecture, thermal summary, uncertain parameters | 상대 비용·yield·Monte Carlo | 비교 CSV/JSON/PNG | modeled/estimated/illustrative 혼합 | TSV/bump/KOZ/corridor/PDN overhead 입력 연결 |
| OpenROAD | RTL, Sky130HD, reduced top parameters | synthesis→place→route→GDS | historical `output/output.gds` | routed integration artifact, stale | 최신 OpenROAD와 현재 workspace 경로로 재현 runner 구현 |
| KLayout | architecture GDS 또는 OpenROAD GDS | hierarchy/layer/bbox 검사 및 표시 | 2-D layout | structural visualization | block/TSV class, KOZ, corridor, violation, temperature overlay |
| OpenSCAD/Blender/ParaView | SCAD/VTK/GDS-derived geometry | 3-D 표시·렌더 | 논문용 raster/vector | viewer 설치 완료 | camera/colorbar/units/metadata를 고정한 재현 export |

## 기준선 재실행 결과

### Architecture

- 1 stack, 8 DRAM dies, 8 physical channels, 8 representative TSV groups
- top cell: `HBM2_PIM_ARCHITECTURE_NOT_SIGNOFF`
- architecture validation 및 4Hi/2x12Hi variant 회귀 PASS
- KLayout headless hierarchy 검사 PASS
- 이 GDS의 die/package/TSV geometry는 대부분 `illustrative` 또는 `estimated`이며 실제 place-and-route 결과가 아니다.

### RTL-to-3D와 열해석

- 입력: `verification/rtl_to_3d/fixtures/report_manifest.json`
- 5개 synthetic block, 총 입력/매핑 전력 4.0 W
- unit, bounds, unknown module, unmapped detection, power conservation 등 7개 테스트 PASS
- reference thermal peak: 322.581811 K, ambient 대비 22.581811 K
- 이 온도는 synthetic 4 W 입력과 미보정 재료·경계조건으로 계산된 `modeled` 값이다. 현재 RTL의 measured 또는 signoff 온도가 아니다.

### Hardware cost

- 기준 scenario: `hbm2_8hi_1stack`
- analytic identity, source traceability, monotonicity, output completeness 및 seed 재현성 검사 PASS
- die area, TSV KOZ, routing demand, defect/yield 입력 상당수가 low-confidence `illustrative` 또는 `estimated`다.
- 절대 제조비가 아니라 후보 간 normalized proxy로만 사용한다.

## 물리 산출물의 정확한 분류

| 산출물 | 분류 | 사용 가능 범위 |
|---|---|---|
| `output/floorplan_optimization/baseline/hbm2_arch/*.gds` | `illustrative` | package/stack/channel 계층과 layer 표현 |
| fixture placement rectangle | `synthetic` | adapter·validation 회귀 |
| `output/output.gds` | historical `routed` integration artifact | reduced Full-PIM hierarchy가 ORFS까지 연결됐다는 증거 |
| canonical manifest에서 새로 만드는 미배치 block | `provisional` | 좌표 탐색과 proxy 비교 |
| 향후 OpenROAD DEF/ODB에서 읽은 block | `placed` 또는 `routed` | 실행 단계와 로그가 존재하는 범위 |

기존 `output/output.gds`는 1 channel/1 bank/1 PIM block/1 PCU 축소 구성이다. KLayout top/bbox 검사는 다시 통과했지만 다음 제한이 있다.

- 생성일 2026-08-07로 현재 dirty RTL보다 오래됨
- 274,099 detailed-route violation
- antenna violation 602 nets/743 pins
- 10 ns timing 미수렴
- 따라서 DRC-clean, timing closure 또는 현재 normalization RTL의 물리 구현 증거가 아님

## OpenROAD 기준선 실패 분석

현재 `flow/run_flow.ps1` 실행 결과:

```text
PLATFORM variable not set
OpenROAD flow failed with exit code 2
```

원인은 두 층으로 분리된다.

1. launcher/config 결합 문제: `RepoRoot=/mnt/c/orfs`가 하드코딩되어 있으나 현재 시스템에 해당 경로가 없다.
2. 환경 ABI 문제: launcher가 지정하는 `/home/chandler/.local/openroad-pi/usr/bin/openroad`는 `libtclreadline-2.3.8.so`가 없어 실행되지 않는다.

새로 설치·빌드한 `/home/chandler/.local/stob-eda/openroad/bin/openroad` 26Q3는 독립 smoke test를 통과했다. Phase 4에서는 기존 flow 설계를 재사용하되 경로와 executable을 manifest/parameter로 주입하는 runner로 강화한다. 과거 GDS를 새 결과로 가장하지 않는다.

## 기존 구현을 확장하는 이유

새로운 독립 architecture/thermal/cost 구현을 만들 이유가 없다. 기존 구현에는 이미 다음 검증 가능한 기능이 있다.

- 계층형 HBM2 GDS/SCAD 생성과 KLayout 검사
- 보고서 교체형 RTL physical input collector
- 단위·bounds·unmapped·전력 보존 검사
- solver-independent mapped-power JSON
- steady/transient reference thermal solver와 VTK/NPZ export
- source classification과 seeded uncertainty를 포함한 비용 모델

따라서 canonical floorplan manifest를 이 흐름들의 공통 adapter 입력으로 추가하고, TSV connectivity와 다중 블록 좌표를 확장한다. 별도 파이프라인은 HotSpot/3D-ICE나 OpenROAD처럼 독립 solver 교차검증이 필요한 경우에만 adapter 형태로 추가한다.

## Phase 1 입력으로 넘기는 결함 목록

1. `hbm2_package.json`은 logic block 위치를 단일 `logic_block_x_um/y_um`으로만 표현한다.
2. architecture GDS의 TSV는 channel별 대표 group이며 source/destination·signal class·pitch·KOZ provenance가 없다.
3. micro-bump가 connectivity object가 아니라 규칙적 시각 요소다.
4. PHY, PDN, clock, decap, routing corridor reserved region 계약이 없다.
5. logic block placement와 OpenROAD DEF 사이의 round-trip 계약이 없다.
6. thermal mapping은 공통 candidate ID나 placement manifest hash를 기록하지 않는다.
7. cost model이 후보별 TSV/bump 수, KOZ 손실, corridor/PDN overhead를 직접 입력받지 않는다.
8. 현재 OpenROAD runner는 workspace와 tool path를 하드코딩한다.
9. HotSpot exporter는 uniform 2-D bank map만 만들며 logic-die 후보 좌표를 소비하지 않는다.
10. 3D-ICE는 설치됐지만 solver-independent IR adapter가 아직 없다.

## 재현 증거

기계 판독 가능한 명령, hash, 수치와 실패 원인은 [baseline_artifacts.json](results/baseline_artifacts.json)에 기록했다. 환경 자체의 독립 smoke 결과는 [toolchain_smoke.json](results/toolchain_smoke.json)에 있다.

Phase 0 완료는 Phase 1 schema/validator 구현을 시작할 수 있다는 뜻이며, 물리·열·비용 최적화 완료를 뜻하지 않는다.
