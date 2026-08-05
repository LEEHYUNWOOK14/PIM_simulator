# 77차: Bank-local aggregation FP16 누산 정확도

## 1. 목적

기존 0/1 입력은 FP16 rounding 문제를 드러내지 않는다. 부호와 소수값이 섞인 deterministic 입력으로 factor 1과 factor 9의 실제 누산 결과를 FP16 연산 순서를 재현한 software golden과 비교한다.

## 2. 조건

- Shape: 4×4×8, 3×3 depthwise
- 1 HBM channel
- 입력: 주기 29의 signed fractional sequence
- 가중치: 주기 23의 signed fractional sequence
- Golden: 각 MUL과 ADD마다 `fp16`으로 rounding
- 비교 출력: 128개

## 3. 결과

| Aggregation factor | Logic partial bursts | FP16 mismatch | FP32 기준 최대 절대오차 | Cycle |
|---:|---:|---:|---:|---:|
| 1 | 1,152 | 0/128 | 0.00601459 | 30,428 |
| 9 | 128 | 0/128 | 0.00601459 | 29,570 |

Factor 9는 partial transfer를 9분의 1로 줄이면서 FP16 결과를 바꾸지 않았다.

## 4. 해석

현재 bank-local accumulator는 tap 0→8 순서를 유지해 순차 덧셈한다. Factor 1도 logic accumulator에서 같은 순서로 더하므로 연산 위치만 바뀌고 FP16 결합 순서는 같다. 따라서 두 결과와 FP32 오차가 동일하다.

향후 adder tree 또는 여러 port의 병렬 reduction으로 바꾸면 결합 순서가 달라질 수 있다. 그때는 bit-exact 비교 대신 모델 허용오차와 정확도 정책을 별도로 정해야 한다.

## 5. 근거 파일

- `results/depthwise_fp16_rounding_factor1.log`
- `results/depthwise_fp16_rounding_factor9.log`

