# Phase 0 보고서: GR00T Normalization 기준선 고정

- 수행일: 2026-08-11
- 작업 목표: `groot_normalization_rsqrt_goal_prompt.md`
- RTL 저장소 commit: `eb4fb6fa3b8221294e0029891feb2cf3d29de042`
- GR00T simulator 저장소 commit: `ecacdb9c1d3ae1f838dbfd2f7e80fbb73c4b217d`
- 판정: **PHASE 0 PASS — Phase 1 workload manifest 작성 가능**

## 1. 기준선 결론

현재 `STOB_PIM2`는 Bank-PCU, Logic-PCU, cross-channel FP16 reduction 및 Bank/host result routing을 `full_pim_system_top`에 연결한다. 기존 초기 감사 문서의 “reduction/result router 미연결” 판정은 수정 전 상태이며, 현재 RTL과 `07_aud_009_014_repair_progress.md`가 더 최신 증거다.

그러나 현재 RTL은 GR00T LayerNorm/RMSNorm 엔진이 아니다. RTL opcode는 ADD/MUL/MAC/MAD/MOV/FILL/NOP/JUMP/EXIT만 제공하며 `REDUCE_SUM`, `REDUCE_SUMSQ`, `DIV`, `SQRT`, `RSQRT`, `NORM_APPLY`는 없다. 현재 reduction network는 여러 channel에서 들어온 FP16 vector를 lane별로 더하는 기능이며, normalization hidden dimension 전체의 row reduction과 mean/variance/RSQRT를 수행하지 않는다.

C++ simulator에는 `BatchNormPIMKernel`과 host `sqrt()` 경로가 있지만 이는 RTL 지원 증거가 아니다. 기존 GR00T 테스트의 대상도 BatchNorm이 아니라 LayerNorm/RMSNorm이다.

## 2. 현재 지원 범위

| 기능 | C++ PIMSimulator | 현재 RTL | GR00T 기존 테스트에서의 처리 |
|---|---|---|---|
| FP16 ADD/MUL | 지원 | 지원 | Bank-PIM |
| MAC/MAD | simulator/RTL 경로 존재 | 지원 | 사용하지 않음 |
| BatchNorm kernel | `BatchNormPIMKernel` 존재 | 전용 opcode/engine 없음 | 사용하지 않음 |
| LayerNorm/RMSNorm element-wise | ADD/MUL 조합 | primitive만 존재 | Bank-PIM |
| hidden-dimension reduction | host 계산 | 전용 normalization row reduction 없음 | host, cycle 제외 |
| cross-channel vector reduction | 별도 simulator 계약 | `cross_channel_reduction_network` 연결 | 기존 GR00T 테스트에서 미사용 |
| mean/variance/division | host 계산 | 없음 | host, cycle 제외 |
| RSQRT | host `1/sqrt()` | 없음 | host, cycle 제외 |
| scalar broadcast | operand row로 재배치 | normalization 전용 broadcast 없음 | 비용 미분리 |
| BF16 | 기존 경로 미지원 | 현재 FP16 datapath 중심 | 미검증 |

## 3. 기존 GR00T 결과의 비용 경계

2026-08-11에 `Gr00tN17NormalizationFixture.*`를 다시 실행하여 2/2 PASS를 확인했다.

| 연산 | 실제 실행한 고유 profile | 모델 호출 수 | projected Bank-PIM cycle | FP32 최대 절대오차 |
|---|---:|---:|---:|---:|
| LayerNorm | 5 | 269 | 1,417,342 | 0.001415 |
| RMSNorm | 2 | 64 | 623,040 | 0.001361 |
| 합계 | 7 | 333 | 2,040,382 | 0.001415 |

포함된 비용:

- LayerNorm의 Bank-PIM ADD/MUL element-wise passes
- RMSNorm의 Bank-PIM MUL element-wise passes
- simulator가 해당 primitive 실행에 부과하는 cycle

포함되지 않은 비용:

- hidden dimension reduction
- mean/variance 또는 mean-square 계산
- division과 epsilon 처리
- host RSQRT
- host/GPU 왕복과 kernel launch
- queue 및 synchronization
- partial statistic 이동
- scalar broadcast와 mode switching의 독립 비용
- Logic-PCU 실행 비용

따라서 `2,040,382 cycles`는 normalization end-to-end cycle이 아니라 **Bank-PIM element-wise 부분의 projected cycle**이다.

## 4. 재검증 결과

