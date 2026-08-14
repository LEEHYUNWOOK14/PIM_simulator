# STOB PIM2 최종 통합 연구용 GDS 장기 실행 골 프롬프트

### 현재 실행 소유권

- VS Code는 Phase 3 OpenROAD 완료, audit, evidence, 보고서, commit/push까지만 수행한다.
- VS Code는 Phase 4를 시작하지 않는다.
- Phase 4~10의 실행 소유자는 CLI다.
- `reports/final_integrated_gds_execution/CLI_OWNS_PHASE4` 파일을 삭제하거나 우회하지 않는다.
- Phase 4 이후 watcher를 생성하거나 재생성하지 않는다.

CLI 실행 전략:

- Phase 4는 Phase 3 legal ODB를 재사용한다.
- Phase 5 후보는 fast placement/route로 선별하고 최종 후보만 full resize한다.
- Phase 6은 CTS/post-CTS checkpoint를 재사용한다.
- Phase 7은 fast DRT로 수렴성을 확인한 뒤 최종 후보만 full DRT를 수행한다.
- 최종 후보에는 전체 기능·합성·배치·CTS·배선·GDS 검증을 수행한다.

## 0. 이 문서의 지위와 사용법

이 문서는 `STOB_PIM2`의 장시간 자율 작업을 위한 최상위 실행 계약이다. 작업자는 서버에서 작업을 시작할 때, 각 Phase를 시작할 때, 장시간 도구 실행이 끝났을 때, 실패 후 방향을 바꿀 때 반드시 이 파일을 다시 읽는다.

이 문서보다 구체적인 최신 사용자 지시가 있으면 사용자 지시를 우선한다. 기존 저장소의 근거, 테스트, 보고서와 충돌하는 추정을 사실로 취급하지 않는다.

작업 루트:

```text
/home/forstobpim/PIM_simulator
```

기준 계획서:

```text
reports/final_integrated_gds_plan/final_integrated_gds_project_plan.html
```

핵심 인수인계 문서:

```text
GCP_HANDOFF.md
```

장시간 작업의 기본 반복 단위는 다음과 같다.

```text
골 프롬프트 재확인
→ 현재 Git/도구/디스크/메모리 상태 확인
→ 한 가지 명확한 가설 또는 마일스톤 실행
→ 결과 검증
→ compact evidence와 HTML 보고서 갱신
→ 커밋 및 origin/PIM_Simulator 푸시
→ 원격 반영 확인
→ 다음 단계 결정
```

## 1. 최종 목표

최종 목표는 제조용 signoff나 tape-out이 아니라 다음 연구 산출물을 만드는 것이다.

> 현재 통합 normalization RTL을 공개 Sky130HD 연구용 flow에서 합성·배치·배선하여 RTL GDS를 생성하고, TSV·micro-bump·HBM floorplan overlay를 동일 좌표계에서 병합한 단일 연구용 GDS를 만든다. 모든 입력, 실행 명령, 도구 버전, 해시, 측정값, 실패와 한계를 재현 가능한 evidence로 동결한다.

최종 산출물 권장 명칭:

```text
STOB_PIM2_FINAL_INTEGRATED_RESEARCH_GDS
```

최종 병합 파일:

```text
output/final_integrated_gds/final/merged_final_physical.gds
```

이 결과는 논문 그림, 구조 검토, 재현성 검증, 후속 열·전력·비용 분석을 위한 `placed/routed research artifact`다. `Final`은 이 연구 프로젝트의 최종 결과라는 뜻이며 제조 승인이나 tape-out 준비 완료를 뜻하지 않는다.

## 2. 명시적 비목표와 주장 경계

다음은 프로젝트 완료 조건이 아니다.

- foundry signoff
- tape-out 승인 또는 제조 인계
- proprietary HBM PHY 검증
- 제조용 DRC/LVS closure
- IR/EM signoff
- 실제 wafer fabrication, packaging, silicon bring-up
- 공개 Sky130 proxy 결과를 실제 HBM 공정 PPA로 표현하는 것

