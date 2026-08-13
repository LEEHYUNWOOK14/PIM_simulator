# GR00T Mixed-precision Design-space Exploration

## 결론

선택 후보는 **`C10_FP32_BALANCED_NR2_FUSED`**다.

```text
BF16 activation
→ bank별 4-lane FP32 pairwise tree 및 FP32 row accumulation
→ 16-bank FP32 balanced global tree
→ FP32 mean/variance
→ BF16 LUT256 seed를 FP32로 확장
→ FP32 Newton-Raphson 2회
→ FP32 mean/inv_std broadcast
→ 4-stage FP32 fused affine apply
→ 최종 BF16 RNE 1회
```

전체 6개 captured tensor, 1,909,248 elements에서 6/6 profile이 기존 `max_abs <= 0.025` 기준을 통과했다. overall max abs는 0.015625, bit mismatch는 44개다.

이는 아직 RTL 통과 결과가 아니라 RTL 후보를 고르기 위한 numerical model 결과다.

## 탐색 방법

`tools/explore_groot_mixed_precision.py`가 실제 16-bank × 4-lane mapping 순서를 사용한다.

- BF16 baseline: bank별 lane 순차 BF16 SUM/SUMSQ와 bank 0→15 global BF16 누산
- FP32 local: lane `(0+1) + (2+3)` pairwise tree 후 vector partial을 FP32 row accumulator에 누산
- balanced global: 16→8→4→2→1 FP32 tree
- scalar: `E[x²] - E[x]²`, negative variance zero clamp
- NR: `y = y × (1.5 - 0.5 × x × y²)`
- fused apply: FP32 center/multiply/gamma/beta 후 마지막에만 BF16 RNE

선택 기준은 다음 순서다.

1. 6개 profile 모두 정확도 gate 통과
2. 변경되는 precision block 수 최소화
3. exact FP32 square-root보다 LUT+NR처럼 구현 가능한 scalar cost 우선
4. 동일 정확도/비용이면 global reduction cycle이 짧은 후보 우선

## 후보 결과

| 후보 | 핵심 변경 | profile PASS | max abs | mismatch / 1,909,248 | 결과 |
|---|---|---:|---:|---:|---|
| C0 | 현재 BF16 전체 경로 | 0/6 | 0.1875 | 1,394,056 | FAIL |
| C1 | FP32 reduce/scalar, BF16 LUT/apply | 0/6 | 0.0625 | 987,083 | FAIL |
| C2 | C1 + NR1, BF16 apply | 0/6 | 0.0625 | 824,008 | FAIL |
| C3 | fused FP32 apply만 | 0/6 | 0.1875 | 1,433,610 | FAIL |
| C4 | BF16 reduce + FP32 scalar NR1/fused | 0/6 | 0.1250 | 1,554,636 | FAIL |
| C5 | FP32 reduce + LUT + fused | 0/6 | 0.0625 | 782,319 | FAIL |
| C6 | FP32 reduce + NR1 + fused | 3/6 | 0.0625 | 4,040 | FAIL |
| C7 | FP32 reduce + exact RSQRT + fused | 6/6 | 0.015625 | 30 | PASS |
| C8 | canonical variance + exact RSQRT + fused | 6/6 | 0.015625 | 32 | PASS |
| C9 | FP32 reduce + NR2 + fused, sequential global | 6/6 | 0.015625 | 38 | PASS |
| C10 | FP32 reduce + NR2 + fused, balanced global | 6/6 | 0.015625 | 44 | **PASS/SELECTED** |

## 왜 각 변경이 필요한가

### FP32 reduction

BF16 reduction을 유지한 C4는 scalar/apply를 넓혀도 max abs 0.125로 실패한다. local/global statistic precision 확장은 필수다.

### FP32 fused apply

FP32 reduction/scalar와 NR1을 사용해도 BF16 staged apply를 유지한 C2는 max abs 0.0625로 실패한다. 특히 큰 activation을 가진 `norm_out`에서 중간 BF16 rounding이 기준을 넘긴다.

### NR2

NR1 fused 후보 C6은 mismatch가 4,040개로 크게 줄지만 vlln, VL norm3, norm_out에서 최대 0.03125~0.0625로 실패한다. NR2는 exact FP32 RSQRT 없이 6/6 통과한다.

### Balanced global tree

sequential bank accumulation C9과 balanced tree C10은 모두 max abs 0.015625다. C10은 global combine latency를 16 adds에서 4 tree levels로 줄일 수 있어 선택했다. rounding 순서 변화로 mismatch가 38→44개 증가하지만 gate 여유는 유지된다.

## 선택 RTL contract

| 경계 | format |
|---|---|
| activation/gamma/beta input | BF16, 16-bit |
| lane conversion | exact BF16→FP32 expansion |
| local SUM/SUMSQ | FP32, 32-bit |
| bank partial | FP32 SUM + FP32 SUMSQ, 64-bit payload |
| global SUM/SUMSQ | FP32 balanced tree |
| inv_hidden/epsilon | FP32 |
| mean/variance/RSQRT | FP32 |
| scalar broadcast | FP32 mean + FP32 inv_std |
| affine internal | FP32 per operation |
| final output | BF16 RNE |

## 성능 설계 원칙

- local 4-lane pairwise tree는 stage register를 둔다.
- global 16-bank tree는 네 level을 pipeline한다.
- NR2는 row scalar 연산이므로 shared scalar engine에서 순차 실행해 element datapath 면적 증가를 피한다.
- apply는 center, normalize, gamma, beta를 stage별로 분리하고 II=1을 목표로 한다.
- FP32 accumulator feedback이 주파수 병목이면 multi-accumulator interleave를 별도 후보로 모델링한 후 rounding/정확도를 다시 검증한다.

## 산출물과 재현

```bash
python tools/explore_groot_mixed_precision.py
```

- `reports/groot_normalization/results/mixed_precision_exploration/mixed_precision_profile_accuracy.csv`
- `reports/groot_normalization/results/mixed_precision_exploration/mixed_precision_candidate_summary.csv`
- `reports/groot_normalization/results/mixed_precision_exploration/mixed_precision_exploration.json`

