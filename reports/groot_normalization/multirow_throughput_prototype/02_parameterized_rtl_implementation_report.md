# Parameterized RTL Implementation Report

## 구현 결과

다음 parameterized C11 prototype을 구현했다.

- `mixed_precision_bank_reducer_interleaved`: 4/8/16-lane balanced FP32 tree
- `mixed_precision_bank_apply_pipe`: 4/8/16-lane FP32 apply, final BF16 RNE
- `mixed_precision_scalar_engine_array`: 4/8/16 NR2 scalar engines
- `mixed_precision_row_context_table`: tag별 mode/inv_hidden/epsilon
- `mixed_precision_multirow_datapath`: reduce/scalar/apply overlap top
- `mixed_precision_bank_reducer_pingpong`: 2-context accumulator로 row drain 숨김

## 단위 검증

| block | configurations | result |
|---|---|---|
| generic reducer | lanes 4/8/16 | 3 cases each, II=1 PASS |
| generic apply | lanes 4/8/16 | 64 vectors, C11 reference bit-exact, 20-cycle stall PASS |
| scalar array | engines 4/8/16 | 12/24/48 requests, 10-cycle stall PASS |
| multi-row top | lanes 4/8/16, scalar 4 | 8 rows, zero-loss/tag/order, 12-cycle stall PASS |

## Multi-row overlap

상수 LayerNorm synthetic test에서 다음을 확인했다.

- row n+1 reduction이 row n output 전에 시작됨
- context occupancy 최대 3
- reduce, scalar, apply가 서로 다른 row에서 동시에 active
- arbitrary output stall 이후 데이터 손실 없음

## Ping-pong reducer 효과

초기 multi-row top은 local reducer가 마지막 vector 뒤 accumulator drain/combine 동안 다음 row begin을 막았다. 두 accumulator context를 번갈아 사용하도록 변경해 row n+1 input과 row n drain을 겹쳤다.

8-row synthetic cycle:

| lanes | single-context | ping-pong | improvement |
|---:|---:|---:|---:|
| 4 | 277 | 225 | 1.23x |
| 8 | 301 | 228 | 1.32x |
| 16 | 325 | 234 | 1.39x |

## Numerical model

lane 폭별 실제 reduction association을 Python golden에 반영했다.

| lanes | profiles PASS | PyTorch bit mismatch | max abs |
|---:|---:|---:|---:|
| 4 | 6/6 | 37 | 0.015625 |
| 8 | 6/6 | 39 | 0.015625 |
| 16 | 6/6 | 37 | 0.015625 |

lane 확장은 기존 정확도 gate를 손상하지 않는다.

## 주요 검증 명령

```bash
bash verification/groot_normalization/run_mixed_precision_generic_reducer_test.sh
bash verification/groot_normalization/run_mixed_precision_generic_apply_test.sh
bash verification/groot_normalization/run_mixed_precision_scalar_array_test.sh
bash verification/groot_normalization/run_mixed_precision_multirow_test.sh
```