상세 배선 이후 남은 DRC, antenna, timing, slew, fanout, capacitance 위반은 숨기지 않고 수치로 기록한다. 그러나 이 연구의 범위를 제조 signoff closure로 확장하지 않는다.

모든 주장은 최소한 다음 분류 중 하나를 가져야 한다.

```text
measured
rtl_simulated
synthesized
placed
routed_research_artifact
modeled
estimated
illustrative
unknown
```

## 3. 현재 기준선

작업 시작 시 실제 파일과 Git 이력으로 다시 확인하되, 현재 알려진 기준선은 다음과 같다.

- production normalization top: `logic_die_normalization_hbm_top`
- 최신 구조 변경: `normalization_writeback_quad_slice`
- 최신 구조의 unit backpressure test: PASS 기록
- PCU→quad slice→HBM adapter 통합 회귀: 4/4 PASS 기록
- 기존 물리 결과는 quad slice 이전 netlist 기반이므로 최신 결과로 재사용 금지
- 기존 최선 V4 global-route residual congestion: 2,620
- 기존 V4 detailed congestion entries: 5,998
- 기존 V4 overflow entries: 2,003
- 기존 분석상 writeback이 가장 큰 실제 hotspot 후보
- 공식 기존 판정: `FAIL_CURRENT_FLAT_PHYSICAL_ARCHITECTURE_NOT_PROVEN`

기존 V4/V5/V7/V8 ODB, route guide 또는 보고서를 최신 `wbq` 결과로 오인하지 않는다. 최신 RTL의 source hash와 mapped netlist hash가 연결되지 않은 산출물은 비교용 historical evidence로만 사용한다.

## 4. 절대 작업 원칙

### 4.1 정확성

- 성공을 exit code 하나로 판정하지 않는다. 필수 파일, log marker, tool check, hash, metric을 함께 확인한다.
- 실패, timeout, OOM, signal termination, partial output을 PASS로 포장하지 않는다.
- `0`과 `unknown`, 측정되지 않음과 위반 없음, skipped net과 routed net을 구분한다.
- 툴 로그의 서로 다른 congestion 정의를 혼용하지 않는다. V4 비교 시 동일 collector와 동일 metric 정의를 우선한다.
- 결과가 예상과 다르면 결과를 맞추기 위해 validator를 완화하지 않는다.

### 4.2 실험 규율

- 한 실험에서는 가능한 한 하나의 독립 변수만 변경한다.
- 각 실험은 hypothesis, inputs, commands, versions, resource use, outputs, verdict, next decision을 기록한다.
- 기존 최선 결과와 current control run을 모두 보존한다.
- random seed가 있는 도구는 seed를 기록한다.
- 새 구조는 기능 회귀를 통과하기 전 대형 P&R에 투입하지 않는다.
- 새 RTL netlist는 새 variant 이름을 사용하며 이전 결과를 덮어쓰지 않는다.

### 4.3 장시간 실행과 복구

- OpenROAD 장시간 실행은 재접속 후에도 유지되는 방식으로 실행하고 PID, 시작 시각, 명령, log path를 기록한다.
- 동일한 대형 OpenROAD 작업을 중복 실행하지 않는다.
- 실행 전 가용 RAM, swap, 디스크를 기록하고, 실행 중 peak RSS와 디스크 증가량을 가능한 범위에서 수집한다.
- 각 대형 단계는 재시작 가능한 ODB/SDC checkpoint를 만든다.
- 중단된 결과는 `interrupted`, `timeout`, `oom`, `tool_error`, `design_fail` 중 하나로 분류한다.
- 실패 시 같은 명령을 무한 반복하지 않는다. 원인과 다음 변경 변수를 먼저 문서화한다.

### 4.4 저장소 안전

