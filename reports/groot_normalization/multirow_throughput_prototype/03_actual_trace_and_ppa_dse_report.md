# Actual Trace and PPA DSE Report

## Actual trace cycle

`action_dit_norm3` 41×1536, 62,976 elements에서 모두 model bit-exact다.

| configuration | cycles | vs serial C11 6,520 | max contexts |
|---|---:|---:|---:|
| 4 lanes / 4 scalar | 1,201 | 5.43x | 3 |
| 8 lanes / 4 scalar | 820 | 7.95x | 3 |
| 16 lanes / 4 scalar | 761 | 8.57x | 3 |

16 lanes에서 scalar engines를 4→8→16으로 늘려도 cycle은 모두 1,331(single-context reducer 당시)로 동일했다. ping-pong 이후에도 scalar 4개가 병목이 아니므로 추가 복제는 제외했다.

## 8-lane winner full trace

| profile | elements | cycles | model mismatch | PyTorch mismatch |
|---|---:|---:|---:|---:|
| action_vlln | 573,440 | 5,448 | 0 | 7 |
| action_vl_self_attention_norm1 | 573,440 | 5,448 | 0 | 8 |
| action_vl_self_attention_norm3 | 573,440 | 5,448 | 0 | 18 |
| action_dit_adaln_norm1 | 62,976 | 820 | 0 | 2 |
| action_dit_norm3 | 62,976 | 820 | 0 | 0 |
| action_dit_norm_out | 62,976 | 820 | 0 | 4 |
| **total** | **1,909,248** | — | **0** | **39** |

steady-state는 1536-hidden에서 약 20.0 cycles/row, 2048-hidden에서 약 19.46 cycles/row다.

## Sky130 component mapping

TT 25C 1.8V, 10ns constraint의 data arrival와 mapped cell area다.

| component | parameter | area (mm²) | arrival | Fmax |
|---|---:|---:|---:|---:|
| reducer | 4 | 0.211 | 20.81ns | 48.05MHz |
| reducer | 8 | 0.320 | 22.17ns | 45.11MHz |
| reducer | 16 | 0.540 | 34.70ns | 28.82MHz |
| apply | 4 | 0.505 | 23.85ns | 41.93MHz |
| apply | 8 | 0.983 | 27.87ns | 35.88MHz |
| apply | 16 | 1.941 | 50.72ns | 19.72MHz |
| scalar array | 4 | 0.299 | 27.57ns | 36.27MHz |
| scalar array | 8 | 0.598 | 39.66ns | 25.21MHz |
| scalar array | 16 | 1.195 | 30.86ns | 32.40MHz |

## Lane-level 판단

16 banks와 scalar4/global을 합한 component-sum 하한:

| lanes | representative cycles | component Fmax | core time | area lower bound |
|---:|---:|---:|---:|---:|
| 4 | 1,201 | 36.27MHz | 33.11µs | 12.13mm² |
| 8 | 820 | 35.88MHz | **22.85µs** | 21.52mm² |
| 16 | 761 | 19.72MHz | 38.60µs | 40.37mm² |

16 lanes는 8 lanes보다 cycle이 7.2% 적지만 timing이 45% 낮고 면적이 88% 커 실제 시간은 더 느리다. 8 lanes가 최소 latency 후보다.

## Full-top synthesis audit

8-lane/4-scalar flat Sky130 mapping을 직접 시도했다.

- pre-ABC mapped flip-flops: 301,301
- normal ABC mapping: 15분 timeout
- peak observed memory: 약 60%
- netlist 및 full-top STA: 미생성

따라서 위 면적/Fmax는 full-top P&R 결과가 아니라 낙관적인 component bound다. production feasibility에는 오히려 불리한 불확실성이다.

