# BF16 Actual-trace Accuracy Resolution

## 결론

BF16 actual-trace 정확도 게이트 실패를 C11 mixed-precision normalization datapath로 해결했다. 외부 activation, gamma, beta 및 output 형식은 BF16 16-bit를 유지한다. 내부 통계 누산, scalar 계산 및 affine apply만 FP32로 확장하고 마지막 출력에서 BF16 RNE를 한 번 수행한다.

새 canonical 명령은 다음과 같다.

```bash
bash verification/groot_normalization/run_groot_actual_trace_bf16_test.sh
```

이 명령은 C11 RTL로 6개 captured tensor 전체를 재생하고, PyTorch BF16 output에 대한 `max_abs <= 0.025`, nonfinite 0 기준을 자동 판정한다. 분석기가 FAIL이면 명령도 nonzero로 종료한다.

## 원인

기존 all-BF16 hierarchical datapath는 local/global SUM·SUMSQ 누산, scalar 계산 및 affine apply의 각 단계에서 BF16 반올림을 반복했다. stage 분석에서 RTL은 software BF16 emulation과 bit-exact했으므로 mapping이나 testbench 문제가 아니었다.

기존 결과는 6개 profile 중 1개만 기준을 통과했으며 최대 절대오차는 profile에 따라 0.03125~0.0625였다. 특히 reduction/scalar 오차와 staged BF16 apply rounding이 지배적이었다.

## 적용 구조

선택된 C11 경로:

```text
BF16 input
→ FP32 4-lane local SUM/SUMSQ
→ FP32 16-bank balanced global tree
→ FP32 variance + LUT seed + Newton-Raphson 2회
→ FP32 fused affine pipeline
→ BF16 RNE output 1회
```

임계값을 완화하거나 golden output을 변경하지 않았다.

## 새 RTL 실행 결과

실행일: 2026-08-11 KST

| profile | elements | RTL vs C11 model mismatch | PyTorch BF16 bit mismatch | 결과 |
|---|---:|---:|---:|---|
| action_vlln | 573,440 | 0 | 5 | PASS |
| action_vl_self_attention_norm1 | 573,440 | 0 | 7 | PASS |
| action_vl_self_attention_norm3 | 573,440 | 0 | 17 | PASS |
| action_dit_adaln_norm1 | 62,976 | 0 | 4 | PASS |
| action_dit_norm3 | 62,976 | 0 | 0 | PASS |
| action_dit_norm_out | 62,976 | 0 | 4 | PASS |

종합 결과:

- profile: 6/6 PASS
- samples: 1,909,248
- RTL vs C11 model mismatch: 0
- PyTorch BF16 bit mismatch: 37
- overall max abs: 0.015625
- threshold: 0.025
- nonfinite: 0

## 회귀 정책 변경

- `run_groot_actual_trace_bf16_test.sh`를 C11 기반 BF16 external-I/O accuracy gate로 변경했다.
- `analyze_groot_mixed_precision_rtl.py --variant C11`이 C11 결과를 직접 판정하고 FAIL 시 nonzero를 반환한다.
- foundation regression에서는 canonical C11 actual-trace를 실행한다.
- C10과 C11 helper full-tensor 스크립트의 중복 자동 실행은 제외했다. C10 component protocol/stress 테스트는 계속 유지한다.
- legacy all-BF16 결과와 RTL은 기준선·원인 분석 증거로 보존하며 production accuracy PASS로 표시하지 않는다.

## 한계

C11은 정확도 문제를 해결하지만 기존 보고된 Sky130 pre-layout timing에서 최종 목표 주파수에 미달한다. 따라서 이번 결과는 arithmetic accuracy 해결이며 최종 PPA 또는 HBM manufacturing sign-off가 아니다.

## 최종 전체 회귀

정확도 수정 후 전체 회귀 게이트를 새로 실행했다.

```text
rtl_to_3d_unit: PASS
hardware_cost_unit: PASS
normalization_foundation_tests: PASS
rtl_audit_regression: PASS
FULL_REGRESSION_GATE PASS
```

실행 결과:

- `reports/reproducibility/regression_gate_20260811T145903Z.json`
- `reports/reproducibility/regression_gate_20260811T145903Z.csv`
- `reports/reproducibility/reproducibility_manifest_20260812T0018KST.json`

전체 게이트 소요 시간은 약 1,111.5초였으며, canonical C11 BF16 actual-trace와 `LANES=4` multirow 전체 trace를 포함한다.