- 사용자 또는 다른 작업자가 만든 변경을 reset, restore, clean, overwrite하지 않는다.
- 대형 ODB, route guide, VCD, raw log, 임시 netlist는 Git에 넣지 않는다.
- compact JSON/CSV/Markdown/HTML, 실행 스크립트, config, manifest, checksum은 Git에 보존한다.
- 50 MB 이상 파일은 커밋 전에 반드시 크기와 필요성을 검토한다.
- credential, token, 개인 경로의 민감 정보는 커밋하지 않는다.

## 5. Git·푸시·보고 의무

### 5.1 체크포인트 원칙

다음 사건마다 독립적인 논리 커밋을 만들고 `origin/PIM_Simulator`에 푸시한다.

- 환경 복원 및 portability 수정 완료
- 최신 `wbq` 기능 회귀 완료
- technology mapping 완료 또는 의미 있는 실패 확정
- floorplan/repair/legalization 완료
- global route 실험 한 revision 완료
- CTS/clock distribution 완료
- detailed route 완료 또는 구조적 실패 확정
- RTL GDS stream-out 및 readback 완료
- overlay 동결 완료
- 최종 병합 완료
- 최종 독립 검증 및 보고서 완료
- RTL/microarchitecture 변경을 수반한 각 구조 개선 완료

커밋 전에는 반드시 다음을 확인한다.

```bash
git status --short
git diff --check
git diff --stat
```

관련 테스트와 validator가 통과한 경우에만 해당 단계의 PASS 커밋을 만든다. 실패도 재현 가능하고 다음 의사결정에 중요한 경우 `Record ... failure evidence` 형태의 체크포인트로 커밋할 수 있다.

