# GR00T workload 감사 및 provisional normalization 아키텍처 DSE

- 작성일: 2026-08-11
- 상태: **PROVISIONAL ONLY**
- 재현 분석기: `tools/analyze_gr00t_workload_architecture.py`
- 기계 산출물: `results/gr00t_workload_architecture/workload_characteristics.csv`, `workload_characteristics.json`, `architecture_dse.csv`, `audit_summary.json`
- requirement 감사 CSV: `results/gr00t_workload_architecture/requirement_to_evidence.csv`

## 1. 결론

현재 자료만으로 GR00T 최종 아키텍처를 확정할 수 없다. 확인된 것은 pinned GR00T N1.7 구조에서 도출한 7개 normalization profile과 333개 호출을 deterministic synthetic FP16 activation으로 simulator에서 측정·재생한 결과다. pretrained BF16 activation, 실제 모델 E2E profiler, 실제 HBM command/address/timestamp trace, 실제 power activity가 없다.

따라서 이 보고서의 후보 수치는 measured/derived/modeled/assumed를 분리한 provisional DSE이며, MobileNet V4를 근거로 사용하지 않는다.

## 2. GR00T 실험 감사

| 항목 | 판정 | 증거 및 해석 |
|---|---|---|
| 모델명 | DERIVED | `experiment/gr00t_placement/README.md`, `assumptions.json`: `nvidia/GR00T-N1.7-3B` |
| checkpoint revision | DERIVED | `2fc962b973bccdd5d8ce4f67cc63b264d6886495` |
| Isaac-GR00T revision | DERIVED | `b9955401d50c92a29258732e3ad6ccd579f1bdc0` |
| 실행 완료 | PASS(제한적) | `gr00t_normalization_reproduction.log`: 2/2 PASS, exit status 0 |
| 실패 실험 | 기록됨 | `gr00t_normalization_failure_glibc.log`: GLIBC_2.43 loader 실패 후 clean WSL rebuild로 재실행 |
| 입력 activation | SYNTHETIC | deterministic sinusoidal FP16; pretrained intermediate activation 아님 |
| 공식 dtype | DERIVED | manifest의 `official_dtype=BF16`; simulator dtype는 FP16 |
| shape/호출 수 | DERIVED | pinned source에서 도출한 manifest 7행, 총 333 invocation |
| cycle | MEASURED + PROJECTED | profile당 simulator 1회 측정 후 invocation 수로 투영; host reduction/RSQRT 제외 |
| trace | MEASURED REPLAY | `gr00t_scheduler_replay_base_trace.csv` 333행; synthetic profile을 고정 arrival schedule로 replay |
| random seed | UNVERIFIED for normalization run | placement assumptions의 seed 1701은 placement model seed이며 normalization simulator seed 증거가 아님 |
| 실제 E2E latency/bandwidth/power | MISSING | 기존 Phase 1/3 문서도 UNVERIFIED 또는 ASSUMED로 명시 |

실행 재현 명령:

```bash
./sim --gtest_filter=Gr00tN17NormalizationFixture.* --gtest_color=no
python tools/analyze_gr00t_workload_architecture.py
```

## 3. 측정·도출 workload 특성

| 특성 | 확인값 | 증거 등급 |
|---|---:|---|
| profile / trace call | 7 / 333 | manifest 및 replay CSV, MEASURED/DERIVED |
| LayerNorm 계열 | 269 calls | DERIVED_FROM_PINNED_OFFICIAL_SOURCE |
| RMSNorm | 64 calls | DERIVED_FROM_PINNED_OFFICIAL_SOURCE |
| shape | `[280,2048]`, `[41,1536]`, `[8960,64]`, `[8960,64]` | DERIVED |
| vector length | 64, 1536, 2048 | DERIVED |
| simulator/official dtype | FP16 / BF16 | DERIVED + SYNTHETIC simulator input |
| projected logical input+output | 232,939,520 B | DERIVED logical payload; physical HBM traffic 아님 |
| reduction statistic scalars | 322,040 | DERIVED: LN 2/row, RMS 1/row |
| measured compute cycles | 2,040,382 projected cycles | MEASURED profile × DERIVED invocation |
| replay service cycles | 3,878,880 | MEASURED replay |
| replay queue cycles | 28,743,920 | MEASURED replay under synthetic arrivals |
| 최대 queue | 801,040 cycles | MEASURED replay; 실제 GR00T queue occupancy 아님 |
| 채널 분포 | 8 channels, 41–42 calls/channel | MEASURED replay schedule; 실제 bank mapping 아님 |
| arithmetic intensity | 산출 불가 | actual transaction bytes/activation trace 부재 |
| real burst/bank distribution | 산출 불가 | raw command/address trace 부재 |

상세 행별 값은 `workload_characteristics.csv/json`에 있다. 특히 `[280,2048]`와 `[8960,64]`는 논리 element 수가 같아도 row 수와 reduction dimension이 다르므로 동일 workload로 취급하지 않는다.

