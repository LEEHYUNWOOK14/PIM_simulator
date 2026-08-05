# 94차 실험 보고서: Bounded pointwise ready queue

## 1. 목적

93차 fixed-arrival replay에서는 중앙 scheduler에 최대 수만 건의 요청이 대기했다. 이번 실험은
모든 요청을 중앙 FIFO에 저장하지 않고 다음 두 계층으로 나눈다.

```text
64 channel/rank stream의 source FIFO
  -> round-robin admission
  -> logic die bounded ready queue
  -> 8-block pointwise PCU lane
```

PCU `16·32·64개`와 중앙 ready queue `64·128·256 entries`의 9개 조합을 실제 UIB
pointwise 요청 92,512건으로 replay한다.

## 2. 모델 규칙

1. 실제 trace의 arrival cycle과 stream별 요청 순서를 유지한다.
2. 요청은 먼저 자신이 속한 source FIFO에 들어간다.
3. Round-robin arbiter가 cycle당 PCU lane 수만큼 중앙 ready queue에 admission한다.
4. 완료되어 비어 있는 PCU lane은 중앙 queue의 head 요청을 받는다.
5. 중앙 queue가 가득 차면 source FIFO에서 더 가져오지 않아 backpressure를 표현한다.
6. 기존 중앙 요청을 먼저 dispatch하고 같은 cycle에 생긴 빈 entry를 다시 채워 인위적인 bubble을
   만들지 않는다.

이번 모델의 source FIFO는 아직 무제한이다. 즉 중앙 queue의 물리 크기를 검증하는 단계이며,
DRAM command issue까지 되돌아가는 end-to-end backpressure는 다음 단계다.

## 3. 재현 명령

```bash
python3 experiment/replay_uib_bounded_pointwise_scheduler.py
```

UIB 실행부터 모든 분석을 다시 수행하려면:

```bash
bash experiment/run_uib_integration_trace.sh
```

## 4. 완료 시간 결과

Queue depth를 64·128·256으로 바꿔도 같은 PCU 수에서 마지막 완료 cycle은 같았다.

| PCU | Lane | Expand 마지막 완료 | Project 마지막 완료 |
|---:|---:|---:|---:|
| 16 | 2 | 87,027 | 225,702 |
| 32 | 4 | 43,971 | 174,630 |
| 64 | 8 | 22,443 | 149,098 |

64-entry ready queue만으로도 PCU lane이 쉬지 않고 동작한다. 128·256 entries는 더 많은 요청을
logic die 중앙에 미리 옮길 뿐 처리량은 높이지 못했다.

## 5. Queue occupancy

### 64-entry 중앙 queue

| PCU | 중앙 peak | 중앙 full cycle | Source peak 전체 | Source당 최대 peak |
|---:|---:|---:|---:|---:|
| 16 | 64 | 187,888 | 46,115 | 836 |
| 32 | 64 | 93,942 | 42,555 | 776 |
| 64 | 64 | 46,968 | 36,021 | 657 |

### Queue depth 증가 효과

| PCU | Depth 64 source peak | Depth 128 | Depth 256 |
|---:|---:|---:|---:|
| 16 | 46,115 | 46,051 | 45,923 |
| 32 | 42,555 | 42,491 | 42,363 |
| 64 | 36,021 | 35,957 | 35,829 |

Queue를 64에서 256으로 4배 늘려도 source peak는 정확히 192건만 감소한다. 중앙에 추가한
192 entries만큼 source 저장량을 옮긴 결과이며 총 대기량 자체는 거의 변하지 않는다.

## 6. 아키텍처 판단

### 확정 가능한 내용

- 중앙 ready queue는 현재 trace에서 **64 entries면 처리량 포화**에 도달한다.
- 128·256 entries는 성능 이득이 없으므로 우선 후보에서 제외한다.
- PCU 처리량이 완료 cycle을 결정하며 32 PCU는 16 PCU 대비 pointwise 구간을 절반으로 줄인다.
- Round-robin admission으로 모든 92,512개 요청이 손실과 교착 없이 완료됐다.

### 아직 확정할 수 없는 내용

- Source당 657~836 entries는 실제 channel/rank queue로 구현하기에 여전히 크다.
- 이 수치는 16-PCU 실행의 arrival를 고정했기 때문에 앞단이 멈추는 효과를 포함하지 않는다.
- 64-entry가 다른 MobileNetV4 shape와 다른 모델에서도 충분한지는 아직 모른다.

## 7. 다음 구현

다음 단계에서는 source FIFO 자체를 `8·16·32 entries/stream`으로 제한한다. FIFO가 가득 차면
도착 요청을 버리지 않고 해당 stream의 후속 issue를 지연시켜 arrival cycle을 재구성한다.
측정할 값은 다음과 같다.

1. Backpressure로 이동한 arrival와 전체 완료 cycle
2. Source FIFO full cycle 및 최대 점유율
3. Stream별 완료 수와 starvation 여부
4. 중앙 64-entry ready queue 사용률
5. PCU 16·32·64의 실제 처리량 포화점

이 결과를 C++의 `LogicDieScheduler::canAccept()`에 pointwise PCU queue 조건으로 연결한 뒤 전체
UIB 정확도와 end-to-end cycle을 다시 측정한다.

결과 CSV는 `experiment/results/uib_bounded_pointwise_scheduler.csv`에 저장된다.