푸시 후 다음을 확인한다.

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/PIM_Simulator
git status --short --branch
```

원격 push가 실패하면 로컬 커밋 SHA와 실패 원인을 보고서에 남기고 재시도한다. 원격 반영을 확인하지 않은 상태를 “푸시 완료”라고 표현하지 않는다.

### 5.2 HTML 보고 의무

큰 작업이 끝날 때마다 사람이 읽을 수 있는 HTML 보고서를 생성·갱신하고 함께 커밋·푸시한다. 큰 작업에는 synthesis, placement, global route, CTS, detailed route, GDS stream-out, overlay merge 및 주요 RTL 구조 변경이 포함된다.

권장 보고 경로:

```text
reports/final_integrated_gds_execution/
├─ 00_environment_and_baseline_report.html
├─ 01_wbq_functional_regression_report.html
├─ 02_wbq_synthesis_report.html
├─ 03_wbq_placement_report.html
├─ 04_wbq_global_route_report.html
├─ 05_hierarchical_architecture_report.html
├─ 06_clock_and_detailed_route_report.html
├─ 07_rtl_gds_report.html
├─ 08_overlay_merge_report.html
└─ 09_final_completion_report.html
```

각 HTML은 최소한 다음을 포함한다.

- 목표와 실행 시각
- Git SHA와 dirty 상태
- 입력 RTL/netlist/config/Liberty/LEF/SDC 해시
- 도구 및 OS 버전
- 정확한 재현 명령
- 실행 시간, peak memory, 주요 파일 크기
- 핵심 metric 표
- 이전 기준선과의 동일 정의 비교
- PASS/FAIL/PARTIAL/UNKNOWN 판정
- 실패 원인과 증거 링크
- claim boundary와 known limitations
- 다음 단계와 그 선택 근거

HTML만 만들고 machine-readable evidence를 생략하지 않는다. 주요 수치는 JSON 또는 CSV에도 저장하고 HTML이 이를 읽거나 동일 source에서 생성되게 한다.

## 6. Phase 0 — 서버 환경과 기준선 동결

### 목표

현재 GCP 서버에서 모든 후속 결과의 provenance를 보장할 실행 환경을 만든다.

### 작업

1. Git branch, HEAD, remote, dirty state를 기록한다.
2. CPU, RAM, swap, disk, OS, kernel을 기록한다.
3. GCC/G++, Python, SCons, Icarus, Verilator, Yosys, OpenROAD, KLayout 버전을 기록한다.
4. ORFS를 인수인계 기준 commit `56496f3980fb6e9e58f10c8aea4a98949c0fe5f2`로 복원하고 submodule 상태를 기록한다.
5. 가능한 경우 OpenROAD 기준 commit `ab6fd26351dc449e69059684dc6aa9ae9046eb36`과 일치시키고, 다르면 정확한 차이를 기록한다.
6. Sky130HD platform, LEF, Liberty를 확인하고 대표 Liberty SHA-256을 기존 기록과 비교한다.
7. `/home/chandler`, `/mnt/c/orfs` 및 Windows 경로 하드코딩을 전수 조사한다.
8. 경로는 환경변수 또는 repository-relative default로 이식 가능하게 수정한다. 현재 서버의 절대 경로만 다른 하드코딩으로 치환하지 않는다.
9. 환경 preflight 스크립트를 만들어 executable, file, version, disk/RAM 조건을 자동 검사한다.

### 필수 산출물

- 환경 manifest JSON
- portability audit
- preflight script
- `00_environment_and_baseline_report.html`

### 게이트

- ORFS/OpenROAD/Sky130HD 입력 경로가 실제로 존재한다.
- hardcoded desktop 경로 없이 preflight가 통과한다.
- Liberty/LEF/ORFS/OpenROAD provenance가 기록된다.
- 기존 결과와 도구 버전 차이가 명시된다.

## 7. Phase 1 — 최신 wbq RTL 기능 기준선 재검증

### 목표

물리 실험에 투입할 정확한 RTL revision을 고정한다.

### 작업

1. `normalization_writeback_quad_slice` unit test를 실행한다.
2. PCU→slice→HBM adapter 통합 회귀 4개를 실행한다.
3. LayerNorm/RMSNorm, width 128/2048 결과를 기존 기대값과 비교한다.
4. expected output, ACT/READ/WRITE/PRE count, credit final 0, timing error 0을 확인한다.
5. 관련 Yosys generic structural check를 실행한다.
6. source list와 모든 입력 RTL SHA-256을 manifest로 고정한다.

### 게이트

- unit PASS
- integration 4/4 PASS
- protocol/credit/timing error 없음
- source manifest complete

실패하면 물리실험을 진행하지 않고 기능 원인을 먼저 해결한다.

## 8. Phase 2 — wbq 전용 Sky130HD technology mapping

### 목표

최신 quad-slice RTL만을 입력으로 하는 독립적인 mapped netlist를 생성한다.

### 기준 명령

```bash
MAPPING_VARIANT=wbq \
  bash verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh
