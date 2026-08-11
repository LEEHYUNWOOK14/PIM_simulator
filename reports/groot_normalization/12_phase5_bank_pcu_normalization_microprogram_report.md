# Phase 5 Bank-PCU normalization 마이크로프로그램 검증

## 결론

기존 `bank_pim_core`의 FP16 ADD/MUL, GRF, SRF 기능만으로 affine RMSNorm과 affine LayerNorm의 elementwise apply를 수행할 수 있다. 따라서 normalization apply를 위해 bank마다 별도 산술 데이터패스를 추가할 필요는 없다.

## 검증 범위

`bank_pim_normalization_microprogram_tb.sv`에서 256-bit, 16-lane FP16 Bank-PCU를 직접 구동했다.

- 입력 lane 패턴: 2.0, 3.0, 4.0, 1.0 반복
- RMSNorm scalar: `inv_rms=0.5`, `gamma=2.0`
- LayerNorm scalar: `mean=1.0`, `inv_std=0.5`, `gamma=2.0`, `beta=0.5`
- 모든 lane을 bit-exact FP16 결과와 비교
- destination, register index, context key, illegal-command 신호 확인

## 실행 결과

```text
BANK_PIM_NORMALIZATION_MICROPROGRAM_TB PASS commands=6 cycles=20 lanes=16
```

| 연산 | scalar 설정 | 산술 명령 | 명령 시퀀스 |
|---|---:|---:|---|
| affine RMSNorm apply | SRF 1회 + gamma GRF 1회 | 2 | normalize MUL; gamma MUL |
| affine LayerNorm apply | SRF 1회 + gamma/beta GRF | 4 | center ADD; normalize MUL; gamma MUL; beta ADD |

LayerNorm의 감산은 별도 SUB opcode 없이 SRF에 `-mean`을 저장하고 ADD로 수행한다. `-mean`과 `inv_std`는 하나의 256-bit SRF write에 함께 넣을 수 있다. gamma와 beta는 vector parameter이므로 GRF에 적재한다.

## 의미

- Bank-PCU의 기존 vector ALU를 재사용하므로 apply 연산의 incremental arithmetic datapath area는 0이다.
- 필요한 추가 기능은 Logic-PCU 결과를 SRF로 전달하는 broadcast/configuration 경로와 명령 스케줄링이다.
- TB의 20사이클은 reset 이후 두 affine normalization 예제를 연속 수행한 testbench 관측치다. GRoot 전체 latency를 의미하지 않는다.
- 실제 parameter cache 재사용률과 GRF 적재 비용은 GRoot graph/profile을 기준으로 Phase 1/6에서 분리 계측해야 한다.

## 재현

```bash
bash verification/groot_normalization/run_bank_pim_normalization_microprogram_test.sh
```

관련 파일:

- `verification/groot_normalization/bank_pim_normalization_microprogram_tb.sv`
- `verification/groot_normalization/run_bank_pim_normalization_microprogram_test.sh`
- `rtl/bank_pim_core.sv`
- `rtl/pim_command_decoder.sv`
