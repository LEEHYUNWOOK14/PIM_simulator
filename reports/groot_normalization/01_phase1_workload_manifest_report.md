# Phase 1 보고서: GR00T Normalization Workload Manifest

- 수행일: 2026-08-11
- 입력 기준선: `00_phase0_baseline_report.md`
- 기계 판독 산출물: `gr00t_normalization_profile_manifest.csv`
- 판정: **PARTIAL PASS — 검증 가능한 policy/Qwen profile manifest 완료, 실제 E2E profiling은 미완료**

## 1. 결과

기존 pinned GR00T N1.7 자료와 재실행한 simulator 결과를 이용해 7개 고유 normalization profile을 구조화했다. 현재 검증 범위는 LayerNorm 계열 269회와 RMSNorm 64회, 총 333회다.

| 계열 | 고유 profile | 모델 호출 | 대표 shape | projected element-wise cycle |
|---|---:|---:|---|---:|
| LayerNorm/AdaLayerNorm | 5 | 269 | `[280,2048]`, `[41,1536]` | 1,417,342 |
| RMSNorm | 2 | 64 | `[280,2048]`, `[8960,64]` | 623,040 |
| 합계 | 7 | 333 | 4개 대표 shape | 2,040,382 |

cycle은 각 고유 profile을 한 번 실제 simulator에서 실행한 뒤 공식 호출 수를 곱한 projected 값이다. host reduction/RSQRT가 제외됐으므로 E2E normalization cycle이 아니다.

## 2. 데이터 분류

| 항목 | 상태 | 근거/한계 |
|---|---|---|
| normalization 종류 | `DERIVED` | pinned GR00T/Transformers source와 기존 worklog |
| rows/hidden size | `DERIVED` | checkpoint/deployment/source로 도출 |
| 호출 횟수 | `DERIVED` | layer 수와 denoising step을 이용한 정적 계산 |
| epsilon/affine | `DERIVED` | source와 기존 test profile |
| Bank-PIM cycle | `MEASURED_ONCE_PER_PROFILE` | 2026-08-11 simulator 재실행 |
| 전체 호출 cycle | `PROJECTED` | 단일 profile 측정값 × 호출 수 |
| activation | `SYNTHETIC` | deterministic sinusoidal FP16 |
| 공식 model dtype | `DERIVED_BF16` | checkpoint config |
| 실제 모델 latency 비중 | `UNVERIFIED` | GR00T E2E profiler 미실행 |
| 실제 activation traffic | `UNVERIFIED` | pretrained intermediate trace 미확보 |
| dynamic VL length 분포 | `UNVERIFIED` | typical 280만 사용 |
| vision LayerNorm | `UNVERIFIED/EXCLUDED` | gated Cosmos config의 실제 width 미확인 |

## 3. 논리 payload 정의

CSV의 byte 필드는 FP16/BF16 모두 element당 2 byte라는 전제로 계산한 알고리즘 수준 논리 payload다.

```text
logical_input_bytes  = rows × hidden_size × 2
logical_output_bytes = rows × hidden_size × 2
```

`affine_parameter_bytes_per_call`은 parameter를 호출마다 논리적으로 한 번 읽는 보수적 표기다.

- 일반 LayerNorm: gamma와 beta vector
- RMSNorm: weight vector
- AdaLayerNorm: 현재 workload 의미에 맞춰 row별 scale/shift payload
- non-affine `dit_norm3`: 0 byte

이 값은 다음을 포함하지 않는다.

- PIMSimulator의 131,072-element tile padding
- ADD/MUL 단계 사이의 intermediate row traffic
- cache/weight-buffer reuse
- 실제 HBM burst granularity
- bank/channel 복제
- partial reduction packet
- host/GPU transfer protocol overhead

따라서 현재 byte 필드는 실제 HBM transaction 측정치가 아니라 비교 모델 입력용 **논리 하한/계약값**이다. Phase 2/3에서 각 architecture의 물리 traffic으로 확장한다.

## 4. 통계 scalar 수

`global_stat_scalars_per_call`은 각 row가 최종적으로 요구하는 전역 통계 scalar 수다.

- LayerNorm 계열: row당 SUM과 SUMSQ, 2개
- RMSNorm: row당 SUMSQ, 1개

현재 333회 범위의 전역 통계량은 총 322,040 scalar다.

- LayerNorm 계열: 26,360 scalar
- RMSNorm: 295,680 scalar
- FP32 scalar로 표현하면 총 1,288,160 byte

이는 bank별 partial statistic 수가 아니다. 실제 cross-bank payload는 bank mapping과 활성 bank 수에 따라 증가하므로 Phase 2에서 `rows × statistic_count × active_banks × scalar_bytes` 형태로 계산한다.

## 5. 중요한 workload 관찰

1. RSQRT 호출 수는 tensor element 수가 아니라 normalization row 수에 비례한다.
2. `[8960,64]` Q/K RMSNorm은 hidden dimension은 작지만 row 수가 매우 커서 RSQRT 및 row scheduling 요구가 크다.
3. `[280,2048]`과 `[8960,64]`는 모두 호출당 573,440 elements로 activation payload가 같지만 reduction 구조와 RSQRT 병렬성 요구는 크게 다르다.
4. `[41,1536]` DiT profile은 호출당 tensor는 작지만 260회 호출되어 launch/queue/synchronization 비용에 민감할 가능성이 있다.
5. 따라서 단순 tensor byte만으로 placement를 결정할 수 없으며 rows와 hidden size를 독립 변수로 유지해야 한다.

## 6. 현재 범위의 논리 activation 규모

padding과 중간 버퍼를 제외한 input activation은 모델 1회 projected 기준 총 116,469,760 byte이며 output도 같은 크기다.

- LayerNorm 계열 input: 43,069,440 byte
- RMSNorm input: 73,400,320 byte
- 전체 input+output: 232,939,520 byte

이 합계는 normalization 호출 사이의 tensor reuse나 GPU cache 효과를 반영하지 않은 논리량이다. GPU baseline traffic으로 그대로 사용하지 않는다.

## 7. Phase 1 미완료 항목

로드맵이 요구한 다음 항목은 현재 로컬 증거만으로 완료되지 않았다.

- 실제 GR00T inference에서 normalization latency 비중
- 실제 read/write transaction byte
- 실제 BF16 activation의 분포와 정확도
- 동적 sequence length의 통계
- vision encoder 내부 49개 LayerNorm의 검증된 shape와 호출

따라서 Phase 1 전체를 완료로 닫지 않는다. 다만 Phase 2/3의 구조 정의와 sensitivity model은 현재 manifest의 대표 shape 및 `UNVERIFIED` 범위를 명시한 상태로 병행할 수 있다.

## 8. 다음 작업

1. Phase 2에서 네 architecture의 데이터 이동 경계와 공통 비용식을 고정한다.
2. 실제 GPU profiling이 가능한 로컬 GPU/소프트웨어 환경을 조사한다.
3. GR00T 전체 실행이 불가능하면 measured microbenchmark와 parameter sweep을 분리한다.
4. 실제 activation이 없더라도 BF16 edge/random 정확도는 Phase 4에서 독립 검증한다.

## 9. 완료 판정

검증 가능한 기존 GR00T 범위의 profile manifest는 완료했다. 그러나 실제 모델 E2E profiling 항목이 남아 있으므로 Phase 1은 `PARTIAL PASS`로 유지한다.