## 4. 후보 DSE

후보의 lane reducer core는 기존 RTL 합성/STA 결과를 사용했다. scalar engine 수, PCU 수, FIFO, context, buffer는 실제 GR00T trace에서 확정할 근거가 없어 명시적 가정이다.

| 후보 | lane / reducer | scalar / PCU | FIFO / context / buffer | FP16 core area | BF16 core area | timing | 판정 |
|---|---|---:|---|---:|---:|---|---|
| 저면적 | 2 / pipelined tree | 1 / 4 | 4 / 4 / 16 KiB | 30,335 um² measured | 25,552 um² measured | 19.61 / 19.97 ns, 100 MHz FAIL | area baseline |
| 균형 | 4 / pipelined tree | 8 / 8 | 8 / 16 / 64 KiB | 57,618 um² measured | 48,305 um² measured | 20.28 / 21.48 ns, 100 MHz FAIL | **provisional working point** |
| 고성능 | 8 / pipelined tree | 16 / 16 | 16 / 16 / 256 KiB | 115,235 modeled extrapolation | 96,610 modeled extrapolation | STA missing | throughput target only |

기존 STA를 단순 역수로 환산한 현재 측정 core의 최대 주파수는 FP16 2/4-lane에서 각각 50.994/49.31 MHz, BF16에서 50.075/46.555 MHz다. 이는 새 pipeline이 timing closure를 달성했다는 뜻이 아니며, 현재 RTL이 100 MHz workload 목표를 만족하지 못한다는 정량적 근거다. 예상 reducer pipeline stage는 각각 1/2/3, II는 기존 pipelined reducer 검증값인 1 cycle이다.

따라서 timing-closure 실험의 안전한 중간 목표는 40MHz(25ns)이며, 100MHz를 유지하려면 최소 한 개 이상의 FP add 내부 arithmetic stage 분할이 필요하다. 40MHz는 기존 2/4-lane critical path보다 느슨한 modeled target일 뿐이며, 새 STA PASS로 간주하지 않는다.

`architecture_dse.csv`의 projected cycles/throughput/utilization/bandwidth는 workload trace와 기존 측정값에 기반한 모델이며, actual end-to-end latency 또는 power 측정값이 아니다. 전 후보의 power/energy는 representative VCD/SAIF가 없어 unavailable이다.

### Provisional 판단

실제 trace가 불완전하므로 최종 PCU/lane/FIFO/context/buffer를 확정하지 않는다. 단, 다음 검증 순서의 provisional working point로 4-lane pipelined tree + 8 scalar engines + 8 PCU를 사용한다.

1. 4-lane은 2-lane보다 row reduction 병렬성이 높고, 8/16-lane의 미측정 area/timing extrapolation을 피한다.
2. 8 scalar engines는 현재 replication 결과가 실제로 합성된 범위 안의 중간점이다.
3. FIFO 8/context 16은 replay의 queue burst를 수용하기 위한 **assumed starting point**이며 trace만으로 확정된 값이 아니다.
4. 100 MHz STA가 실패하므로 이 후보는 timing-closed 최종안이 아니다.

## 5. timing critical path와 개선안

기존 Sky130HD TT, 25 C, 1.8 V, ideal 10 ns clock의 pre-layout STA는 다음과 같다.

- FP16 4-lane: 20.28 ns data arrival, -10.41 ns slack
- BF16 4-lane: 21.48 ns data arrival, -11.61 ns slack

RTL 구조상 critical arithmetic boundary는 `bank_normalization_pipelined_vector_reducer.sv`의 `u_row_sum`/`u_row_sumsq`이다. 각 tree level에는 register가 있으나, `row_sum_q` 또는 `row_sumsq_q`에서 마지막 tree 결과를 더해 `accumulated_sum`/`accumulated_sumsq`를 만드는 FP add가 한 register interval에 남아 있다. STA log의 cell 이름은 합성 후 익명화되어 RTL 인스턴스명까지 직접 보존하지 않지만, 경로는 수십 단계의 exponent compare/align, significand add, normalize/round 및 control mux 조합망으로 구성된다. 따라서 “lane 수를 줄이면 해결된다”는 결론은 성립하지 않는다.

권고하는 timing-closure 변경은 다음 단계다.

- 마지막 tree 출력과 row accumulator를 분리하는 추가 arithmetic pipeline stage;
- accumulator의 sum/sumsq 경로를 동일한 valid/last pipeline으로 정렬;
- `result_valid`, tag, backpressure hold를 추가 stage만큼 지연하되 ready/valid 의미는 유지;
- FP16/BF16 양쪽에 대해 latency는 증가하지만 II=1을 유지하는지 검증;
- 변경 전후 generic cell, mapped area, STA, numerical/reference, reset/backpressure를 다시 실행.