```

실행 전 스크립트가 current ORFS/Yosys/Liberty 경로를 사용하며 기존 pre-slice netlist를 덮어쓰지 않는지 확인한다.

### 필수 검사

- top module 일치
- Yosys `check` error 0
- unmapped internal primitive 0
- latch count 확인 및 의도하지 않은 latch 0
- memory lowering/inference 방식 기록
- mapped cell count
- sequential/combinational cell count
- mapped area
- FF/register count
- warning 분류
- source/netlist/config hash 연결

### 게이트

`Yosys check 0`과 `unmapped primitive 0`을 모두 만족하지 않으면 placement로 진행하지 않는다.

## 9. Phase 3 — floorplan, repair, placement, legalization

### 목표

최신 `wbq` mapped netlist를 위한 재사용 가능한 합법 배치 checkpoint를 만든다.

### 작업

1. pre-slice ODB를 재사용하지 않고 새 floorplan을 생성한다.
2. die/core size, utilization, routing layers, pin placement, bank/quad locality를 manifest에 기록한다.
3. fanout/wire/timing repair의 buffer 삽입량과 area 증가를 기록한다.
4. global placement와 detailed placement/legalization을 실행한다.
5. placement violation 0을 확인한다.
6. clock high-fanout 처리 정책을 기록한다. 최종 flow에서 clock을 조용히 skip하지 않는다.
7. legal ODB와 SDC를 저장하고 hash를 기록한다.

### 게이트

- latest wbq netlist hash 사용
- placement/legalization terminal completion
- final legalization violation 0
- ODB/SDC 재개방 가능
- die/core/utilization 및 resource metric 확보

## 10. Phase 4 — wbq global route와 V4 정량 비교

### 목표

quad writeback slice가 기존 V4의 실제 routing congestion을 개선하는지 동일 정의로 검증한다.

### 비교 기준

```text
historical V4 residual congestion = 2,620
historical V4 detailed entries    = 5,998
historical V4 overflow entries    = 2,003
```

### 작업

1. full-net global route를 실행한다.
2. exit code, clean completion marker, route guide, congestion report를 확인한다.
3. residual congestion, overflow, violation entries, maximum overuse, skipped nets, routed nets를 수집한다.
4. layer별, 좌표 tile별, source hierarchy별 hotspot을 분류한다.
5. writeback, replay, reduction, bank interface, adapter buffer, mux select, clock을 분리한다.
6. 동일 collector로 historical V4와 current wbq를 비교한다.
7. peak RSS, wall time, output size를 기록한다.

### 판정

- `PASS_PF4`: overflow 0, severe congestion 없음, 허용되지 않은 skipped net 없음, clean completion
- `IMPROVED_NOT_CLOSED`: 2,620보다 감소했지만 0이 아님
- `NO_IMPROVEMENT`: 동일 정의에서 2,620 이상
- `INVALID_RUN`: OOM, 중단, 불완전 report, 입력 hash 불일치

PF-4가 PASS이면 Phase 6으로 이동한다. 그렇지 않으면 Phase 5를 수행한다.

## 11. Phase 5 — 물리 근거 기반 계층화 반복

### 목표

router 옵션 반복이 아니라 congestion source를 제거하는 RTL/microarchitecture 변경으로 PF-4를 해결한다.

### 우선 구조 방향

1. 16 bank를 4개 quad로 묶는다.
2. quad-local writeback endpoint를 둔다.
3. 필요 시 quad-local replay endpoint를 둔다.
4. 필요 시 quad-local reduction을 추가하고 중앙 구조에는 축약된 결과만 전달한다.
5. wide flat parallel bus를 registered/narrow/serialized/packetized hierarchy로 바꾸는 대안을 비교한다.
6. ready/valid, ordering, tag, backpressure 및 throughput 계약을 유지한다.

### 구조 변경 규율

각 변경 전에 다음을 작성한다.

- congestion evidence
- 변경 가설
- 변경되는 interface와 유지되는 contract
- 예상 wire/fanout 감소
- 예상 latency/throughput/area 비용
- 성공·중단 기준

각 후보는 다음 순서를 통과해야 한다.

```text
unit test
→ integration regression
→ generic synthesis check
→ Sky130 mapping
→ legal placement
→ global route
→ 이전 후보와 A/B 비교
```

### 금지

- 기능 실패를 허용한 채 congestion 숫자만 낮추기
- critical net을 근거 없이 route에서 제외하기
- die를 무제한 확대해 문제를 숨기기
- 서로 다른 RTL/netlist/tool definition의 수치를 직접 비교하기
- router iteration만 반복하고 구조적 원인을 무시하기

각 큰 RTL 구조 변경 후 `05_hierarchical_architecture_report.html`을 갱신하고 커밋·푸시한다.

## 12. Phase 6 — clock distribution과 재사용 가능한 routed checkpoint

### 목표

연구용 GDS에 필요한 명시적 clock 구조와 재시작 가능한 global-route 결과를 확보한다.

### 작업

1. 대규모 `clk_i` fanout 처리 방식을 선택하고 근거를 기록한다.
2. 가능한 경우 CTS를 적용한다. 불가능하면 명시적인 연구용 clock distribution model과 한계를 구현·문서화한다.
3. clock 반영 후 placement legality와 global-route overflow를 다시 확인한다.
4. routed ODB, SDC, route report, congestion report를 저장한다.
5. 모든 입력과 checkpoint의 SHA-256을 revision manifest로 고정한다.

### 게이트

- clock을 암묵적으로 skipped net으로 남기지 않음
- clock 반영 후 legal placement 유지
- PF-4 조건 유지
- routed ODB 재개방 성공

## 13. Phase 7 — 상세 배선과 RTL GDS

### 목표

제조 signoff가 아닌, terminal completion에 도달한 상세 배선 연구 산출물과 구조적으로 유효한 RTL GDS를 만든다.

### 작업

1. detailed route 전 RAM/swap/disk preflight를 수행한다.
2. routed checkpoint에서 detailed route를 실행한다.
3. 진행률, peak memory, wall time, violation count를 기록한다.
4. detailed route terminal completion과 output ODB 존재를 확인한다.
5. 남은 DRC, antenna, timing 및 기타 위반을 정량 기록한다.
6. OpenROAD로 GDS를 stream-out한다.
7. 별도 KLayout 프로세스에서 GDS를 다시 연다.
8. top cell, hierarchy, bbox, cell count, metal/via layer, non-empty geometry를 검사한다.
9. DEF, netlist, ODB, GDS, metrics와 hash manifest를 연결한다.

### 게이트

- detailed-route terminal completion
- output ODB 존재 및 재개방 가능
- GDS stream-out 성공
- KLayout independent readback PASS
- 제조용 signoff가 아니라는 한계 기록

## 14. Phase 8 — TSV·micro-bump·HBM overlay 동결

### 목표

최신 RTL GDS와 병합 가능한 canonical overlay를 만든다.

### 작업

1. 최신 RTL revision으로 floorplan manifest를 갱신한다.
2. TSV와 micro-bump bundle의 connectivity, signal class, pitch, keep-out, provenance를 확인한다.
3. RTL GDS와 overlay의 DBU, 원점, 방향, die bbox를 확인한다.
4. 최소 2개의 물리 anchor로 좌표 변환을 계산하고 오차를 기록한다.
5. layer collision을 검사하고 필요한 remap을 recipe에 명시한다.
6. overlay geometry가 die boundary 안에 있는지 검사한다.
7. illustrative/estimated geometry를 실제 routed geometry와 명확히 분류한다.

### 게이트

- canonical manifest validation PASS
- 두 개 이상 anchor validation PASS
- layer 정책 확정
- overlay GDS/LYP 독립 readback PASS

## 15. Phase 9 — 최종 통합 GDS 병합

### 목표

RTL과 overlay geometry를 모두 포함하는 hash-pinned 단일 연구용 GDS를 생성한다.

### 권장 폴더

```text
output/final_integrated_gds/
├─ inputs/
│  ├─ integrated_rtl_routed.gds
│  ├─ tsv_bump_overlay.gds
│  └─ floorplan_manifest.json
├─ recipe/
│  └─ final_gds_merge_recipe.json
├─ final/
│  ├─ merged_final_physical.gds
│  └─ merged_final_physical.lyp
├─ validation/
│  ├─ merged_final_physical_report.json
│  ├─ hash_manifest.json
│  └─ klayout_fixed_camera.png
└─ reports/
   └─ final_integrated_gds_completion_report.html
