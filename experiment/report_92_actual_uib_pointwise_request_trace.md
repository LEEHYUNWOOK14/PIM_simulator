# 92차 실험 보고서: 실제 UIB pointwise logic-PCU 요청 trace

## 1. 목적

91차에서는 MobileNetV4 UIB의 다섯 단계 경계와 FP16 데이터 연쇄를 검증했다. 이번 실험은
그 아래에서 expand와 project pointwise가 global logic-PCU scheduler에 실제로 전달한
개별 reservation 요청을 모두 기록한다. 목표는 요청 수, stream 범위, coalescing 효과와 queue
병목을 RTL scheduler의 입력 계약으로 만드는 것이다.

## 2. 계측 위치와 의미

`LogicDieScheduler::reserve()`는 logic-die MAC 명령이 실제로 자원을 예약하는 지점이다.
여기에서 다음 값을 읽기 전용 event history에 저장했다.

| 값 | 의미 |
|---|---|
| `arrival_cycle` | 명령이 global scheduler에 도착한 cycle |
| `service_start_cycle` | 선택된 PCU lane에서 실행을 시작한 cycle |
| `completion_cycle` | compute·transfer·command overhead가 끝나는 cycle |
| `queue_cycles` | PCU lane을 기다린 시간 |
| `stream_id` | channel×rank로 구분한 명령 stream |
| `epoch_id`, `command_ordinal` | broadcast/coalescing 순서를 보존하는 식별자 |
| `dispatch_signature` | 실행할 PIM 명령의 packed signature |
| `coalesced` | 같은 명령 broadcast에 합쳐졌는지 여부 |

계측 벡터는 예약 결과를 읽기만 하며 scheduler의 lane 선택이나 completion 계산에는 참여하지
않는다.

## 3. 재현 명령

```bash
bash experiment/run_uib_integration_trace.sh
```

이미 생성된 trace만 다시 분석할 때는 다음을 실행한다.

```bash
python3 experiment/verify_uib_integration_trace.py \
  experiment/results/uib_integration_trace.csv
python3 experiment/analyze_uib_pointwise_requests.py \
  experiment/results/uib_integration_trace.csv.requests.csv
```

## 4. 정확도 및 계약 검증 결과

```text
[  PASSED  ] 1 test.
UIB_INTEGRATION_TRACE PASS stages[5] outputs[18816]
total_stage_span_cycles[230856]
final_fp16_hash[4068a98fc1531583]
expand_requests[42336] project_requests[50176]
expand_coalesced[41616] project_coalesced[49280]
expand_max_queue[78432] project_max_queue[94021]
```

검증기는 92,512개 요청 모두에 대해 다음 식을 확인했다.

```text
service_start_cycle = arrival_cycle + queue_cycles
completion_cycle    = service_start_cycle + service_cycles
```

또한 모든 요청이 expand 또는 project의 실제 stage cycle 범위 안에서 도착했는지 검사했다.
최종 출력 18,816개와 단계 사이 FP16 해시도 91차와 동일하게 통과했다.

## 5. 요청 분석 결과

| 항목 | Expand pointwise | Project pointwise |
|---|---:|---:|
| Reservation 요청 | 42,336 | 50,176 |
| 활성 stream | 63 | 64 |
| 독립 dispatch | 720 | 896 |
| Coalesced 요청 | 41,616 | 49,280 |
| Coalescing 비율 | 98.30% | 98.21% |
| 평균 queue | 39,411.76 cycle | 47,664.04 cycle |
| P95 queue | 74,862 cycle | 90,448 cycle |
| 최대 queue | 78,432 cycle | 94,021 cycle |
| 첫 도착 | 915 cycle | 123,558 cycle |
| 마지막 완료 | 87,027 cycle | 225,702 cycle |

Expand stream이 63개인 이유는 192개 출력을 처리하는 compact spatial group이 channel 3개씩
21개 group을 사용하기 때문이다. Project는 96개 출력에 channel 2개씩 32개 group을 사용해
64개 stream을 모두 사용한다.

## 6. 아키텍처 해석

Command coalescing은 요청의 약 98%를 broadcast에 합쳐 command dispatch 수를 크게 줄인다.
그러나 합쳐진 각 stream의 연산 자체는 global PCU lane을 사용하므로 queue가 사라지지는 않는다.
현재 최대 queue가 두 stage 모두 수만 cycle이라는 결과는 pointwise 병목의 우선순위가 다음과
같음을 보여준다.

1. Global PCU lane 수와 한 명령의 service time
2. Spatial group이 한꺼번에 만드는 stream fanout
3. Weight/output buffer와 scheduler 사이의 release 정책
4. 그 이후에 command bus dispatch overhead

따라서 depthwise용 공유 FP16 pipeline 2개 후보만으로 전체 UIB logic die를 확정할 수 없다.
Pointwise MAC array와 depthwise accumulator는 서로 다른 자원으로 분리하거나, 같은 lane을 공유할
경우 명시적인 arbitration과 queue capacity를 설계해야 한다.

## 7. 다음 단계

다음 실험에서는 이 92,512개 요청 trace를 대상으로 global logic-PCU lane 수와 queue depth를
replay한다. 우선 8·16·32·64 PCU 후보에서 평균/P95/최대 queue, total completion과 필요 queue
entry를 비교한다. 그 결과를 pointwise scheduler RTL의 `PCU_COUNT`, `QUEUE_DEPTH`,
`DISPATCH_WIDTH` 후보로 사용한다.

현재 trace에는 scheduler 예약과 command payload 식별자가 있지만 실제 weight/input FP16 payload는
아직 포함하지 않는다. 자원 후보를 줄인 뒤 선택한 구성에 대해서만 payload replay RTL을 붙여
파일 규모와 검증 시간을 관리한다.
