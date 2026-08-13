# STOB_PIM Desktop → GCP Handoff

> 이 문서를 GCP의 새 Codex 채팅에서 목표 문서로 설정한다. 첫 목표는 아래에 적힌 Git 상태를 안전하게 복원하고 검증하는 것이다. 새 RTL 최적화나 P&R 재개는 환경 복원이 끝나고 사용자가 별도로 승인하기 전에는 수행하지 않는다.

## 1. Source State

- 저장소 루트: `C:/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2`
- WSL 경로: `/mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2`
- 브랜치: `PIM_Simulator`
- handoff 전 HEAD: `004b0180c925718547267b2cd21a3bba30473748`
- HEAD 제목/시각: `Checkpoint normalization RTL and research flow`, 2026-08-13 19:51:22 +09:00
- 기록 시각: 2026-08-13T20:38:38+09:00
- 상태: dirty, staged 파일 없음
- tracking branch: `personal/PIM_Simulator`
- tracking 기준: ahead 1, behind 0
- live remote 확인 결과: `personal/PIM_Simulator` = `14dd245dbfc8d53177f73526ade4f0b72d2b7f6b`; 따라서 현재 HEAD commit 1개와 아래 working-tree 변경이 아직 원격에 없다.
- `origin`: `https://github.com/SAITPublic/PIMSimulator.git`
- `personal`: `https://github.com/LEEHYUNWOOK14/PIM_simulator.git`
- 의도한 push 대상: `personal`, branch `PIM_Simulator`
- submodule: 없음 (`.gitmodules` 없음)
- Git LFS: Windows에 3.6.1이 설치돼 있지만 이 저장소에는 `.gitattributes`와 LFS 추적 파일이 없다.
- 전체 working directory: 약 27 GiB
- `.git`: 약 347 MiB; `git count-objects` loose 318.22 MiB + pack 18.75 MiB

Handoff 시작 당시 Windows Git의 정확한 변경 상태는 다음과 같다.

```text
 M rtl/logic_die_normalization_hbm_top.sv
 M verification/groot_normalization/normalization_hbm_boundary_integration_tb.sv
 M verification/groot_normalization/run_normalization_hbm_boundary_test.sh
 M verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh
?? rtl/normalization_writeback_quad_slice.sv
?? verification/groot_normalization/classify_congestion_sources.awk
?? verification/groot_normalization/normalization_hbm_v8_routability_place.tcl
?? verification/groot_normalization/normalization_writeback_quad_slice_tb.sv
?? verification/groot_normalization/run_normalization_hbm_v8_routability_place.sh
?? verification/groot_normalization/run_normalization_writeback_quad_slice_test.sh
```

이 문서 작성 후 `GCP_HANDOFF.md`도 untracked 항목으로 추가된다. Windows Git은 system 설정 `core.autocrlf=true`를 사용한다. 같은 OneDrive working tree를 WSL Git으로 직접 검사하면 줄바꿈 변환 때문에 실제 내용 변경이 아닌 다수 파일이 modified로 보였다. GCP에서는 데스크톱 폴더를 파일 복사하지 말고 승인된 commit을 새로 clone해야 한다.

### 최신 작업본 판정

조사된 데스크톱 범위에서는 이 디렉터리가 최신 활성 STOB_PIM 작업본이다.

- 현재 작업본 HEAD/최근 작업: 2026-08-13, HEAD `004b018...`, 물리 실험 로그 20:28까지 존재
- `STOB_PIM_pure_layornorm`: HEAD `ecacdb9...`, 마지막 commit 2026-08-06
- `STOB_vscode`: HEAD `01c259d...`, 마지막 commit 2026-07-17
- `C:/Users/Admin/AppData/Local/STOB_PIM2`: 독립 Git 저장소가 아님

이 판정은 검색된 로컬/OneDrive 경로에 한정된다. 마운트되지 않은 외장 디스크나 별도 클라우드 복사본의 부재까지 증명하지는 않는다.

## 2. Current Architecture State

현재 normalization 경로는 다음 RTL로 구성된다.

- `logic_die_normalization_pcu_top`: 16-bank normalization PCU 상위 구조
- `normalization_bank_scheduler` 및 mixed-precision datapath: BF16 입력과 FP32 내부 연산을 사용하는 LayerNorm/RMSNorm reduction, scalar, replay/apply, writeback 경로
- `normalization_hbm_boundary_adapter`: PCU의 bank-level traffic을 DRAM command/read/credit 인터페이스에 연결
- `logic_die_normalization_hbm_top`: PCU와 HBM boundary adapter의 통합 top
- 새 uncommitted `normalization_writeback_quad_slice`: 16-bank writeback payload를 4개 quad로 나눈 one-entry elastic register slice. lockstep ready/valid를 유지하며 empty일 때 시작 지연 1 cycle, 동시 dequeue/enqueue 때 최대 1 transaction/cycle을 목표로 한다.