현재 workload 증거가 provisional이고, 100 MHz closure를 입증하는 새 STA 결과가 없으므로 이 보고서에서는 기존 RTL을 임의로 확정 변경하지 않았다. 이는 timing fix 완료가 아니라 **timing closure 미완료** 상태의 정직한 판정이다.

## 6. requirement-to-evidence 감사

### Timing-closure primitive candidate (추가 검증)

`rtl/fp16_add_pipe2.sv`와 `rtl/bf16_add_pipe2.sv`를 추가했다. 두 모듈은 operand compare/align와 add/normalize/round를 두 sequential stage로 나누며 II=1, latency=1 cycle의 primitive 후보이다. 기존 `fp16_add.sv`/`bf16_add.sv`를 대체하거나 full reducer에 아직 연결하지 않았다.

- `fp_bf16_add_pipe2_tb.sv`: 기존 combinational primitive와 1,006개 directed/random vector 비교 PASS
- FP16 pipe2: Yosys `check -assert` PASS, 3,273 generic cells
- BF16 pipe2: Yosys `check -assert` PASS, 2,602 generic cells
- 주의: primitive 단독 합성 결과이며, full reducer timing closure나 Sky130 100MHz PASS를 의미하지 않는다.

Feedback 통합 후보 `rtl/normalization_accumulator_pipe2.sv`도 추가했다. staged adder 결과를 다음 입력의 accumulator state로 반영하기 전까지 `partial_ready`를 막아 II=2를 명시적으로 보장한다. FP16/BF16 accumulator TB에서 결과 보존과 result backpressure를 PASS했으며, Yosys `check -assert`도 양쪽 format에서 PASS했다(합성 top 기준 FP16 6,662 cells, BF16 5,328 cells). 이는 full bank vector reducer가 아니라 timing/feedback 정책을 검증하는 통합 후보다.

| 요구 | 현재 상태 | 근거 |
|---|---|---|
| GR00T 모델/revision/조건 감사 | PARTIAL PASS | README, assumptions, reproduction log; actual full inference absent |
| 실제 trace/shape/call 분석 | PARTIAL PASS | manifest 및 333행 replay; synthetic trace |
| dtype/vector/traffic/queue 추출 | PARTIAL PASS | generated workload CSV/JSON; physical traffic/bandwidth unavailable |
| 1/2/4/8/16 reducer 비교 | PASS foundation / PARTIAL workload DSE | synthesis metrics; 8/16 mapped workload result absent |
| scalar/PCU/FIFO/context/buffer 비교 | MODEL ONLY | candidate CSV; workload 근거 없는 assumptions 명시 |
| latency/throughput/utilization/area/timing | PARTIAL | measured RTL core + modeled system values; power unavailable |
| 100 MHz 원인 분석 | PASS diagnosis | STA logs + reducer RTL structure |
| pipeline 변경 전후 비교 | PARTIAL | FP16/BF16 two-stage primitive 기능·generic synthesis PASS; full reducer integration, before/after mapped STA는 미완료 |
| 기능/수치/reset/backpressure regression | PASS foundation | `27_workload_independent_foundation_completion_audit.md` 및 regression CSV |
| 현재 worktree foundation 재실행 | PASS (component gates) | `foundation_regression_results.csv` 34/34 PASS: 27 test, 6 synthesis, 1 physical gate 기록; Sky130 mapping 4행 PASS. 통합 wrapper는 5분 제한에서 중단됐으나 개별 gate는 재실행 완료 |
| full PIM regression / Yosys structural audit | PASS foundation | 선행 audit 및 logs |
| 현재 full PIM regression 재실행 | PASS | `rtl/run_full_pim_tests.sh`: 9 gates PASS, random stress 40 batches/320 results |
| 현재 normalization structural audit 재실행 | PASS | `run_normalization_structural_audit.sh`: FP16/BF16, lanes 1/2/4/8/16, no latch, `check -assert` |
| workload trace replay | PASS LIMITED | synthetic profile replay CSV; actual GR00T command trace absent |
| 최종 아키텍처 | NOT CLAIMED | data incompleteness 때문에 provisional only |

## 7. 남은 위험과 signoff 미완료

- pretrained BF16 intermediate activation 및 실제 shape variation 미확보
- 실제 GR00T end-to-end normalization latency 비중 미측정
- raw HBM/bank/channel address distribution과 burst/padding 미측정
- synthetic arrival schedule의 queue 결과를 실제 workload로 일반화할 수 없음
- pipeline 추가 후 latency/II/area/timing 및 full regression 필요
- VCD/SAIF 기반 power/energy 없음
- placement/routing/CTS/extracted parasitic, HBM2 PHY, CDC, DFT, thermal/package, silicon signoff 미완료

따라서 본 산출물의 최종 상태는 `PROVISIONAL_ONLY`이며, 실제 GR00T trace와 timing-closed RTL이 확보되기 전에는 최종 후보로 승격하지 않는다.
