# 93차 실험 보고서: Pointwise PCU 8·16·32·64 trace replay

## 1. 목적

92차에서 수집한 실제 MobileNetV4 UIB pointwise reservation 92,512건을 이용해 global
logic-PCU 수가 queue와 완료 시간에 미치는 영향을 비교한다. 전체 시뮬레이터를 후보마다 다시
실행하기 전에 동일 arrival 조건에서 PCU lane 효과만 분리하는 실험이다.

## 2. Replay 원리

현재 pointwise 명령 하나는 8개의 PIM block을 함께 처리한다. 따라서 PCU 수와 동시에 처리할
수 있는 scheduler lane의 관계를 다음과 같이 두었다.

| Logic PCU | 동시 8-block 명령 lane |
|---:|---:|
| 8 | 1 |
| 16 | 2 |
| 32 | 4 |
| 64 | 8 |

각 요청은 실제 trace의 arrival cycle, service cycle과 coalescing 결과를 그대로 사용한다.
Scheduler와 동일하게 가장 먼저 비는 lane을 선택한다.

```text
start      = max(arrival, selected_lane_busy_until)
queue      = start - arrival
completion = start + service
```

## 3. Baseline 동일성 검증

Trace는 16-PCU 설정에서 생성됐다. Replay 결과를 원본 scheduler 기록과 92,512건 모두 비교했다.

```text
UIB_POINTWISE_PCU_SWEEP PASS
baseline_start_mismatches[0]
baseline_completion_mismatches[0]
```

따라서 replay의 lane 선택, queue와 service 완료 계산은 현재 C++ scheduler와 정확히 같다.

## 4. 재현 명령

기존 trace만 분석할 때:

```bash
python3 experiment/replay_uib_pointwise_pcu_sweep.py
```

UIB 실행부터 trace 생성과 sweep까지 모두 다시 수행할 때:

```bash
bash experiment/run_uib_integration_trace.sh
```

## 5. 결과

### Expand pointwise

| PCU | 평균 queue | P95 queue | 최대 queue | Peak waiting | Arrival→완료 span |
|---:|---:|---:|---:|---:|---:|
| 8 | 82,422.49 | 156,578 | 164,544 | 40,446 | 172,224 |
| 16 | 39,411.76 | 74,862 | 78,432 | 38,556 | 86,112 |
| 32 | 17,906.39 | 34,006 | 35,376 | 34,776 | 43,056 |
| 64 | 7,153.71 | 13,490 | 13,850 | 27,222 | 21,528 |

### Project pointwise

| PCU | 평균 queue | P95 queue | 최대 queue | Peak waiting | Arrival→완료 span |
|---:|---:|---:|---:|---:|---:|
| 8 | 148,232.77 | 236,897 | 245,746 | 50,176 | 253,869 |
| 16 | 47,664.04 | 90,448 | 94,021 | 46,179 | 102,144 |
| 32 | 22,170.17 | 42,012 | 43,283 | 42,619 | 51,072 |
| 64 | 9,423.24 | 17,656 | 18,323 | 36,092 | 25,536 |

Span은 PCU 16→32→64에서 거의 정확히 1/2씩 줄어든다. 이는 네 후보 범위에서는 compute
lane이 계속 포화 상태이며 weight/output보다 scheduler 처리량이 pointwise 완료 시간을 직접
제한한다는 뜻이다.

## 6. Queue depth 해석

PCU 64개에서도 Project의 peak waiting은 36,092건이다. 이를 하나의 물리 중앙 FIFO entry로
구현하는 것은 비현실적이다. 현재 C++ scheduler가 미래 실행을 무제한 예약하고 source 쪽에
backpressure를 즉시 돌려주지 않기 때문에 나타난 값이다.

따라서 이 결과를 “queue를 36,092 entries로 만들자”로 해석하면 안 된다. 올바른 설계 방향은
다음과 같다.

1. Channel/rank의 기존 source queue에 요청을 분산 보관한다.
2. Logic die 중앙에는 작은 ready queue와 stream별 head pointer만 둔다.
3. 중앙 queue가 차면 command issue에 `ready=0`을 전달한다.
4. 한 stream이 queue를 독점하지 않도록 round-robin 또는 age 기반 중재를 사용한다.
5. Bounded queue를 넣은 full simulation에서 arrival 자체가 어떻게 이동하는지 다시 측정한다.

## 7. 후보 판단

- **PCU 8:** 1 lane이라 expand가 끝나기 전에 project arrival이 시작되어 두 stage가 같은 queue에서
  겹친다. 현재 workload에는 부족하다.
- **PCU 16:** 실제 전체 UIB에서 검증된 baseline이지만 최대 queue가 94,021 cycle이다.
- **PCU 32:** 16개 대비 pointwise span을 절반으로 줄이는 중간 후보이며 우선 RTL 면적 비교 대상이다.
- **PCU 64:** 가장 빠르지만 32개 대비 다시 2배의 MAC 자원을 요구하므로 합성 면적·전력 근거가
  필요하다.

현 단계에서는 32개를 우선 Pareto 후보, 16개를 최소 기준, 64개를 성능 상한으로 둔다. 이는
확정 사양이 아니며 bounded queue와 합성 결과가 나온 뒤 다시 판단한다.

## 8. 한계와 다음 단계

이 sweep은 **fixed-arrival sensitivity**다. PCU 수가 바뀌어도 16-PCU 실행에서 관측한 arrival를
그대로 사용하므로 backpressure가 앞단 DRAM 명령 시점까지 이동시키는 효과는 포함하지 않는다.
따라서 다른 PCU 수의 최종 UIB cycle을 확정하는 결과가 아니다.

다음 단계는 중앙 queue depth를 64·128·256 entries로 제한하고 source queue에 backpressure를
연결하는 것이다. 그 뒤 16·32·64 PCU의 전체 UIB를 다시 실행해 정확도, 실제 arrival, queue
occupancy와 end-to-end cycle을 비교해야 한다.

결과 CSV는 `experiment/results/uib_pointwise_pcu_sweep.csv`에 저장된다.