새 slice는 V4 congestion report에서 writeback 경로가 residual overflow의 가장 큰 분류였다는 근거로 추가됐다. 현재 production top과 integration TB에는 연결돼 있지만, 이 새 구조의 Sky130 재매핑·재배치·재배선은 아직 실행하지 않았다.

## 3. Important Source Files

핵심 소스와 재현 자료는 다음과 같다.

- `rtl/`: PCU, normalization arithmetic/datapath, scheduler, HBM adapter, DRAM model
- `rtl/logic_die_normalization_hbm_top.sv`: 현재 통합 top
- `rtl/normalization_writeback_quad_slice.sv`: 최신 uncommitted 구조 변경
- `verification/groot_normalization/`: RTL TB, synthesis, OpenROAD/Yosys, congestion 분석 스크립트
- `flow/designs/sky130hd/normalization_hbm_*`: Sky130 proxy floorplan/SDC/ORFS 설정
- `reports/groot_normalization/physical_feasibility/physical_feasibility_metrics.json`: compact physical evidence와 현재 FAIL verdict
- `reports/groot_normalization/physical_feasibility/01_lightweight_physical_feasibility_report.html`: 사람이 읽는 물리 구현성 보고서
- `groot_actual_workload_validation_goal_prompt.md`: 실제 GR00T normalization workload 검증 목표
- `normalization_completion_tracker_goal_prompt.md`: normalization 진행 추적 목표
- `hardware_cost/`, `experiment/`, `b0_baseline_experiment/`, `b1_logic_die_experiment/`: 하드웨어 비용과 비교 baseline 재현 자료
- `requirements.txt`, `requirements-klayout-3d.txt`, `Sconstruct`, `README.md`, `PIMSimulator_GUIDE.md`: Python/C++ simulator 환경

## 4. Current Verification Status

### 최신 uncommitted writeback slice

- unit backpressure/elastic test: PASS
- PCU→slice→HBM adapter 통합 회귀: 4/4 PASS

```text
LayerNorm width=128, vectors=1:   wall 524, adapter 522 cycles
LayerNorm width=2048, vectors=16: wall 3517, adapter 3515 cycles
RMSNorm   width=128, vectors=1:   wall 512, adapter 510 cycles
RMSNorm   width=2048, vectors=16: wall 3505, adapter 3503 cycles
```

모든 통합 case에서 expected output, ACT/READ/WRITE/PRE count, read credit final=0, timing error=0 조건이 통과했다. 로그는 로컬 ignored 파일로 존재한다.

- `reports/groot_normalization/physical_feasibility/writeback_quad_slice_unit_regression.log` (153 B)
- `reports/groot_normalization/physical_feasibility/writeback_quad_slice_integration_regression.log` (14,536 B)

### 새 slice 이전의 Sky130 proxy evidence

아래 수치는 현재 새 slice를 포함하지 않는 이전 integrated netlist에 대한 것이다.

- adapter standalone mapping: 58,201 cells, 14,639 FF, 0.621866 mm², Yosys check 0
- integrated mapping: 3,322,275 cells, mapped cell area 26.863932 mm², mapped latch 0, unmapped internal primitive 0, Yosys check 0
- V2 floorplan: die 81.5391 mm², project proxy 91.8 mm² 이내
- post-repair area/utilization: 30.430141 mm² / 37.5%
- repair: 78,087 buffers, 10,805 resized cells, library fanout/slew/cap violation 0
- legalization: 3,897 initial violation → 0, max displacement 25.6 µm
- relaxed 1000 ns constraint audit: integrated worst path 26.854 ns, slack +972.576 ns, setup constraint error 0

### Routing verdict

물리 구현 가능성은 아직 증명되지 않았다.

- V4, distributed 565 internal met5 landing pads: remaining congestion 2,620, FAIL
- V4 report source classification: 5,998 entries, 2,003 overflow entries; writeback 2,427 entries/1,181 overflow로 가장 큰 실제 hotspot
- V5, 16 bank soft guides: legal placement에는 성공했지만 remaining congestion 1,182,646, FAIL
- V7, V4와 동일한 배치/핀에서 router iteration 5회: remaining congestion 18,829, FAIL
- V8 routability-driven placement: 구 RTL netlist 기반 탐색이었고 desktop RAM 약 13 GiB를 사용하던 중 migration을 위해 SIGTERM 종료; exit 143, 최종 ODB 없음
- V8 중단 스냅샷: `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v8_interrupted_snapshot.log`

