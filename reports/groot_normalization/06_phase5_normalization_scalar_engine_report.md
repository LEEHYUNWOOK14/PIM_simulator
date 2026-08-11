# Phase 5 진행 보고서: Logic-die Normalization Scalar Engine

- 수행일: 2026-08-11
- RTL: `rtl/logic_normalization_scalar_engine.sv`
- Testbench: `verification/groot_normalization/logic_normalization_scalar_engine_tb.sv`
- 판정: **SCALAR ENGINE PASS — LayerNorm/RMSNorm finalize+RSQRT 완료, partial FIFO/top 통합은 미완료**

## 1. 구현 목적

global SUM/SUMSQ가 준비된 뒤 Logic die에서 수행해야 하는 scalar 경로를 구현했다.

### LayerNorm

```text
mean        = FP16(sum × inv_hidden)
mean_square = FP16(sumsq × inv_hidden)
variance    = FP16(mean_square - FP16(mean × mean))
argument    = FP16(max(variance, 0) + epsilon)
inv_std     = LUT256_RSQRT(argument)
```

### RMSNorm

```text
mean_square = FP16(sumsq × inv_hidden)
argument    = FP16(mean_square + epsilon)
inv_rms     = LUT256_RSQRT(argument)
mean        = 0
```

`hidden_size` divider를 추가하는 대신 host/command context가 FP16 `inv_hidden`을 전달하도록 했다. 지원할 hidden size마다 reciprocal을 미리 계산할 수 있어 범용 divider보다 구조가 단순하다.

## 2. 인터페이스

입력:

- LayerNorm/RMSNorm mode
- row tag
- global SUM
- global SUMSQ
- `1/hidden_size`
- epsilon

출력:

- 동일 mode/tag
- mean
- inv-std 또는 inv-RMS
- negative variance clamp 여부

입출력은 ready/valid이며 response stall 동안 mode/tag/mean/inv/clamp가 유지된다.

## 3. Pipeline과 성능

상태 순서:

```text
IDLE → VARIANCE → EPSILON → RSQRT_SEND → RSQRT_WAIT
```

- request acceptance부터 response 생성까지 nominal 5 cycles
- 현재 engine은 transaction 하나만 in-flight로 유지
- back-to-back transaction 처리율은 약 5 cycles/row
- 내부 RSQRT primitive 자체는 latency 1, II 1

따라서 현재 scalar engine의 병목은 RSQRT가 아니라 직렬 FSM이다. 향후 row throughput이 중요한 `[8960,64]` profile에서는 mean/variance/RSQRT를 pipeline으로 분리해야 한다.

## 4. Bit-exact 검증

2,048개 deterministic vector를 생성해 RTL과 단계별 FP16 reference를 비교했다.

포함 범위:

- LayerNorm/RMSNorm 교대
- hidden size 64/256/1536/2048
- epsilon `1e-5`/`1e-6`
- mean 양수/음수/0
- variance 0 및 작은 값부터 큰 값
- FP16 단계별 반올림
- negative variance clamp
- tag/mode 보존
- output backpressure
- stall 중 payload 안정성

결과:

```text
LOGIC_NORMALIZATION_SCALAR_ENGINE_TB PASS vectors=2048 cycles=10242
```

- mismatch: 0
- clamp 경로 vector: 37
- 평균 처리 간격: 약 5 cycle/vector

## 5. Negative variance clamp

SUM/SUMSQ 방식은 FP16 반올림 때문에 이론상 음수가 아니어야 하는
`mean_square - mean²`가 작은 음수가 될 수 있다. RSQRT에 음수를 전달하지 않도록 다음 정책을 구현했다.

```text
if LayerNorm and variance < 0:
    variance = +0
    variance_clamped = 1
```

clamp 여부를 출력해 정확도 분석과 디버깅에서 숨기지 않는다. 장기적으로 Welford 또는 더 넓은 accumulator와 비교해야 한다.

## 6. Yosys generic synthesis

전체 scalar engine hierarchy의 generic synthesis가 성공했다.

| 항목 | 결과 |
|---|---:|
| wires | 8,059 |
| generic cells | 29,372 |
| AND | 7,801 |
| MUX | 11,402 |
| OR | 4,522 |
| enabled/regular DFF | 168 |

세부 hierarchy에는 FP16 add/mul, LUT RSQRT와 control register가 포함된다. 합성 log는 `results/logic_normalization_scalar_engine_yosys.log`에 저장했다.

29,372 generic cells는 technology-mapped area가 아니다. 특히 LUT case와 FP16 arithmetic이 generic mux/gate로 확장되므로 µm²/power 주장에 사용할 수 없다.

## 7. 기존 RTL 회귀

새 engine은 아직 production top에 연결되지 않았지만 이름 충돌이나 기존 소스 영향 여부를 확인하기 위해 `rtl/run_full_pim_tests.sh`를 다시 실행했다.

결과:

- 기존 Full-PIM self-checking test 9개 PASS
- 16-PCU 동시 처리 PASS
- random stall 40 batches/320 results PASS
- full top direct/logic/reduction route PASS

## 8. 자산 재현

`tools/generate_normalization_scalar_vectors.py`가 2,048개 128-bit vector를 생성한다.

재현 명령:

```powershell
wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/groot_normalization/run_normalization_scalar_test.sh"
```

## 9. 현재 구조적 한계

- 입력 SUM/SUMSQ는 이미 global reduction이 끝난 FP16 scalar라고 가정한다.
- Bank별 partial-result FIFO와 accumulator는 아직 연결되지 않았다.
- 기존 cross-channel vector reduction이 SUM/SUMSQ 두 stream을 row별로 공급하도록 확장되지 않았다.
- 한 transaction만 in-flight여서 II가 5 cycle 수준이다.
- BF16을 지원하지 않는다.
- `inv_hidden` 및 epsilon command/config register가 top에 없다.
- mean/inv 결과를 Bank-PCU로 broadcast하는 네트워크가 없다.
- `NORM_APPLY` Bank opcode가 없다.
- 실제 GR00T activation 및 end-to-end RTL test가 없다.
- technology-mapped timing/area/power가 없다.

## 10. 다음 구현 단위

1. row tag를 보존하는 SUM/SUMSQ partial pair FIFO
2. expected bank mask 기반 global accumulator
3. scalar engine request 생성
4. mean/inv result broadcast interface
5. `full_pim_system_top`과 Logic-die hierarchy 연결
6. Bank-PCU `NORM_APPLY` 또는 기존 ADD/MUL sequence 연결
7. LayerNorm/RMSNorm multi-row end-to-end test
8. pipeline/replication을 이용한 scalar engine II 개선

## 11. 현재 판정

global statistic 이후의 finalize+RSQRT 기능은 standalone RTL 기준 완료됐다. 하지만 Bank partial 입력부터 Bank apply까지 전체 normalization transaction은 아직 닫히지 않았으므로 Phase 5는 계속 진행 중이다.
