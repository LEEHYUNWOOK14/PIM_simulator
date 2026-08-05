# 65차 실험 보고서: Full UIB rank command reject 원인 분해

## 1. 목적

Full MobileNetV4 UIB에서 하나의 `rank_command_rejects` 합계로만 보이던 command 발행 거절을 원인과 실행 domain별로 분해한다. Logic-die PIM의 다음 성능 수정 대상을 broadcast queue와 mode transition 중에서 구분하는 것이 목적이다.

## 2. 추가한 계측

Rank는 command 수락 실패 시 다음 원인을 기록한다.

| 원인 | 의미 |
|---|---|
| `MODE_TRANSITION` | 현재 cycle이 해당 domain의 `modeReadyCycle`보다 이르다. |
| `LOGIC_QUEUE_BACKPRESSURE` | Online broadcast mask queue가 새 command를 받을 수 없다. |

MemoryController는 실제 발행 시도에서만 다음 카운터를 증가시킨다.

- `rank_mode_transition_rejects`
- `rank_logic_queue_rejects`
- `rank_bank_domain_rejects`
- `rank_logic_domain_rejects`

측정용 probe는 카운터를 증가시키지 않는다. 테스트는 다음 두 불변식을 확인한다.

```text
rank_command_rejects = rank_mode_transition_rejects + rank_logic_queue_rejects
rank_command_rejects = rank_bank_domain_rejects + rank_logic_domain_rejects
```

## 3. 재현 명령

빠른 계측 회귀:

```bash
bash experiment/run_hab_direct_output_regression.sh
```

Full UIB:

```bash
RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
RAW_FILL_CHANNELS=32 HIERARCHY_SOURCE_QUEUES=true \
OUTPUT_BUFFER_ENABLE=true OUTPUT_BUFFER_ENTRIES=2 \
OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
HAB_RESIDENCY=true MODE_TRANSITION_LATENCY=32 \
PIM_RUN_WATCHDOG_CYCLES=0 EPOCH_RELEASE=true \
ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH=128 \
HIERARCHY_READY_BYPASS=true FILL_POLICY=row_interleaved \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 4. 결과

| 지표 | 3 channels | 6 channels | Full UIB |
|---|---:|---:|---:|
| 출력 검증 | 384 PASS | 768 PASS | 18,816 PASS |
| Total cycle | 1,706 | 2,515 | 235,182 |
| Rank reject 합계 | 6,294 | 12,588 | 1,943,168 |
| Mode transition | 6,294 | 12,588 | 1,943,168 |
| Logic queue | 0 | 0 | 0 |
| Bank domain | 0 | 0 | 669,056 |
| Logic domain | 6,294 | 12,588 | 1,274,112 |

Full 원본 결과는 `experiment/results/full_uib_rank_reject_breakdown.csv`와 `experiment/results/full_uib_rank_reject_breakdown.log`에 저장했다.

## 5. 출력 해석

```text
rank_command_rejects[1943168]
rank_mode_transition_rejects[1943168]
rank_logic_queue_rejects[0]
rank_bank_domain_rejects[669056]
rank_logic_domain_rejects[1274112]
```

1. Rank 계층에서 거절된 command는 모두 mode transition ready 대기였다.
2. Broadcast queue depth 128은 이 workload에서 rank 거절을 만들지 않았다.
3. Logic domain이 전체 rank 거절의 약 65.57%, bank domain이 약 34.43%다.
4. Bank와 logic의 mode context를 분리해도 두 domain 모두 mode 전환 비용을 가진다.

## 6. 주의사항

Reject 값은 손실 cycle이 아니다. CommandQueue가 여러 channel과 후보 command를 매 cycle 검사하면서 거절된 **시도 횟수**다. 따라서 `1,943,168 rejects = 1,943,168 cycles`로 해석하면 안 된다. Mode latency 32가 full UIB total cycle에 얼마나 기여하는지는 latency 0/32 A/B와 channel별 reject wall-cycle 계측으로 판단해야 한다.

또한 다음 값은 Rank보다 앞선 controller 조건이다.

```text
epoch_mismatch_rejects[8940258]
barrier_outstanding_rejects[1225410]
write_bus_busy_rejects[93051750]
```

서로 다른 검사 단계의 후보 시도 횟수이므로 숫자 크기만 비교해 병목 순위를 정할 수 없다.

## 7. 다음 구현

1. `CommandQueue::isIssuable()` 실패를 logic-PCU busy, wrong mode, bank idle/active, timing-ready, row mismatch, row-access-limit로 분해한다.
2. 같은 cycle에 같은 원인이 여러 후보에서 발생해도 한 번만 세는 wall-cycle counter를 병행한다.
3. Mode latency 0/32 A/B에서 total cycle, reject attempts, reject wall cycles를 함께 비교한다.
4. 그 결과로 mode FSM 최적화, barrier 축소, bus arbitration 중 실제 critical path에 있는 항목을 선택한다.

## 8. 결론

현재 Rank-level 병목 후보는 broadcast queue가 아니라 mode transition ready다. 다만 reject attempt 수만으로 cycle 기여도를 확정할 수 없으므로, 다음 단계에서 DRAM issuability와 wall-cycle을 함께 계측한 뒤 설계 변경 여부를 판단한다.