현재 공식 판정은 `FAIL_CURRENT_FLAT_PHYSICAL_ARCHITECTURE_NOT_PROVEN`이다. 공정 signoff PPA/STA, detailed-route closure, DRC/LVS, tapeout readiness를 주장할 수 없다. 새 writeback slice의 기능 회귀만 끝났고 Yosys/Sky130 mapping과 physical gate는 남아 있다.

## 5. Toolchain

Desktop에서 확인한 환경:

| 항목 | 확인값 |
|---|---|
| WSL OS | Ubuntu 26.04 LTS |
| WSL kernel | `6.18.33.2-microsoft-standard-WSL2` |
| GCC/G++ | 15.2.0 |
| Python | 3.14.4 |
| SCons | 4.8.1 |
| CMake | 4.2.3 |
| Ninja | 1.13.2 |
| Icarus Verilog | 12.0 stable |
| Verilator | 5.032 |
| Yosys | `0.68+48`, git `ff5817c34-dirty` |
| OpenROAD executable | `26Q3-1080-gab6fd26351` |
| OpenROAD-flow-scripts | commit `56496f3980fb6e9e58f10c8aea4a98949c0fe5f2` |
| ORFS OpenROAD submodule | `ab6fd26351dc449e69059684dc6aa9ae9046eb36` |
| Windows Git | 2.49.0.windows.1 |
| Git LFS | 3.6.1, tracked files 없음 |

Physical scripts의 desktop hardcoded 경로:

```text
/home/chandler/OpenROAD-flow-scripts
/home/chandler/.local/oss-cad-suite/bin/yosys
/home/chandler/.local/stob-eda/openroad/bin/openroad
/mnt/c/orfs                         # 일부 config.mk 기본값
```

Sky130 proxy는 ORFS의 `flow/platforms/sky130hd`를 사용했다. 대표 liberty는 `sky130_fd_sc_hd__tt_025C_1v80.lib`, SHA-256 `ec0e1067a35c8bf20b11e58d1e8ac53326067e4dac84a125cc1b917a3518d0d9`이다. 별도 PDK release tag는 UNKNOWN이다. ORFS checkout의 OpenROAD submodule에는 local untracked `build-stob/`가 있으므로 commit SHA만 clone해도 desktop custom binary가 자동 복원되지는 않는다.

GCP target은 Ubuntu 24.04 LTS, 16 vCPU, RAM 128 GiB, disk 약 200 GB, VS Code Tunnel `gcp-stob-pim`이다. Desktop과 OS/compiler 버전이 다르므로 결과 비교 시 tool hash와 log를 다시 기록해야 한다.

## 6. Build / Run Commands

저장소 루트에서 실행한다.

### C++ simulator

```bash
sudo apt-get update
sudo apt-get install -y build-essential scons libgtest-dev
scons
```

옵션은 `scons NO_STORAGE=1`, `scons NO_EMUL=1`, `scons NO_LIBRARY=1`이다.

### Python analysis environment

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### 최신 writeback slice 기능 검증

```bash
bash verification/groot_normalization/run_normalization_writeback_quad_slice_test.sh
bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh
```

기대 결과는 unit PASS 1개와 integration PASS 4개다.

### 새 current RTL의 Sky130 mapping — GCP 복원 이후 첫 대용량 단계

```bash
MAPPING_VARIANT=wbq \
  bash verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh
```

이 명령은 아직 current RTL에 대해 실행되지 않았다. 실행 전 script 안의 `/home/chandler/...` 경로가 GCP 설치 경로와 일치하는지 확인해야 한다. `MAPPING_VARIANT=wbq`는 기존 pre-slice netlist를 덮어쓰지 않기 위한 것이다.

이전 V4/V5/V7/V8 P&R 스크립트는 pre-slice ODB를 입력으로 사용한다. 새 mapping 이후 netlist·floorplan·repair·legal placement를 새 variant로 재생성하기 전에는 그대로 재실행하지 않는다.

## 7. External Dependencies

