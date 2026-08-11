# Logic-die output retirement 설계 계약

## 목적

Logic PCU의 channel partial을 하나의 transaction으로 reduction하고, 명령이 지정한 bank 또는 host 경로로 손실 없이 retire한다.

## 현재 RTL 경로

```text
logic_pcu_scheduler raw result
  → cross_channel_reduction_network
  → reduced result {valid, ready, tag, data, destination_bank}
  → logic_result_router
  ├─ bank output
  └─ host output
```

Shared weight는 `logic_shared_buffer`에서 읽어 PCU `src1`에 공급된다. Epoch release, 완성된 operand mask, 동일 tag, 유효한 weight context가 모두 충족돼야 dispatch할 수 있다.

## 필수 신호

- `reduced_result_valid_o`, `reduced_result_ready_i`
- `reduced_result_tag_o`, `reduced_result_data_o`
- `reduced_destination_bank_o`
- `logic_bank_result_*`, `logic_host_result_*`
- reduction duplicate/context error

## 불변 조건

1. 결과가 stalled된 동안 valid, tag, data와 destination은 변하지 않는다.
2. 하나의 결과가 bank와 host 양쪽에서 동시에 valid가 되지 않는다.
3. expected channel mask의 각 channel은 정확히 한 번만 reduction에 참여한다.
4. duplicate channel과 다른 tag는 architectural result에 포함되지 않고 오류로 노출된다.
5. 명령 수락 이후 외부 route 입력이 바뀌어도 이미 발행된 transaction의 목적지는 바뀌지 않는다.
6. output backpressure는 reduction과 PCU 응답까지 전파된다.

## 검증 기준

- 네 채널의 FP16 3.0 partial이 한 개의 12.0 결과로 축약된다.
- 외부 src1과 shared weight를 다르게 설정했을 때 shared weight 기반 결과가 나온다.
- host/bank stall 중 metadata 안정성과 단일 목적지 특성을 검사한다.
- random ready/valid 회귀에서 loss, duplicate, reorder가 없다.