| 검증 | 결과 | 범위 |
|---|---|---|
| `rtl/run_full_pim_tests.sh` | PASS | 9개 self-checking RTL test: ALU, DRAM, Bank subsystem, Logic-PCU, reduction, routing, 16-PCU, full top, random stall |
| `run_parameter_min_matrix.sh` | PASS | CHANNELS/BANKS/PIM_BLOCKS/PCUS/ROWS/COLS=1 계열 elaboration |
| `run_aud_001_008_regression.sh` | PASS | FP16 MUL 4,217 vectors mismatch 0 및 AUD-002~008 회귀 |
| `Gr00tN17NormalizationFixture.*` | PASS 2/2 | 7개 고유 GR00T profile, synthetic FP16, host reduction/RSQRT |
| RTL synthesis | 이번 Phase에서 재실행하지 않음 | 기존 Yosys/OpenROAD 증거 사용; normalization RTL 변경 전이므로 비용 대비 생략 |

사용 도구:

- Icarus Verilog 12.0 stable
- g++ 15.2.0
- Python 3.14.4
- WSL Linux 실행 환경

## 5. 재현성 수정

`verification/rtl_audit/run_aud_001_008_regression.sh`가 FP16 벡터 생성기의 include 경로를 `${HOME}/projects/STOB_PIM2/lib`로 고정하고 있었다. 이를 `${repo_root}/lib`로 바꿔 현재 저장소 위치와 무관하게 실행되도록 수정했고 전체 감사 회귀 PASS로 검증했다.

이 변경은 RTL 기능이나 결과값을 바꾸지 않고 테스트 실행 경로만 수정한다.

## 6. 물리 구현 기준선과 주장 한계

기존 최신 감사 결과에 따르면 축소 구성 `full_pim_system_top`의 Yosys/OpenROAD/GDS integration은 완료됐다. 그러나 다음 한계가 유지된다.

- physical instance는 1 channel, 1 bank, 1 Bank-PCU, 1 Logic-PCU 축소 구성이다.
- detailed-routing violation 274,099건이 남아 있다.
- antenna violation은 602 nets / 743 pins이다.
- 10 ns timing constraint를 만족하지 않는다.
- 따라서 integration artifact이지 DRC-clean/signoff/tape-out 결과가 아니다.

Normalization/RSQRT RTL을 추가하면 area/timing/power를 다시 측정해야 하며 기존 GDS 수치를 새 엔진의 PPA로 재사용하면 안 된다.

## 7. Worktree 보존

두 저장소 모두 작업 시작 시 clean 상태가 아니었다.

- `STOB_PIM2`: 다수의 기존 수정 및 미추적 RTL/보고서/physical-flow artifact 존재
- `STOB_PIM_pure_layornorm`: `src/tests/Gr00tNormalizationTestCases.cpp`에 기존 사용자 수정 존재

기존 변경을 되돌리거나 덮어쓰지 않았다. 본 Phase에서 새로 만든 것은 이 보고서와 goal prompt이며, 수정한 기존 파일은 감사 회귀 스크립트의 저장소 상대 include 경로 한 줄뿐이다.

## 8. Phase 1 입력과 남은 미검증 항목

Phase 1은 다음 네 대표 shape를 workload manifest의 최소 집합으로 사용한다.

- LayerNorm `[280, 2048]`
- LayerNorm `[41, 1536]`
- RMSNorm `[280, 2048]`
- RMSNorm `[8960, 64]`

다음은 아직 미검증이다.

- 실제 GR00T pretrained intermediate activation
- GR00T BF16에서의 수치 및 traffic
- 동적 VL sequence length 분포
- gated Cosmos vision config의 실제 hidden width
- ViT 내부 LayerNorm 호출의 전체 cycle
- normalization의 실제 GR00T end-to-end latency 비중
- 실제 GPU baseline latency/energy

이 항목들은 추정값을 실측처럼 사용하지 않고 Phase 1 manifest에서 `MEASURED`, `DERIVED`, `ASSUMED`, `UNVERIFIED`로 분류한다.

## 9. 재현 명령

```powershell
wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash rtl/run_full_pim_tests.sh"

wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/rtl_audit/run_parameter_min_matrix.sh"

wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/rtl_audit/run_aud_001_008_regression.sh"

wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM_pure_layornorm' && ./sim --gtest_filter='Gr00tN17NormalizationFixture.*' --gtest_color=no"
```

## 10. Phase 0 완료 판정

지원 범위, hierarchy, 기존 GR00T 결과의 비용 경계, 테스트 재현성과 물리 주장 한계를 현재 코드와 실행 결과로 고정했다. Phase 1 workload manifest 작성에 필요한 기준선이 확보됐으므로 Phase 0을 완료한다.