- OpenROAD-flow-scripts commit `56496f3980fb6e9e58f10c8aea4a98949c0fe5f2`
- OpenROAD commit/version `ab6fd26351dc449e69059684dc6aa9ae9046eb36`
- Sky130HD platform/liberty files supplied through ORFS
- Yosys/OSS CAD Suite compatible with the version recorded above
- Icarus Verilog, Verilator, GCC/G++, SCons, CMake, Ninja
- Python packages pinned in `requirements.txt`: gdstk 0.9.61, numpy 2.3.2, scipy 1.16.1, matplotlib 3.10.5, jsonschema 4.25.1
- KLayout embedded Python용 `gds3xtrude==0.0.13`는 별도 설치
- full Isaac GR00T checkout/runtime은 이 repository에 포함되지 않는다. 현재 normalization trace/evidence는 저장소 안의 snapshot을 사용하지만 새 실제 trace를 얻으려면 외부 GR00T 환경을 별도로 복원해야 한다.

## 8. Large Artifacts Not Stored in Git

`.gitignore`는 `.odb`, `.route_guide*`, `.vcd`, local ORFS output, physical feasibility의 raw `.log/.rpt/.v`, `.venv`, cache와 binary를 제외한다. ignored 파일은 8,065개였으며 `.venv` 7,246개, `reports` 420개가 대부분이다. 주요 local directory 크기는 다음과 같다.

- `reports/groot_normalization/physical_feasibility/`: 약 24 GiB
- `b0_baseline_experiment/orfs/`: 약 769 MiB
- `b1_logic_die_experiment/orfs/`: 약 833 MiB
- `.venv/`: 약 283 MiB

50 MB를 초과하는 local 파일은 모두 commit 후보에서 제외한다.

| 크기 | 경로 |
|---:|---|
| 2.77 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v5_relegalize_pass1.odb` |
| 2.77 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v5_bank_regions.odb` |
| 2.77 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v5_bank_gp.odb` |
| 2.77 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v5_bank_legal.odb` |
| 2.77 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v2_repaired_legal.odb` |
| 2.68 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_repaired_legal.odb` |
| 2.56 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v5_tapless_legal.odb` |
| 1.54 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v2.route_guide` |
| 1.51 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top.route_guide.attempt1_met2_met5` |
| 1.19 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v4.route_guide` |
| 0.12 GiB | `output/output.gds` |
| 0.09 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.odb` |
| 0.08 GiB | `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v5_tapcell_rebuild.log` |
| 0.07 GiB | `b0_baseline_experiment/results/power/b0_gate_activity.out` |
| 0.06 GiB | `b0_baseline_experiment/orfs/results/sky130hd/b0_bank_only_baseline/base/6_final.odb` |
| 0.06 GiB | `b0_baseline_experiment/orfs/results/sky130hd/b0_bank_only_baseline/base/6_1_fill.odb` |
| 0.06 GiB | `b0_baseline_experiment/orfs/results/sky130hd/b0_bank_only_baseline/base/5_route.odb` |
| 0.06 GiB | `b0_baseline_experiment/orfs/results/sky130hd/b0_bank_only_baseline/base/5_3_fillcell.odb` |
| 0.06 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/4_1_cts.odb` |
| 0.06 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/4_cts.odb` |
| 0.06 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/3_place.odb` |
| 0.06 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/3_5_place_dp.odb` |
| 0.06 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/3_4_place_resized.odb` |
| 0.06 GiB | `b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/3_3_place_gp.odb` |

이 파일들은 재생성 가능하거나 중간 checkpoint다. GitHub에는 compact JSON/HTML evidence, source script와 hash/명령만 보존한다. desktop local 파일은 이번 단계에서 삭제하지 않는다.

## 9. Known Blockers

1. current writeback-slice RTL의 Sky130 technology mapping이 아직 없다.
2. 따라서 current RTL의 cell area, FF 수, legal placement, global-route congestion, relaxed STA를 아직 판정할 수 없다.
3. 이전 physical verdict는 FAIL이며 route closure를 달성하지 못했다.
4. P&R/Yosys 스크립트에 `/home/chandler`와 `/mnt/c/orfs` hardcoded 경로가 많아 GCP 경로 적응이 필요하다. 이 handoff 단계에서는 수정하지 않았다.
5. Desktop WSL은 Ubuntu 26.04지만 GCP는 Ubuntu 24.04다. compiler/tool binary를 동일하게 재현할 수 있는지는 아직 UNKNOWN이다.
6. exact Sky130 PDK release tag와 OSS CAD Suite package release는 UNKNOWN이다. liberty hash와 ORFS/OpenROAD commit만 확보했다.
7. Windows/WSL line-ending 해석이 다르며 저장소에 `.gitattributes`가 없다. 이번 migration에서는 clean Linux clone으로 회피하고 별도 portability patch 전에는 대량 줄바꿈 변경을 commit하지 않는다.
8. 200 GB GCP disk에는 Git source는 충분하지만 desktop의 24 GiB physical artifacts 전체를 복사할 필요가 없다. 새 run의 intermediate ODB가 각각 약 3 GiB이므로 보존 정책과 free-space 감시가 필요하다.

