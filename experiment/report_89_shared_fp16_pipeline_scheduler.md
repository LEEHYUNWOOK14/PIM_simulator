# 89차 실험 보고서: 8-source 공유 FP16 pipeline scheduler

## 1. 설계 목적

88차 합성에서 source마다 16-lane FP16 가산기를 복제하면 면적 proxy가 매우 커지는
것을 확인했다. 이번 실험은 channel 하나의 8개 PIM-block source가 제한된 수의
16-lane FP16 burst pipeline을 공유하는 구조를 구현하고 다음을 비교한다.

- FP16 결과 정확도
- round-robin 공정성
- pipeline 1·2·4개 처리 cycle
- scheduler와 operand routing을 포함한 합성 proxy
- C++ cycle simulator의 link bandwidth·overlap과의 관계

## 2. RTL 구조

```text
8 source valid/key/slot/partial
→ source별 16-entry state buffer
→ eligible request
→ round-robin shared pipeline fabric
→ 1·2·4개의 16-lane FP16 adder
→ 선택된 source entry writeback
→ final valid/key/data
```

| 파일 | 역할 |
|---|---|
| `rtl/shared_fp16_pipeline_fabric.sv` | round-robin grant, operand mux, 제한된 FP16 pipeline, result routing |
| `rtl/shared_fp16_reduction_cluster.sv` | 8-source entry buffer와 shared fabric 결합 |
| `rtl/tb/shared_fp16_reduction_cluster_tb.sv` | 1·2·4 pipeline 기능 및 cycle 검증 |

source별 key와 partial 상태는 유지하지만 FP16 연산기는 공유한다. 선택되지 않은
source는 valid를 유지하고 grant를 받을 때까지 기다린다. 한 source가 계속 요청해도
round-robin pointer가 이동하므로 다른 source가 굶지 않는다.

## 3. RTL 기능 결과

재현 명령:

```bash
bash rtl/run_shared_cluster_tests.sh
```

실제 출력:

```text
SHARED_FP16_REDUCTION_CLUSTER_TB PASS pipelines[1] partials[24] finals[8] service_cycles[26]
SHARED_FP16_REDUCTION_CLUSTER_TB PASS pipelines[2] partials[24] finals[8] service_cycles[14]
SHARED_FP16_REDUCTION_CLUSTER_TB PASS pipelines[4] partials[24] finals[8] service_cycles[8]
```

8 source가 각각 FP16 vector `1`, `2`, `3`을 보내고 final 16 lane이 모두 `6`인지
확인했다. 모든 source가 update 세 개와 final 하나를 완료했으므로 총 partial은 24,
final은 8이다.

| Pipeline | Service cycle | 이상적 연산 cycle | 관측 오버헤드 |
|---:|---:|---:|---:|
| 1 | 26 | 24 | 시작·final 관측 2 |
| 2 | 14 | 12 | 2 |
| 4 | 8 | 6 | 2 |

처리율이 pipeline 수에 맞춰 증가하고 8 source가 모두 완료되어 scheduler 기능과
공정성을 확인했다.

## 4. Shared fabric 합성 결과

재현 명령:

```bash
bash rtl/run_shared_fabric_synthesis.sh
```

| Source | Pipeline | 총 FP16 lane | Generic cell | Flip-flop | Depth |
|---:|---:|---:|---:|---:|---:|
| 8 | 1 | 16 | 69,313 | 3 | 292 |
| 8 | 2 | 32 | 138,075 | 3 | 340 |
| 8 | 4 | 64 | 279,940 | 3 | 434 |

이 값에는 FP16 adder뿐 아니라 8-source operand 선택 mux, result routing,
round-robin 제어가 포함된다. pipeline 수가 늘면 병렬 adder와 multi-grant 선택망이
함께 커지므로 단순 `51,632×P`보다 크다.

8-source entry buffer와 fabric 전체를 한 번에 flatten한 합성은 register-array mux가
크게 펼쳐져 10분 안에 끝나지 않았다. 따라서 다음 비교는 88차에서 독립 합성한
source buffer/control proxy `37,355 cell/source`와 이번 fabric 실측을 합한 추정이다.
서로 다른 합성 단위의 합이므로 cross-module 최적화를 포함한 정확한 top 면적은 아니다.

