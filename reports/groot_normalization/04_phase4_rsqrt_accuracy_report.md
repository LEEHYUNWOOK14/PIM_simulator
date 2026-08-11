# Phase 4 보고서: RSQRT 후보 수치 정확도

- 수행일: 2026-08-11
- 평가 도구: `tools/evaluate_rsqrt_candidates.py`
- 결과: `results/rsqrt_scalar_accuracy.csv`, `results/rsqrt_normalization_accuracy.csv`
- 판정: **NUMERICAL PASS — LUT-only 및 wide-internal NR 후보 통과, RTL latency/area는 미측정**

## 1. 평가 범위

256-entry mantissa LUT를 seed로 사용하는 다음 후보를 비교했다.

1. `LUT256`
2. `LUT256_NR1_NARROW`
3. `LUT256_NR2_NARROW`
4. `LUT256_NR1_WIDE`
5. `LUT256_NR2_WIDE`

`NARROW`는 Newton–Raphson의 곱셈과 뺄셈마다 출력 dtype(FP16/BF16)으로 반올림한다. `WIDE`는 LUT 입출력은 대상 dtype이지만 NR 내부 계산을 FP32 상당으로 유지한 뒤 최종 결과를 반올림한다.

LUT는 입력을 mantissa와 짝수 exponent로 정규화하고 `[1,4)` mantissa 구간을 256개 bin으로 나눈 뒤 bin midpoint의 `1/sqrt(m)` 값을 사용한다.

## 2. 사전 판정 기준

scalar RSQRT maximum relative error:

- LUT-only: 1% 이하
- FP16 NR: 0.2% 이하
- BF16 NR: 1% 이하
- 평가 중 nonfinite 결과: 0개

normalization output:

- FP32 canonical 결과 대비 maximum absolute error 0.025 이하
- nonfinite 결과 0개

첫 실행 결과를 본 뒤 허용치를 넓히지 않았다.

## 3. Scalar 결과

20,007개 positive 입력을 각 dtype/candidate에서 평가했다.

- LayerNorm/RMSNorm epsilon `1e-5`, `1e-6`
- FP16 최대값과 작은 양수
- `2^-19`에서 `2^15` 범위 log-uniform random 20,000개

| Dtype | Candidate | Max relative error | Mean relative error | Nonfinite | 판정 |
|---|---|---:|---:|---:|---|
| FP16 | LUT256 | 0.2998% | 0.0825% | 0 | PASS |
| FP16 | NR1 narrow | 0.1115%* | 0.0261%* | 1,848 | **FAIL** |
| FP16 | NR2 narrow | 0.1023%* | 0.0234%* | 1,850 | **FAIL** |
| FP16 | NR1 wide | 0.0488% | 0.0176% | 0 | PASS |
| FP16 | NR2 wide | 0.0488% | 0.0176% | 0 | PASS |
| BF16 | LUT256 | 0.4467% | 0.1621% | 0 | PASS |
| BF16 | NR1 narrow | 0.6264% | 0.1809% | 0 | PASS |
| BF16 | NR2 narrow | 0.5541% | 0.1708% | 0 | PASS |
| BF16 | NR1 wide | 0.3914% | 0.1390% | 0 | PASS |
| BF16 | NR2 wide | 0.3868% | 0.1390% | 0 | PASS |

`*` FP16 narrow의 error 통계는 finite 결과에 대해서만 계산됐다. nonfinite가 발생했으므로 전체 후보는 실패다.

## 4. FP16 narrow NR 실패 원인

작은 RSQRT 입력에서는 seed `y`가 크다. NR 식의 `y²`를 FP16으로 즉시 반올림하면 FP16 maximum을 넘어 `Inf`가 될 수 있다.

```text
y_next = y × (1.5 - 0.5 × x × y²)
```

수학적으로 `x × y² ≈ 1`이어도 연산 순서상 `y²`가 먼저 overflow한다. 이 때문에 epsilon 근처 입력에서 `Inf/NaN`이 발생했다. 정규화 평가에서도 all-zero, constant, small-variance 및 epsilon-near case가 실패했다.

