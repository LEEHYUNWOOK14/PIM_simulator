# C10 Full-tensor RTL Accuracy Report

## 결론

C10 mixed-precision RTL은 captured GR00T action-head의 6개 대표 tensor, 총 1,909,248 elements에서 numerical model과 bit-exact하게 일치했다. PyTorch BF16 출력 대비 기존 정확도 기준 `max_abs <= 0.025`는 6/6 profile이 통과했다.

| 지표 | 결과 |
|---|---:|
| profile gate | 6/6 PASS |
| RTL vs C10 model mismatch | 0 / 1,909,248 |
| RTL vs PyTorch bit mismatch | 44 / 1,909,248 |
| overall max abs | 0.015625 |
| primitive FP32 vectors | 20,225 bit-exact PASS |
| protocol test | reset 및 3-cycle backpressure PASS |
| stress test | 9 rows / 576 elements bit-exact PASS |

## Profile별 결과

| profile | PyTorch bit mismatch | max abs |
|---|---:|---:|
| action_vlln | 5 | 0.00390625 |
| action_vl_self_attention_norm1 | 8 | 0.0078125 |
| action_vl_self_attention_norm3 | 21 | 0.015625 |
| action_dit_adaln_norm1 | 6 | 0.0078125 |
| action_dit_norm3 | 0 | 0 |
| action_dit_norm_out | 4 | 0.000122 |

## 정확도를 만든 최소 조건

- BF16 input/gamma/beta를 FP32로 exact expansion한다.
- local SUM/SUMSQ와 global tree를 FP32로 유지한다.
- variance와 rsqrt scalar를 FP32로 수행한다.
- BF16 LUT seed 뒤 Newton-Raphson을 2회 수행한다.
- affine 중간값을 FP32로 유지하고 최종 출력에서만 BF16 RNE를 수행한다.

NR1 후보는 3/6 profile만 통과했고, BF16 reduction 또는 staged BF16 apply 후보는 모두 실패했다. 따라서 이 정밀도 확장은 선택 사항이 아니라 현재 정확도 gate에 필요한 최소 구조다.

## 한계

C10은 정확하지만 Sky130 mapping에서 reducer 61.22ns, global 62.67ns, scalar 78.34ns, apply 61.06ns의 임계경로를 보였다. 정확도 기준선으로는 확정할 수 있지만 처리량용 최종 구조로 사용할 수 없다.

## 재현

```bash
bash verification/groot_normalization/run_fp32_mixed_precision_primitives_test.sh
bash verification/groot_normalization/run_mixed_precision_protocol_test.sh
bash verification/groot_normalization/run_mixed_precision_stress_test.sh
bash verification/groot_normalization/run_groot_mixed_precision_trace_test.sh
```