```

### 작업

1. 입력 hash가 recipe와 다르면 병합을 거부한다.
2. RTL과 overlay를 명시적 layer mapping으로 병합한다.
3. 병합 후 top/hierarchy/bbox/layer/cell/shape 수를 검사한다.
4. RTL routed geometry와 overlay geometry가 모두 존재하는지 확인한다.
5. anchor 오차와 die boundary 조건을 확인한다.
6. 고정 카메라 KLayout 이미지를 생성한다.

## 16. Phase 10 — 독립 감사와 프로젝트 종료

### 목표

새 프로세스와 깨끗한 출력 경로에서 최종 결과를 검증하고 연구 프로젝트를 종료한다.

### 작업

1. 최종 GDS를 새 KLayout 프로세스에서 다시 연다.
2. top, hierarchy, bbox, layer, cell, RTL/overlay shape를 독립 확인한다.
3. 모든 입력·출력 SHA-256과 tool version을 기록한다.
4. 문서화된 명령으로 clean output regeneration을 수행한다.
5. evidence matrix를 최신 결과로 갱신한다.
6. 각 결과의 evidence class와 claim boundary를 검토한다.
7. known limitations를 숨김없이 기록한다.
8. `09_final_completion_report.html`과 최종 completion manifest를 만든다.

## 17. 최종 완료 정의

다음 조건을 모두 만족해야 목표를 완료로 판정한다.

1. 현재 통합 normalization revision에서 생성되고 독립적으로 다시 열리는 RTL GDS가 있다.
2. detailed-route 완료 ODB, route report, netlist와 RTL GDS가 동일 revision hash로 연결된다.
3. TSV·micro-bump overlay가 canonical manifest와 두 개 이상의 anchor 검사를 통과한다.
4. RTL과 overlay geometry가 모두 존재하는 `merged_final_physical.gds`가 생성된다.
5. 깨끗한 출력 폴더에서 문서화된 명령으로 recipe, GDS, 검증 보고서를 재생성할 수 있다.
6. timing/DRC/antenna 및 illustrative geometry 한계가 evidence matrix와 최종 HTML에서 일치한다.
7. 최종 source, scripts, configs, compact evidence, HTML reports가 커밋되고 `origin/PIM_Simulator`에 푸시되어 있다.
8. 원격 branch SHA가 최종 로컬 HEAD와 일치한다.

완료 시에도 다음 문구를 유지한다.

```text
RESEARCH ARTIFACT — NOT FOR FABRICATION
```

## 18. 장시간 실행 중 의사결정 규칙

- 의미 있는 진행이 가능하면 사용자 응답을 기다리며 작업을 방치하지 않는다.
- 안전한 범위의 read-only 조사, build, test, synthesis, placement, routing, 보고서 생성, checkpoint commit/push는 계속 수행한다.
- 외부 권한, credential, 유료 자원 변경, 데이터 삭제 또는 목표 범위를 바꾸는 결정이 필요하면 중단하고 사용자에게 요청한다.
- 같은 blocker가 반복되면 증거를 모아 원인을 분류하고 다른 실험 축으로 전환한다.
- 시간 자체는 중단 기준이 아니다. 정확성, 재현성, 리소스 안전, 목표 경계가 중단 기준이다.
- 각 단계가 끝날 때 이 문서를 다시 읽고 최종 목표와 비목표에서 벗어나지 않았는지 확인한다.

## 19. 첫 실행 순서

이 문서를 전달받은 작업자는 다음 순서로 즉시 시작한다.

1. 이 문서와 최종 통합 GDS 계획서, `GCP_HANDOFF.md`를 완독한다.
2. Git/서버/도구/디스크/RAM 상태를 기록한다.
3. 현재 서버에서 실행 중인 OpenROAD 프로세스가 있는지 확인하여 중복 실행을 방지한다.
4. ORFS/OpenROAD/Sky130HD 환경을 정확한 provenance로 복원한다.
5. desktop hardcoded path를 portable configuration으로 바꾼다.
6. preflight와 최신 wbq 기능 회귀를 통과시킨다.
7. `MAPPING_VARIANT=wbq` technology mapping을 실행한다.
8. Yosys check 0과 unmapped primitive 0을 확인한다.
9. 새 wbq netlist 전용 floorplan/placement/legal/global-route를 실행한다.
10. 동일 정의로 기존 residual congestion 2,620과 비교한다.
11. PF-4 실패 시 evidence 기반 quad-local reduction/replay/writeback 계층화를 반복한다.
12. PF-4 통과 후 clock, detailed route, RTL GDS, overlay, merge, independent validation으로 진행한다.
13. 각 큰 단계마다 HTML 보고서와 compact evidence를 저장하고 커밋·푸시한다.