이는 NR 반복 횟수를 늘려 해결되지 않으며 내부 dynamic range 또는 연산 순서를 바꿔야 한다.

## 5. Normalization end-to-end 결과

다음 9개 case를 FP16/BF16에서 평가했다.

- LayerNorm: all-zero, constant, mixed random, small variance, large offset/small variance
- RMSNorm: all-zero, constant, mixed random, epsilon-near
- hidden size: 64, 1536, 2048

총 90개 dtype/candidate/case 행 중 78개가 통과했다.

| Candidate group | 통과 |
|---|---:|
| FP16 LUT256 | 9/9 |
| FP16 NR1/NR2 narrow | 각각 3/9 |
| FP16 NR1 wide | 9/9 |
| FP16 NR2 wide | 9/9 |
| BF16 모든 후보 | 각각 9/9 |

관측 maximum normalization output absolute error:

- FP16 LUT256: 0.002075
- FP16 wide NR: 0.000275 이하
- BF16 후보: 0.005778 이하

모두 사전 허용치 0.025보다 작다. 단, narrow FP16 후보는 nonfinite 때문에 실패다.

## 6. Corner-case 정책

현재 평가 모델의 scalar 정책:

| 입력 | 출력 |
|---|---|
| positive finite | 근사 RSQRT |
| +0 | +Inf |
| +Inf | +0 |
| negative | NaN |
| NaN | NaN |

실제 normalization 경로에서는 epsilon을 더하므로 정상 입력의 RSQRT argument는 양수여야 한다. RTL에서는 위 정책을 그대로 지원할지, error flag/saturation을 사용할지 명령 계약으로 확정해야 한다.

## 7. 후보 선택

### 1차 RTL 후보: LUT256

선택 이유:

- FP16/BF16 scalar 기준 통과
- 모든 normalization case 통과
- NR multiplier/add pipeline이 필요 없어 가장 단순
- FP16 narrow NR의 중간 overflow가 없음
- ROM payload는 dtype당 대략 256 × 16 bit = 4 Kibit 수준

### 정확도 확장 후보: LUT256 + NR1 wide

- FP16/BF16 정확도가 LUT-only보다 개선됨
- FP32 상당 내부 datapath 때문에 area/power/latency 증가 예상
- NR2는 NR1 대비 관측 개선이 거의 없어 우선순위가 낮음

따라서 Phase 5에서는 LUT256을 합성 가능한 baseline으로 구현하고, wide NR1은 optional 비교 대상으로 남긴다. narrow FP16 NR1/NR2는 현재 연산 순서로 구현하지 않는다.

## 8. 중요한 한계

- 실제 GR00T pretrained activation이 아니다.
- gamma/beta/weight를 포함한 affine output 전체를 평가하지 않았다. RSQRT로 인한 normalized value 오차를 평가했다.
- SUM/SUMSQ reduction rounding error는 분리돼 있으며 본 결과에 포함되지 않았다.
- LUT의 RTL ROM inference와 exponent/exception logic은 아직 구현/합성하지 않았다.
- latency, II, area 및 power는 아직 측정하지 않았다.
- Python FP32 wide NR은 특정 RTL pipeline의 bit-accurate 모델이 아니다.

## 9. 재현 명령

```powershell
python .\tools\evaluate_rsqrt_candidates.py --self-test
python .\tools\evaluate_rsqrt_candidates.py
```

## 10. 다음 단계

1. 합성 가능한 FP16 LUT256 RSQRT RTL과 bit-accurate testbench를 구현한다.
2. latency/II를 측정해 Phase 3 parameter를 보정한다.
3. normalization scalar engine의 finalize 및 broadcast 계약을 정의한다.
4. BF16 datapath 지원 범위와 conversion 비용을 별도 결정한다.
5. reduction rounding까지 포함한 LayerNorm/RMSNorm RTL-equivalent reference를 만든다.
