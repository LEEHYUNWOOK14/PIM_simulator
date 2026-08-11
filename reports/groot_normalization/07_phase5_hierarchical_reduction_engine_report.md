# Phase 5 진행 보고서: Hierarchical Normalization Reduction Engine

- 수행일: 2026-08-11
- RTL: `rtl/logic_normalization_reduction_engine.sv`
- Testbench: `verification/groot_normalization/logic_normalization_reduction_engine_tb.sv`
- 판정: **STANDALONE HIERARCHICAL PATH PASS — multi-bank reduction부터 RSQRT까지 완료, production top 연결은 미완료**

## 1. 구현 범위

Bank-PCU에서 계산됐다고 가정한 `(partial SUM, partial SUMSQ)` 쌍을 Logic die에서 수집해 다음 경로를 수행한다.

```text
begin(row tag, expected bank mask, mode, inv_hidden, epsilon)
→ bank별 partial SUM/SUMSQ 수신
→ tag/bank-mask 검증
→ FP16 global SUM/SUMSQ accumulation
→ LayerNorm/RMSNorm scalar finalize
→ LUT256 RSQRT
→ tagged mean/inv-std 또는 inv-RMS response
```

앞서 구현한 `logic_normalization_scalar_engine`과 `fp16_rsqrt_lut256`을 hierarchy 내부에서 재사용한다.

## 2. Transaction 계약

### Begin

- normalization mode: LayerNorm/RMSNorm
- row tag
- expected bank mask
- FP16 `inv_hidden`
- FP16 epsilon

### Partial input

- bank ID
- row tag
- partial SUM
- partial SUMSQ
- ready/valid

### Response

- mode/tag
- mean
- inv-std 또는 inv-RMS
- variance clamp flag
- ready/valid

한 context만 활성화된다. 모든 expected bank가 한 번씩 도착하면 global sum을 scalar engine으로 전달한다.

## 3. 오류 검출

다음 입력을 수락하지 않고 error pulse를 발생시킨다.

- 이미 수신한 bank의 중복 partial: `duplicate_error_o`
- 활성 tag와 다른 partial: `context_error_o`
- expected mask에 없는 bank
- active context가 없을 때 들어온 partial
- expected mask가 0인 begin

중복이나 잘못된 context는 accumulator 값을 변경하지 않는다.

## 4. 기능 검증

512개 transaction과 총 8,192개 bank slot을 생성했다.

검증 범위:

- active bank: 2/4/8/16
- LayerNorm/RMSNorm 교대
- hidden size: 64/256/1536/2048
- FP16 partial SUM/SUMSQ
- sequential FP16 global accumulation
- mean/variance/epsilon/RSQRT
- mode/tag 보존
- response backpressure
- duplicate bank 오류
- wrong-tag context 오류

결과:

```text
LOGIC_NORMALIZATION_REDUCTION_ENGINE_TB PASS transactions=512 duplicate_checks=2
```

표시 이름 `duplicate_checks`에는 duplicate 1개와 context 1개, 총 error-path 검사 2개가 포함된다. 기능 mismatch는 0이다.

## 5. Yosys generic synthesis

전체 hierarchy generic synthesis 결과:

| 항목 | 결과 |
|---|---:|
| wires | 11,312 |
| generic cells | 39,064 |
| AND | 10,491 |
| MUX | 14,451 |
| OR | 6,316 |
| enabled/regular DFF | 286 |

합성 log: `results/logic_normalization_reduction_engine_yosys.log`

포함 hierarchy:

- 두 FP16 global accumulator adder
- normalization scalar engine
- FP16 mean/variance arithmetic
- LUT256 RSQRT
- transaction/context registers

generic cell 수는 합성 가능성 및 상대 복잡도 증거다. technology-mapped area/power로 해석하지 않는다.

## 6. 현재 처리 특성

- bank partial은 cycle당 최대 한 쌍 수신
- bank 수가 B이면 최소 B cycle의 partial collection 필요
- global accumulation은 도착 순서대로 FP16 add
- scalar finalize는 nominal 5 cycle
- 한 row context만 in-flight
- response가 stall되면 다음 begin을 차단

현재 per-row 최소 latency는 대략 `active_banks + 5 cycles`이며 handshake 경계에 따른 control cycle이 추가된다. `[8960,64]`의 높은 row 수에는 다중 context 또는 engine 복제가 필요하다.

## 7. 수치 의미와 한계

SUM/SUMSQ accumulation을 FP16으로 수행하므로 다음 위험이 있다.

- hidden size가 클 때 sum/sumsq overflow
- 큰 offset과 작은 variance에서 cancellation
- partial 도착 순서에 따른 rounding 차이
- negative variance clamp 증가

현재 테스트는 RTL과 같은 순서의 FP16 reference에 대한 bit-exact 검증이다. FP32 PyTorch 정확도를 보장하는 시험은 아니다. 실제 GR00T에서는 FP32 accumulator 또는 wider fixed-point, Welford와 비교해야 한다.

## 8. 재현 자산

- generator: `tools/generate_normalization_reduction_vectors.py`
- metadata: `verification/groot_normalization/normalization_reduction_meta.hex`
- partial data: `verification/groot_normalization/normalization_reduction_partials.hex`

재현 명령:

```powershell
wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/groot_normalization/run_normalization_reduction_test.sh"
```

## 9. Production top과의 차이

현재 `full_pim_system_top`은 channel/PCU vector result를 기존 `cross_channel_reduction_network`로 보낸다. 신규 normalization engine이 요구하는 다음 신호는 아직 production top에 없다.

- SUM과 SUMSQ의 paired partial stream
- row tag와 normalization mode
- expected bank mask
- inv-hidden과 epsilon config
- mean/inv scalar Bank broadcast

따라서 standalone engine PASS를 전체 GR00T normalization RTL 통합 완료로 주장하면 안 된다.

## 10. 다음 구현 단위

1. existing command encoding에서 normalization begin/config 전달 방법 확정
2. Bank local reduction이 SUM/SUMSQ pair를 생성하도록 연결
3. Logic-die top에 normalization reduction engine 인스턴스 추가
4. normalization response를 Bank destination router/broadcast로 연결
5. Bank-PCU element-wise apply sequence와 row tag 동기화
6. multi-row end-to-end top-level test
7. accumulator precision 비교 후 FP16 유지 여부 결정
8. technology mapping 및 timing/area 측정

## 11. 현재 판정

Bank partial statistic에서 Logic RSQRT response까지의 standalone hierarchical datapath는 검증됐다. 실제 Bank subsystem 및 production top과의 연결과 apply 경로가 남아 있으므로 Phase 5는 계속 진행 중이다.