## 10. GCP First Steps

1. Desktop에서 아래 pre-commit gate를 사용자와 검토하고 승인된 파일만 commit/push한다.
2. GCP에서 `personal/PIM_Simulator`를 clone하고 승인된 최종 SHA로 checkout한다.
3. `git status --short`, `git rev-parse HEAD`, `git remote -v`로 clean source state를 확인한다.
4. Ubuntu 24.04에서 compiler, SCons, Python, Icarus, Verilator를 설치하고 버전을 새 log에 기록한다.
5. ORFS를 commit `56496f3...`로 clone하고 submodule을 초기화한다. OpenROAD `ab6fd263...` 및 Sky130HD liberty hash를 확인한다.
6. `/home/chandler`와 `/mnt/c/orfs` hardcoded 경로를 조사한다. 환경변수화/portability 수정은 별도 승인된 commit으로 수행한다.
7. `requirements.txt`로 새 Linux `.venv`를 만든다. desktop `.venv`는 복사하지 않는다.
8. writeback slice unit test와 4-case HBM integration regression을 먼저 실행해 PASS 기준을 확인한다.
9. `MAPPING_VARIANT=wbq`로 current RTL의 새 Sky130 netlist를 생성하고 Yosys check 0, unmapped primitive 0을 확인한다.
10. 새 netlist 전용 floorplan/repair/legal/global-route flow를 만든 뒤에만 physical feasibility 작업을 재개한다. 이전 ODB 기반 V4~V8을 current result로 재사용하지 않는다.

## 11. File Classification and Pre-Commit Safety Gate

### A. MUST PUSH

- `rtl/logic_die_normalization_hbm_top.sv`
- `rtl/normalization_writeback_quad_slice.sv`
- `verification/groot_normalization/normalization_hbm_boundary_integration_tb.sv`
- `verification/groot_normalization/run_normalization_hbm_boundary_test.sh`
- `verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh`
- `verification/groot_normalization/normalization_writeback_quad_slice_tb.sv`
- `verification/groot_normalization/run_normalization_writeback_quad_slice_test.sh`
- `verification/groot_normalization/classify_congestion_sources.awk`
- `verification/groot_normalization/normalization_hbm_v8_routability_place.tcl`
- `verification/groot_normalization/run_normalization_hbm_v8_routability_place.sh`
- `GCP_HANDOFF.md`

### B. SHOULD PROBABLY PUSH — small evidence logs, ignored이므로 명시적 승인 필요

- `reports/groot_normalization/physical_feasibility/writeback_quad_slice_unit_regression.log` (153 B)
- `reports/groot_normalization/physical_feasibility/writeback_quad_slice_integration_regression.log` (14,536 B)
- `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v8_interrupted_snapshot.log` (3,393 B)

이 세 파일은 generated text artifact이며 binary는 아니다. 현재 `.gitignore`의 `physical_feasibility/*.log` 규칙에 걸리므로 승인 후 포함하려면 `git add -f`가 필요하다.

### C. SHOULD NOT PUSH

- 섹션 8의 모든 50 MB 초과 파일
- 모든 `.odb`, `.route_guide*`, raw physical `.rpt`, large/raw `.log`, generated mapped `.v`, `.vcd`, build output
- `.venv/`, `bin/`, cache, local editor 설정
- `b0_baseline_experiment/orfs/`, `b1_logic_die_experiment/orfs/`
- local ORFS/OpenROAD build tree 및 PDK/tool installation

### D. REQUIRES USER DECISION

- B의 small evidence log 3개를 force-add할지 여부. 기본 권고는 exact handoff evidence를 위해 포함하는 것이다.

### Commit proposal

- exact source/document 후보: A의 11개 파일
- optional generated-text 후보: B의 3개 파일
- 50 MB 초과 commit 후보: 없음
- potentially sensitive file: 파일명 및 일반적인 private-key/token/password pattern 검사에서 발견 없음
- generated binary proposed: 없음
- generated text proposed: B의 log 3개만 해당
- 제안 commit message: `Checkpoint writeback quad slice and GCP handoff`
- target branch: `PIM_Simulator`
- target remote: `personal`

**STOP GATE:** 사용자 승인 전에는 stage, commit, push하지 않는다. 승인 시 B의 log 포함 여부도 함께 확정한다.