| Channel 후보 | 추정 cell | 전용 8-pipeline 기준 절감 |
|---|---:|---:|
| Shared 1 pipeline | 368,153 | 48.29% |
| Shared 2 pipelines | 436,915 | 38.63% |
| Shared 4 pipelines | 578,780 | 18.70% |
| Source별 전용 8 pipelines | 711,896 | 기준 |

## 5. C++ 모델 연결

기존 `BANK_LOCAL_ACCUMULATOR_PORTS`는 bank-local tap aggregation port이므로 이번
logic-die shared pipeline에 재사용하면 의미가 섞인다. 새 설정을 추가했다.

```ini
LOGIC_ACCUMULATOR_PIPELINES=0
```

| 값 | 의미 |
|---:|---|
| 0 | 이전 `transfer cycle + latency` 계산을 유지하는 호환 모드 |
| 1 이상 | 동시에 처리하는 32 B FP16 burst pipeline 수 |

새 모델은 다음 두 시간을 계산하고 큰 값을 사용한다.

```text
transferCycles = ceil(bytes / LOGIC_ACCUMULATOR_BW)
bursts         = ceil(bytes / 32 B)
computeCycles  = LOGIC_ACCUMULATOR_LATENCY + ceil(bursts / pipelines) - 1
serviceCycles  = max(transferCycles, computeCycles)
```

전송과 pipeline 연산이 겹친다는 가정이며, `LOGIC_ACCUMULATOR_OVERLAP`은 이 service
시간이 이전 bank-side 실행과 추가로 겹칠 수 있는지를 결정한다.

## 6. C++ pipeline feedback 결과

재현 명령:

```bash
bash experiment/run_shared_pipeline_feedback.sh
```

조건은 1 channel, aggregation 3, logic latency 4, link 64 B/cycle이다.

| Overlap | Pipeline | Total cycle | Accumulator wait | Overlap cycle |
|---|---:|---:|---:|---:|
| OFF | 1 | 30,334 | 393 | 0 |
| OFF | 2 | 29,894 | 201 | 0 |
| OFF | 4 | 29,894 | 192 | 0 |
| ON | 1 | 29,894 | 0 | 393 |
| ON | 2 | 29,894 | 0 | 201 |
| ON | 4 | 29,894 | 0 | 192 |

32 B pipeline 두 개는 cycle당 64 B를 처리하므로 현재 64 B/cycle link와 처리율이
같다. pipeline 네 개를 두어도 link가 병목이라 total cycle은 더 줄지 않는다.
pipeline 한 개는 overlap을 끄면 440 cycle 느리다. overlap을 켜면 이번 1채널
workload에서는 세 후보의 service 시간이 모두 기존 실행 뒤에 숨는다.

## 7. 현재 판단

현재 조건의 첫 기준 후보는 **channel당 16-lane pipeline 2개**다.

- 64 B/cycle link를 채우는 최소 pipeline 수다.
- 4개와 같은 total cycle을 보였다.
- source별 전용 8개보다 channel-level cell proxy를 약 38.63% 줄인다.
- pipeline 1개보다 overlap이 사라지는 workload에서 안전하다.

이는 최종 architecture 확정이 아니다. 실제 공정 합성, 64채널 동시 traffic,
pointwise와 depthwise가 같은 pipeline을 공유하는 경우를 확인해야 한다.

## 8. 다음 단계

다음에는 actual MobileNetV4 64채널 payload trace를 channel당 pipeline 1·2·4개
scheduler에 재생한다. source FIFO peak, grant stall, final link utilization을 함께
측정하면 1채널 소형 실험에서 선택한 pipeline 2개가 전체 traffic에서도 충분한지
판단할 수 있다.

이 단계는 90차 실험에서 수행했다. 세 후보 모두 13,879 cycle로 같았고 pipeline
2개는 pipeline 4개와 같은 peak channel FIFO 및 완료 cycle을 유지하면서 더 작은
합성 proxy를 보였다. 현재 depthwise trace의 기준 후보는 pipeline 2개로 유지한다.
