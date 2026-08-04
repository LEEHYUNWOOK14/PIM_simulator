# 20차 기술 구현 보고서: 공유 가중치 Fill 명령 병목 진단

## 1. 목적

공유 버퍼 fill channel 수를 늘렸을 때 cycle이 단조롭게 감소하지 않은 원인을 찾는다. 총 write가 아니라 각 channel의 다음 값을 실제 명령 경로에서 측정한다.

- 완료된 fill write 수
- 마지막 fill write 완료 cycle
- fill 요청으로 발생한 ACT 명령 수
- 다른 row로 전환하기 위해 발생한 PRE 명령 수

## 2. 계측 구현

공유 가중치 적재 transaction에 다음 tag를 부여한다.

```text
LOGIC_WEIGHT_FILL
```

tag는 `Transaction -> WRITE BusPacket -> DATA BusPacket -> write completion`까지 보존된다. WRITE 대상 row가 현재 open row와 달라 command queue가 PRE를 만들면 원인 요청의 tag도 PRE에 전달한다.

각 channel의 `MemoryController`가 독립적으로 다음 통계를 누적한다.

```text
logicWeightFillWrites
logicWeightFillCompletedWrites
logicWeightFillActivates
logicWeightFillPrecharges
logicWeightFillLastCompletionCycle
```

## 3. 재현 명령

```bash
FILL_POLICY=round_robin \
FILL_CHANNELS_LIST='16 32 64' \
RESULT_FILE=experiment/results/shared_weight_fill_timing_diagnostics.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 4. 결과

| Fill channels | Writes/channel | Last completion | ACT | PRE | Total cycle |
|---:|---:|---:|---:|---:|---:|
| 16 | 224 | 109,941 | 768 | 384 | 223,414 |
| 32 | 112 | 109,528 | 1,536 | 768 | 224,150 |
| 64 | 56 | 108,496 | 1,536 | 0 | 219,405 |

모든 channel에서 최소/최대 write 수와 최소/최대 마지막 완료 cycle이 같았다. 따라서 channel별 요청량 불균형이나 느린 단일 channel은 원인이 아니다.

## 5. 원인 분석

### 5.1 16채널

채널당 224개 write를 처리하므로 queue 길이가 가장 길다. ACT/PRE 수는 32채널보다 적지만 마지막 fill 완료가 가장 늦다.

### 5.2 32채널

채널당 write는 절반으로 줄지만 각 channel이 여러 row 범위를 담당한다. 1,536 ACT와 768 PRE가 필요해 마지막 fill은 조금 빨라져도 전체 compute transaction과의 경합 때문에 total cycle이 16채널보다 736 cycle 증가한다.

### 5.3 64채널

각 channel은 56개 write만 담당하며 fill 중 PRE가 0이다. 요청이 각 channel의 한 open-row 범위에 머물러 row 전환 비용이 제거된다. 마지막 fill 완료도 가장 빠르고, no-buffer hybrid 기준을 통과한다.

## 6. 결론

64채널 crossover의 직접적인 조건은 단순히 “대역폭이 64배”가 아니다.

> 현재 round-robin mapping에서는 channel당 가중치 조각이 한 row 범위에 들어가 fill-induced PRE가 0이 되는 것이 핵심이다.

따라서 RTL 설계에서 중요한 값은 channel 수 외에도 다음과 같다.

1. channel별 weight tile 크기
2. tile이 차지하는 row 수
3. buffer fill 중 허용되는 open-row 수
4. fill과 logic compute command의 arbitration
5. 64개 입력을 중앙 buffer write port로 합치는 구조

## 7. 검증 불변식

실제 UIB 테스트는 공유 버퍼가 활성화되면 다음을 검사한다.

```text
completed fill writes == buffer fill bursts
buffer read misses == 0
outputs checked == 18,816
```

이 조건은 fill transaction이 통계에만 잡히고 실제 완료되지 않는 회귀를 방지한다.

## 8. 다음 단계

다음 구현은 32채널에서도 channel별 tile을 한 row에 유지하는 row-local mapping이다. 같은 32채널 수에서 기존 round-robin과 row-local 정책을 비교해 PRE 768을 제거했을 때 no-buffer 기준 219,854 cycle을 통과하는지 검증한다.
