# C11 Timing Optimization and Actual-trace Report

## 현재 결론

C11은 C10의 정확도 알고리즘을 유지하면서 reduction, scalar, apply의 긴 조합경로를 파이프라인화한 구조다. 현재 실제 trace에서 bit-exact RTL 검증을 통과했으며, C10 대비 core normalization 시간은 약 1.4배 개선될 것으로 측정된다. 다만 apply의 27.85ns 경로 때문에 40MHz timing closure는 아직 달성하지 못했고 현재 추정 Fmax는 약 35.9MHz다.

## 구조 변경

| 블록 | C10 | C11 |
|---|---|---|
| local reduction | 단일 FP32 accumulator feedback | 4-way interleaved FP32 accumulator |
| global reduction | combinational balanced tree | 4-level pipelined balanced tree |
| scalar | state별 combinational FP32 operator | shared pipelined add/mul FSM, NR2 유지 |
| apply | 4 combinational arithmetic stages | 12-cycle arithmetic pipeline, II=1 |
| apply backpressure | global pipeline clock-enable | 16-entry reservation FIFO |
| FIFO write select | 최초 binary pointer | one-hot pointer로 fanout 제한 |

## 기능 검증

| 검증 | 결과 |
|---|---|
| `fp32_add_pipe4` | 20,225 vectors bit-exact, latency 3, II=1 |
| `fp32_mul_pipe4` | 20,225 vectors bit-exact, latency 3, II=1 |
| interleaved reducer | vector_count 1/6/8 PASS, II=1 |
| pipelined global tree | latency 18, 3-cycle stall PASS |
| pipelined scalar | 16 LayerNorm/RMSNorm requests, C10 bit-exact |
| pipelined apply | 64 vectors, C10 bit-exact, 20-cycle output stall PASS |

## Sky130 TT 25C 1.8V mapping

10ns constraint에서의 data arrival 기준이다. 음수 slack은 100MHz 미달을 뜻하며, 각 블록의 실현 가능한 주파수 비교에는 arrival time을 사용한다.

| 블록 | 수정 전 | C11 | 개선 | C11 cell area |
|---|---:|---:|---:|---:|
| FP32 add | 10.49ns | 10.41ns | clock-enable fanout 제거 | 12,875µm² 수준 |
| local reducer | 18.05ns | 12.83ns | 1.41x | 209,526µm² 수준 |
| global reducer | 42.48ns | 15.50ns | 2.74x | 371,676µm² 수준 |
| scalar | 78.34ns | 22.54ns | 3.48x | 73,920.896µm² |
| apply | 61.06ns | 27.85ns | 2.19x | 504,456.314µm² |

apply 최적화 과정에서 고팬아웃 global enable을 제거해 243.93→40.92ns, FIFO binary write pointer를 one-hot으로 바꿔 40.92→27.85ns로 줄였다. 현재 apply 임계경로는 복제된 FP32 multiplier 내부 exponent/round stage다.

> 면적은 generic synthesized cell area이며 배치·배선 후 physical area가 아니다. 특히 16-bank top은 apply 복제로 면적 부담이 크므로 최종 선택 전에 PPA 재평가가 필요하다.

## 실제 GR00T trace

| profile | shape | elements | RTL vs C11 | RTL vs PyTorch | cycles | cycles/row |
|---|---:|---:|---:|---:|---:|---:|
| action_dit_norm3 | 41×1536 | 62,976 | 0 mismatch | 0 mismatch | 6,520 | 159.02 |
| action_vlln | 280×2048 | 573,440 | 0 mismatch | 5 mismatch | 49,001 | 175.00 |
| action_vl_self_attention_norm1 | 280×2048 | 573,440 | 0 mismatch | 7 mismatch | 49,001 | 175.00 |
| action_vl_self_attention_norm3 | 280×2048 | 573,440 | 0 mismatch | 17 mismatch | 49,001 | 175.00 |
| action_dit_adaln_norm1 | 41×1536 | 62,976 | 0 mismatch | 4 mismatch | 6,520 | 159.02 |
| action_dit_norm_out | 41×1536 | 62,976 | 0 mismatch | 4 mismatch | 6,520 | 159.02 |

전체 합계는 6/6 profile, 1,909,248 elements에서 C11 model mismatch 0, PyTorch bit mismatch 37이다. DSE의 C11 예측과 정확히 일치한다.

측정 cycle은 `rows × (111 + 2 × vectors_per_bank) + 1`과 일치한다. 이는 1536에서 159 cycles/row, 2048에서 175 cycles/row다.

## C10 대비 핵심 연산 시간

`action_dit_norm3`에서 C10의 개선된 testbench 측정은 약 79 cycles/row였다. 그러나 C10 top의 가장 긴 scalar 경로 78.34ns를 적용하면 약 6.19µs/row다. C11은 159.02 cycles/row와 27.85ns apply 경로를 적용하면 약 4.43µs/row다.

따라서 현재 증거에서:

- 정확도: C10 수준 유지
- cycle count: scalar 파이프 대기로 약 2.0배 증가
- clock period: 약 2.81배 단축
- 환산 core time: 약 1.40배 개선

이는 메모리 replay/write-back과 on-die traffic을 포함한 end-to-end speedup이 아니라 normalization compute core의 개선치다.

## 남은 작업

1. FP32 multiplier의 exponent/round stage를 한 단계 더 분할해 apply를 25ns 이하로 timing-close한다.
2. C11 measured cycle/Fmax와 실제 traffic을 architecture 비교 모델에 반영한다. **완료**
3. multi-row/lane/scalar 병렬 구조를 구현하고 projected speedup을 RTL로 검증한다.
4. GPU 대비 유리할 때만 replay/DRAM write-back RTL을 production 수준으로 확장한다.

## 재현

```bash
bash verification/groot_normalization/run_fp32_add_pipe4_test.sh
bash verification/groot_normalization/run_fp32_mul_pipe4_test.sh
bash verification/groot_normalization/run_mixed_precision_interleaved_reducer_test.sh
bash verification/groot_normalization/run_mixed_precision_global_pipe_test.sh
bash verification/groot_normalization/run_mixed_precision_scalar_pipe_test.sh
bash verification/groot_normalization/run_mixed_precision_apply_pipe_test.sh
GROOT_PROFILE_FILTER=action_vlln bash verification/groot_normalization/run_groot_mixed_precision_c11_trace_test.sh
```
