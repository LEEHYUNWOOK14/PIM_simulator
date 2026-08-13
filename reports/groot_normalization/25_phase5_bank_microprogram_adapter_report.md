# Phase 5 — Bank-PCU 정규화 microprogram adapter

## 목적과 구현

Logic PCU에서 반환된 `mode/tag/mean/inv_std`를 기존 `bank_pim_core`가 직접 소비할 수 있는 SRF write와 affine 명령열로 변환했다.

- RTL: `rtl/bank_normalization_microprogram_adapter.sv`
- RMSNorm SRF: lane 0에 `inv_rms`
- LayerNorm SRF: lane 0에 `-mean`, lane 1에 `inv_std`
- FP16 precision과 row tag 기반 context key를 명령과 함께 유지한다.
- SRF write 및 command ready/valid backpressure를 모두 지원한다.

명령열:

| Mode | Commands | Operation |
|---|---:|---|
| RMSNorm | 2 | `x*inv_rms`, `normalized*gamma` |
| LayerNorm | 4 | `x-mean`, `centered*inv_std`, `normalized*gamma`, `scaled+beta` |

## 실제 Bank-PCU 기능 검증

adapter 출력을 실제 `bank_pim_core`의 SRF/command 입력에 연결했다. 16-lane activation, GRF_B의 gamma/beta, 실제 vector ALU 결과를 검사했다.

```text
BANK_NORMALIZATION_MICROPROGRAM_ADAPTER_TB PASS transactions=2 commands=6 lanes=16
```

- RMSNorm: `x=2`, `inv=0.5`, `gamma=2` → 최종 `2.0`
- LayerNorm: `x=2`, `mean=1`, `inv=1`, `gamma=2`, `beta=0.5` → 최종 `2.5`
- 두 transaction의 최종 `M_OUT`, tag/context key, 명령 개수와 command error를 확인했다.

## generic synthesis

| Metric | Value |
|---|---:|
| Generic cells | 171 |
| Wires | 89 |
| Wire bits | 521 |
| Port bits | 386 |
| Yosys strict check | PASS |

이는 adapter만의 generic synthesis이며 `bank_pim_core`, GRF, activation/gamma/beta 저장 공간은 포함하지 않는다.

## 판정과 제한

- **RTL_MEASURED:** scalar 응답을 실제 Bank-PCU SRF write와 RMSNorm/LayerNorm affine microprogram으로 변환해 올바른 최종 vector 결과를 낸다.
- 현재 activation operand는 `EVEN_BANK`로 고정돼 있다. 실제 replay scheduler가 even/odd operand와 vector 주소를 제공해야 한다.
- gamma/beta는 사전에 GRF_B index 0/1에 로드되어 있다고 가정한다.
- `transaction_done`은 마지막 명령이 수락된 시점이다. 최종 result 수집 완료와 동일한 신호는 아니므로 상위 controller가 result handshake를 별도로 추적해야 한다.

## 다음 작업

bank별 adapter 배열을 `hierarchical_normalization_scalar_return_top`에 연결해 각 bank의 scalar backpressure가 해당 adapter의 유휴 상태를 반영하도록 만들고, 이후 Bank-PCU array까지 포함한 raw-to-affine 축소 E2E 테스트를 구성한다.
