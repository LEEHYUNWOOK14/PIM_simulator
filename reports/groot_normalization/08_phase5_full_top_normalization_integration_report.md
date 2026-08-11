# Phase 5 진행 보고서: Full-PIM Top Normalization Integration

- 수행일: 2026-08-11
- production hierarchy: `rtl/full_pim_system_top.sv`
- 판정: **TOP INTEGRATION PASS — normalization sideband 및 broadcast 연결 완료, Bank local-reduce/apply 자동 연결은 미완료**

## 1. 변경 내용

`logic_normalization_reduction_engine`을 `full_pim_system_top`에 실제 인스턴스로 추가했다. standalone 모듈 존재와 production hierarchy 연결을 구분하던 기존 RTL 감사 원칙을 적용했다.

추가된 top-level transaction:

```text
normalization_begin
  mode, row tag, expected bank mask, inv_hidden, epsilon

normalization_partial
  bank ID, row tag, partial SUM, partial SUMSQ

normalization_broadcast
  mode, row tag, mean, inv_std/inv_rms, variance_clamped
```

normalization duplicate/context 오류는 기존 `protocol_error_o`에 포함된다.

## 2. 통합 hierarchy

```text
full_pim_system_top
└─ logic_normalization_reduction_engine
   ├─ FP16 SUM accumulator
   ├─ FP16 SUMSQ accumulator
   └─ logic_normalization_scalar_engine
      ├─ FP16 mean/variance arithmetic
      └─ fp16_rsqrt_lut256
```

Yosys hierarchy log에서 위 인스턴스가 `full_pim_system_top` 아래 보존됨을 확인했다.

## 3. Top-level 기능 검증

기존 `full_pim_system_top_tb`에 4-bank RMSNorm transaction을 추가했다.

입력:

- expected bank mask: `4'b1111`
- 각 bank partial SUM: 0
- 각 bank partial SUMSQ: FP16 1.0
- `inv_hidden`: FP16 0.25
- epsilon: FP16 약 `1e-6`
- row tag: `0x55`

기대 결과:

- mean: FP16 0
- LUT256 inv-RMS: `0x3bfa`
- tag/mode 보존
- clamp 미발생

response를 두 cycle stall한 뒤 payload가 유지되는 것도 확인했다.

전체 결과:

```text
FULL_PIM_SYSTEM_TOP_TB PASS direct[2] logic[1]
LOGIC_DIE_RANDOM_STRESS_TB PASS batches[40] results[320]
```

`rtl/run_full_pim_tests.sh`의 기존 9개 test가 모두 통과했으며 기존 direct TSV, Logic-PCU, reduction/result route도 회귀하지 않았다.

## 4. Parameter 검증

normalization RTL을 source set에 추가한 뒤 최소 파라미터 matrix를 다시 실행했다.

```text
AUDIT_FIX PASS: parameter=1 elaboration matrix has no width mismatch
```

확인 항목:

- CHANNELS=1
- BANKS=1
- PIM_BLOCKS=1
- PCUS=1
- ROWS/COLS=1
- reduction engine BANK_WIDTH 최소 1 bit

## 5. Yosys production hierarchy 검증

축소 parameter의 `full_pim_system_top`을 normalization RTL과 함께 elaboration했다.

```text
CHANNELS=1, BANKS=1, PIM_BLOCKS=1, PCUS=1,
ROWS=2, COLS=2, DATA_WIDTH=16, CRF_DEPTH=2
```

결과:

- hierarchy/check PASS
- normalization reduction/scalar/RSQRT hierarchy 보존
- RTL-level hierarchy cells: 5,094
- process: 47
- Yosys peak memory: 약 3.81 GB
- elapsed CPU user time: 약 75.3 s

log: `results/full_pim_normalization_top_yosys.log`

이 결과는 hierarchy/elaboration 검증이며 generic gate synthesis cell 수 39,064와 직접 비교하면 안 된다.

## 6. 합성 실행 시간 문제

기존 `rtl/run_full_pim_synthesis.sh`는 동일한 전체 source set을 세 번 읽어 bank core, Logic scheduler, full top을 순차 처리한다. normalization LUT와 FP arithmetic 추가 후 120초 wrapper 제한을 넘었다.

- bank core 개별 synthesis: 완료
- Logic scheduler 개별 synthesis: 완료
- full top 단계: wrapper timeout 전 미완료
- 별도 targeted full-top hierarchy run: 81초, PASS

이는 RTL 기능 실패가 아니라 반복 source parsing과 wrapper 시간 제한 문제다. technology/gate synthesis를 완료하려면 실행 단위를 분리하거나 더 긴 worker가 필요하다.

## 7. Source 및 재현 스크립트 갱신

다음 source list에 normalization hierarchy를 추가했다.

- `rtl/run_full_pim_tests.sh`
- `rtl/run_full_pim_synthesis.sh`
- `verification/rtl_audit/run_parameter_min_matrix.sh`

targeted Yosys script:

- `verification/groot_normalization/full_normalization_top.ys`

## 8. 현재 연결의 정확한 의미

완료된 것:

- normalization engine이 production `full_pim_system_top` hierarchy에 존재
- begin/config sideband
- multi-bank partial ingress
- Logic global reduction/finalize/RSQRT
- tagged broadcast output
- protocol error 통합

아직 완료되지 않은 것:

- Bank-PCU가 activation row에서 partial SUM/SUMSQ를 계산하는 명령
- 기존 bank result link에서 paired statistic packet을 자동 생성하는 경로
- broadcast mean/inv를 Bank GRF/SRF에 자동 기록하는 경로
- Bank `NORM_APPLY` opcode 또는 완전한 ADD/MUL apply microprogram
- multi-row queue/FIFO
- BF16

따라서 현재 top integration은 host/test driver가 normalization sideband를 공급하는 구조다. 완전 자율적인 GR00T normalization 실행 경로는 아니다.

## 9. 다음 단계

1. Bank local reduction contract와 paired partial packet 정의
2. 기존 Bank-PCU accumulator 또는 신규 row reducer 연결
3. broadcast scalar를 Bank operand storage에 기록
4. Bank apply sequence 실행 및 완료 barrier
5. 실제 GR00T shape의 multi-row top-level trace
6. scalar engine pipeline/replication
7. technology-mapped synthesis 및 Phase 3 모델 보정

## 10. 판정

Normalization engine이 production RTL top에 실제 연결되고 기존 회귀, parameter=1 elaboration 및 Yosys hierarchy를 통과했다. Top integration 목표는 달성했지만 Bank local-reduce/apply 자동 경로가 남아 Phase 5 전체는 계속 진행 중이다.
