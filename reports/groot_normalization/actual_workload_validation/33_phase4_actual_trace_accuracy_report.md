# Phase 4 — GR00T BF16 Trace 대비 RTL 정확도 보고서

## 결론

현재 BF16 full-path RTL은 캡처한 6개 pretrained action-head 대표 row를 모두 정상 종료했지만, 사전에 유지한 `max_abs <= 0.025` 기준은 **1/6 profile만 통과**했다. 따라서 Phase 4 정확도 gate의 결론은 **FAIL**이다. 기준을 결과에 맞춰 완화하지 않았다.

이 결과는 full GR00T inference activation이 아니다. 입력의 증거 등급은 Phase 2와 동일한 `PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`이다. 즉 공개된 N1.7 pretrained action-head weight를 실제 실행해 얻은 내부 BF16 activation이지만, backbone 입력은 고정 seed synthetic boundary tensor이다.

## 재현 조건

- 모델: `nvidia/GR00T-N1.7-3B`
- checkpoint revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- source commit: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`
- trace device/dtype: NVIDIA GeForce RTX 4060, BF16
- RTL: 16-bank `hierarchical_normalization_datapath`, BF16 local SUM/SUMSQ, BF16 global reduction, LUT256 BF16 RSQRT, BF16 affine apply
- 비교 row: profile마다 첫 번째 hidden row 1개, 총 10,240 elements
- 허용 기준: 기존 프로젝트 기준 `max_abs <= 0.025`, nonfinite 0

재현 명령:

```bash
bash verification/groot_normalization/run_groot_actual_trace_bf16_test.sh
python3 tools/analyze_groot_rtl_accuracy_stages.py
bash verification/groot_normalization/run_normalization_special_values_test.sh
bash verification/groot_normalization/run_normalization_scalar_test.sh
```

## PyTorch BF16 대비 결과

| profile | hidden | max abs | mean abs | RMSE | exact mismatch | 결과 |
|---|---:|---:|---:|---:|---:|---|
| action_vlln | 2048 | 0.031250 | 0.001925 | 0.003733 | 983 | FAIL |
| action_vl_self_attention_norm1 | 2048 | 0.046875 | 0.007105 | 0.009518 | 1,986 | FAIL |
| action_vl_self_attention_norm3 | 2048 | 0.031250 | 0.002813 | 0.004901 | 1,228 | FAIL |
| action_dit_adaln_norm1 | 1536 | 0.007812 | 0.000633 | 0.001720 | 470 | PASS |
| action_dit_norm3 | 1536 | 0.031250 | 0.004453 | 0.006392 | 1,340 | FAIL |
| action_dit_norm_out | 1536 | 0.062500 | 0.001920 | 0.006777 | 1,289 | FAIL |

모든 profile에서 NaN/Inf 출력은 0이었다. near-zero 부호 교차 때문에 ULP 최대값은 절대오차보다 과장되므로 gate에는 사전 정의된 max absolute error를 사용했다.

## 단계별 원인 분리

`tools/analyze_groot_rtl_accuracy_stages.py`는 다음을 software에서 그대로 재현한다.

1. 실제 testbench와 같은 `(vector address, bank, lane)` 순서의 bank별 BF16 누산
2. bank 0→15 BF16 global SUM/SUMSQ 누산
3. BF16 mean/variance와 LUT256 RSQRT
4. `center → inv_std multiply → gamma multiply → beta add`의 매 단계 BF16 rounding

검증 결과:

- 6/6 RTL mean bit pattern 일치
- 6/6 RTL inv_std bit pattern 일치
- 총 10,240/10,240 RTL output bit pattern 일치

따라서 변환, 주소 mapping, testbench 수집 오류는 관측되지 않았다. 오차는 설계된 BF16 단계 연산에서 발생한다.

| profile | canonical inv_std | RTL inv_std | inv abs error | canonical scalar + RTL apply max abs | 실제 RTL max abs |
|---|---:|---:|---:|---:|---:|
| action_vlln | 0.985821 | 0.984375 | 0.001446 | 0.031250 | 0.031250 |
| VL norm1 | 0.967414 | 0.957031 | 0.009148 | 0.015625 | 0.046875 |
| VL norm3 | 0.954121 | 0.957031 | 0.002910 | 0.015625 | 0.031250 |
| AdaLN inner LN | 0.999365 | 1.000000 | 0.000635 | 0.007812 | 0.007812 |
| DiT norm3 | 0.986885 | 0.992188 | 0.005303 | 0.015625 | 0.031250 |
| norm_out | 0.035149 | 0.035400 | 0.000252 | 0.062500 | 0.062500 |

해석:

- VL norm1, VL norm3, DiT norm3는 BF16 SUM/SUMSQ 및 scalar 경로가 max error를 0.015625에서 0.03125~0.046875로 증가시킨다.
- vlln과 AdaLN은 scalar를 canonical 값으로 교체해도 최대오차가 줄지 않아 BF16 affine 단계 rounding의 영향이 크다.
- norm_out은 큰 activation/affine 값 때문에 max error는 apply rounding이 지배한다. 다만 canonical scalar를 사용하면 mean abs가 0.001920에서 0.000310으로 감소하므로 scalar 오차도 전체 분포에는 영향을 준다.
- 현재 LUT는 Newton refinement가 없는 LUT256이고 누산도 각 add마다 BF16으로 round한다. PyTorch LayerNorm의 내부 reduction 정책과 같지 않다.

## Corner-case 정책 및 회귀

- `normalization_special_values_tb`: FP16/BF16 각각 7 cases PASS. zero, infinity, NaN 등 RTL의 명시적 special-value 전달 정책을 검증한다.
- `logic_normalization_scalar_engine_tb`: FP16/BF16 각각 2,048 vectors PASS. 이는 RTL과 그 RTL-equivalent golden의 일치성 검사이며 PyTorch 정확도 통과를 의미하지 않는다.
- 음수 variance는 zero로 clamp하고, zero RSQRT 입력은 +Inf, 음수 입력은 canonical NaN, +Inf 입력은 zero로 처리한다.

## Gate와 다음 조치

Phase 5 구조 비교는 목표 문서에 따라 계속 수행하되 모든 성능 결과에 **정확도 FAIL**을 함께 표시한다. Production replay/write-back 구현의 필수 조건인 정확도 gate는 현재 만족하지 않는다.

정확도 개선 후보는 결과 임계값 변경이 아니라 다음 설계 변경이다.

1. bank/local 및 global accumulation을 FP32 또는 확장 고정소수점으로 수행
2. `E[x²]-E[x]²` 대신 Welford/pairwise variance 검토
3. LUT256 뒤 Newton-Raphson 1회 또는 FP32 scalar 경로 사용
4. affine multiply-add의 내부 정밀도 확장 후 최종 BF16 단일 rounding

## 산출물

- `reports/groot_normalization/results/actual_groot/rtl_accuracy_results/accuracy_summary.csv`
- `reports/groot_normalization/results/actual_groot/rtl_accuracy_results/accuracy_summary.json`
- `reports/groot_normalization/results/actual_groot/rtl_accuracy_results/stage_accuracy_summary.csv`
- `reports/groot_normalization/results/actual_groot/rtl_accuracy_results/stage_accuracy_summary.json`
- `reports/groot_normalization/results/actual_groot/rtl_accuracy_results/rtl_runs.log`
- `tools/prepare_groot_rtl_accuracy_vectors.py`
- `tools/analyze_groot_rtl_accuracy.py`
- `tools/analyze_groot_rtl_accuracy_stages.py`
- `verification/groot_normalization/groot_actual_trace_bf16_tb.sv`
- `verification/groot_normalization/run_groot_actual_trace_bf16_test.sh`
