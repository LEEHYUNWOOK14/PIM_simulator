# Phase 5 진행 보고서: Bank Local Reduction 및 Normalization Apply

- 수행일: 2026-08-11
- RTL: `bank_normalization_local_reducer.sv`, `bank_normalization_apply.sv`
- 판정: **BANK PRIMITIVES PASS — local SUM/SUMSQ 및 LN/RMS apply 검증 완료, production top 자동 연결은 미완료**

## 1. 구현 결과

### Bank local reducer

FP16 activation stream 한 row fragment를 받아 다음 partial statistics를 생성한다.

```text
partial_sum   = sequential_FP16_sum(x)
partial_sumsq = sequential_FP16_sum(FP16(x × x))
```

입력 계약:

- row tag
- fragment element count
- FP16 element stream
- ready/valid

출력 계약:

- 동일 row tag
- partial SUM
- partial SUMSQ
- ready/valid

element count가 0이거나 active row가 없을 때 element가 들어오면 protocol error를 발생시킨다.

### Bank normalization apply

Logic die broadcast scalar를 config로 받고 element-wise normalization을 수행한다.

LayerNorm:

```text
y = FP16(FP16(FP16(x - mean) × inv_std) × gamma) + beta
```

RMSNorm:

```text
y = FP16(FP16(x × inv_rms) × gamma)
```

config와 element의 row tag가 다르거나 config 없이 element가 들어오면 context error를 발생시킨다. `element_last`가 수락되면 해당 config context를 닫는다.

## 2. 기능 검증

deterministic generator가 128개 row와 fixed storage 2,048개 element slot을 생성했다. 실제 유효 element는 1,088개다.

검증 범위:

- LayerNorm/RMSNorm 교대
- row 길이 1~16
- 양수/음수/0 activation
- gamma 0.5~1.5
- beta -0.5~0.5
- mean 및 inverse scale 변화
- FP16 단계별 rounding
- reducer output stall
- apply output handshake
- row tag와 last 보존
- inactive reducer protocol error
- missing/wrong apply context error

결과:

```text
BANK_NORMALIZATION_ENGINES_TB PASS rows=128 logical_elements=1088
```

기능 mismatch는 0이다.

## 3. 처리 특성

### Local reducer

- input II: 1 element/cycle
- 하나의 row context만 in-flight
- fragment 길이 N이면 최소 N input cycles
- 마지막 element와 함께 partial 결과 생성
- output stall 중 다음 row begin 차단

### Apply engine

- config context 하나
- input II: 1 element/cycle
- combinational FP16 ADD/MUL chain 뒤 1-entry output register
- output stall 중 result hold
- `last` 수락 후 다음 config 필요

apply engine의 combinational chain은 기능적으로 II 1이지만 timing closure에서 긴 critical path가 될 가능성이 높다. technology timing 결과 전에는 1 GHz 등의 주파수를 주장하지 않는다.

## 4. Yosys generic synthesis

| Engine | wires | generic cells | AND | MUX | OR | DFF |
|---|---:|---:|---:|---:|---:|---:|
| local reducer | 4,519 | 15,307 | 4,187 | 5,450 | 2,533 | 115 |
| normalization apply | 5,740 | 20,777 | 5,627 | 7,827 | 3,245 | 85 |

합성 log:

- `results/bank_normalization_local_reducer_yosys.log`
- `results/bank_normalization_apply_yosys.log`

이는 generic cell 결과이며 µm²/power가 아니다.

## 5. 구조 선택에 주는 의미

Bank apply engine 하나의 generic cell 수가 Logic-die RSQRT primitive 2,885보다 훨씬 크다. 이를 모든 bank/PIM block에 그대로 복제하면 면적 증가가 RSQRT보다 더 클 수 있다.

따라서 최종 RTL에서는 다음 선택을 비교해야 한다.

1. bank마다 dedicated reducer/apply engine
2. channel 내 여러 bank가 reducer/apply pipeline 공유
3. 기존 Bank-PCU ADD/MUL datapath를 microprogram으로 재사용
4. Logic-only에서 tensor를 Logic die로 이동

현재 결과만 보면 전용 Bank apply engine 대량 복제보다 기존 Bank-PCU datapath 재사용이 면적 측면에서 유력하다. 하지만 cycle과 traffic 비교가 추가로 필요하다.

## 6. 수치 한계

- partial accumulation이 FP16이라 overflow/cancellation 위험이 있다.
- test는 RTL-equivalent FP16 reference에 대한 bit-exact 비교다.
- PyTorch FP32/BF16 E2E 정확도는 아직 아니다.
- row 길이 16까지만 RTL test에 사용했다.
- GR00T hidden 64~2048 전체 row는 bank별 fragment로 나뉜다는 전제다.
- gamma/beta/activation storage와 DRAM burst access는 모델링하지 않았다.

## 7. 재현 자산

- generator: `tools/generate_bank_normalization_vectors.py`
- metadata: `verification/groot_normalization/bank_normalization_meta.hex`
- elements: `verification/groot_normalization/bank_normalization_elements.hex`
- test: `verification/groot_normalization/bank_normalization_engines_tb.sv`

```powershell
wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/groot_normalization/run_bank_normalization_test.sh"
```

## 8. 다음 단계

1. local reducer output을 Full-PIM normalization partial ingress에 내부 연결
2. Logic broadcast를 Bank apply config에 연결
3. activation/gamma/beta stream을 top-level test에서 공급
4. Bank fragment → Logic reduction → Bank apply E2E transaction 검증
5. dedicated engine과 기존 Bank-PCU microprogram의 합성/cycle 비교
6. multi-bank/multi-row scheduling 및 backpressure

## 9. 판정

Bank local reduction과 element-wise normalization apply primitive는 standalone RTL 기준 완료됐다. production hierarchy 자동 연결과 실제 Bank memory datapath는 남아 있으므로 Phase 5는 계속 진행 중이다.
