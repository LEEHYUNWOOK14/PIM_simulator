# Phase 5 진행 보고서: FP16 LUT256 RSQRT RTL Primitive

- 수행일: 2026-08-11
- RTL: `rtl/fp16_rsqrt_lut256.sv`
- LUT: `rtl/fp16_rsqrt_lut256_case.svh`
- Testbench: `verification/groot_normalization/fp16_rsqrt_lut256_tb.sv`
- 판정: **RSQRT PRIMITIVE PASS — exhaustive 기능/handshake/합성 검증 완료, normalization engine 통합은 미완료**

## 1. 구현 내용

Phase 4에서 선택한 FP16 LUT256 후보를 합성 가능한 ready/valid RTL로 구현했다.

주요 구조:

- FP16 sign/exponent/fraction decode
- normal/subnormal 입력 mantissa 정규화
- exponent를 짝수로 조정해 mantissa를 `[1,4)`로 변환
- 256-entry midpoint RSQRT LUT
- exponent scaling을 이용한 최종 FP16 결과 생성
- 1-entry elastic output register
- output stall 중 valid/data 유지

LUT는 Python 생성기가 고정 case table로 만든다. RTL에 `real`, DPI, `$sqrt` 또는 simulation-only 산술을 사용하지 않았다.

## 2. 인터페이스와 성능

| 항목 | 결과 |
|---|---:|
| input format | FP16 scalar |
| output format | FP16 scalar |
| latency | 1 cycle |
| initiation interval | 1 cycle |
| flow control | ready/valid |
| output backpressure | 지원, output hold |

latency/II는 standalone RTL simulation에서 확인한 값이다. Logic-PCU와 reduction/finalize/broadcast가 포함된 전체 normalization latency가 아니다.

## 3. Exhaustive 검증

모든 FP16 bit pattern 65,536개를 Python bit-exact reference와 비교했다.

```text
WROTE lut_entries=256 exhaustive_vectors=65536
FP16_RSQRT_LUT256_TB PASS vectors=65536 cycles=76459 latency=1 II=1
```

검증 범위:

- positive normal
- positive subnormal
- +0/-0
- +Inf/-Inf
- NaN payload
- 모든 negative finite pattern
- 주기적 output backpressure
- stall 중 output valid/data 안정성
- 연속 input throughput

관측 mismatch는 0이다.

## 4. 예외 정책

현재 RTL/reference 정책:

| 입력 | 출력 |
|---|---|
| positive finite | LUT 근사 RSQRT |
| +0 | +Inf (`0x7c00`) |
| +Inf | +0 (`0x0000`) |
| negative finite/-0/-Inf | canonical qNaN (`0x7e00`) |
| NaN | canonical qNaN (`0x7e00`) |

`-0`은 sign 우선 정책으로 qNaN이 된다. IEEE 함수 호환성보다 normalization engine의 invalid-input 검출을 우선한 현재 계약이며, opcode 통합 전에 architectural exception 정책으로 확정해야 한다.

## 5. Yosys 합성

Yosys generic synthesis가 성공했다.

| 항목 | 결과 |
|---|---:|
| wires | 1,021 |
| generic cells | 2,885 |
| AND | 715 |
| MUX | 1,121 |
| OR | 506 |
| enabled DFF | 16 |

합성 log: `results/fp16_rsqrt_lut256_yosys.log`

현재 case-ROM은 generic synthesis에서 큰 mux network로 전개됐다. 이는 합성 가능성은 증명하지만 최적 area 구조라는 의미는 아니다. ASIC memory macro나 optimized ROM mapping을 적용하면 구조가 달라질 수 있다.

generic cell 수를 µm² area 또는 power로 변환하지 않는다. technology mapping/OpenROAD 결과가 나오기 전까지 `area_um2`, `power_mw`는 unknown이다.

## 6. 생성 및 재현 구조

`tools/generate_fp16_rsqrt_rtl_assets.py`가 다음 파일을 결정적으로 생성한다.

- 256-entry FP16 LUT case
- 65,536-entry `{input, expected}` exhaustive vector

재현 명령:

```powershell
wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/groot_normalization/run_fp16_rsqrt_test.sh"
```

합성 명령:

```bash
bash rtl/yosys_local.sh -p \
  'read_verilog -sv -I. rtl/fp16_rsqrt_lut256.sv; \
   hierarchy -check -top fp16_rsqrt_lut256; proc; opt; memory; opt; \
   techmap; opt; stat'
```

## 7. 알려진 한계

- FP16만 구현했다. BF16 RTL은 아직 없다.
- LUT256 RSQRT scalar primitive만 구현했다.
- `REDUCE_SUM`, `REDUCE_SUMSQ`, mean/variance/finalize 및 broadcast와 아직 통합되지 않았다.
- 기존 4-bit opcode에 RSQRT를 할당하지 않았다.
- Logic-PCU scheduler와 연결하지 않았다.
- LUT table은 logic mux로 합성됐으며 ROM macro mapping을 하지 않았다.
- technology-mapped area, timing, power가 없다.
- 실제 GR00T activation 기반 RTL test가 아니다.

## 8. Phase 5 다음 구현 단위

1. normalization scalar engine interface와 row tag/epoch 계약 정의
2. SUM/SUMSQ partial 입력 FIFO와 global accumulation
3. row count/hidden size를 이용한 mean/variance finalize
4. RSQRT primitive 연결
5. mean/inv-std 또는 inv-RMS broadcast result 생성
6. Logic-PCU/top-level 연결과 opcode/command encoding 확정
7. LayerNorm/RMSNorm bit-accurate end-to-end RTL test
8. 전체 회귀 및 technology synthesis

## 9. 현재 판정

RSQRT primitive 자체는 exhaustive 기능, ready/valid stall 및 generic synthesis 기준으로 완료됐다. 그러나 goal의 Phase 5인 “Normalization RTL 구현” 전체는 아직 완료되지 않았으므로 Phase 5는 진행 중으로 유지한다.
