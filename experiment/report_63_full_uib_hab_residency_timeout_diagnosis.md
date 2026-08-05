# 63차 실험 보고서: Full UIB HAB residency timeout 진단

> **해결 상태(2026-08-05):** 이 문서는 수정 전 timeout을 기록한 진단 보고서다. 이후 watchdog으로 원인을 확정하고 direct logic output을 DRAM bank row 상태에서 분리하여 해결했다. 수정 내용과 최종 재검증 결과는 `experiment/report_64_direct_output_frontend_fix_and_full_uib_validation.md`를 따른다.

## 1. 목적

62차 마이크로벤치마크에서 확인한 HAB residency 성능 이득을 full MobileNetV4 UIB로 확장할 수 있는지 검증한다.

## 2. 기준 설정

```text
HIERARCHY_SOURCE_QUEUES=true
LOGIC_OUTPUT_BUFFER_ENABLE=true
LOGIC_OUTPUT_BUFFER_ENTRIES=2
LOGIC_OUTPUT_DRAIN_LATENCY=4
LOGIC_OUTPUT_DRAIN_BW=8
LOGIC_MODE_TRANSITION_LATENCY=32
LOGIC_EPOCH_RELEASE=true
LOGIC_ONLINE_QUEUE_BACKPRESSURE=true
LOGIC_BROADCAST_QUEUE_DEPTH=128
HIERARCHY_READY_BYPASS=true
```

## 3. Full UIB 기준 결과

HAB residency OFF:

```text
outputs_checked[18816]
rank_command_rejects[1209004]
total_cycle[235182]
[  PASSED  ] 1 test.
```

- 18,816개 pointwise 출력과 전체 bank-side 단계가 정확성 검증을 통과했다.
- `LOGIC_MODE_TRANSITION_LATENCY=32`가 실제 rank command backpressure로 반영됐다.
- wall-clock 실행 시간은 약 292초였다.

## 4. HAB residency ON 결과

동일 조건에서 residency만 ON으로 변경한 full UIB는 600초 제한 안에 끝나지 않았다. 프로세스는 CPU를 계속 사용하고 있었으므로 즉시 crash한 것은 아니지만, 기준 실행보다 2배 이상 오래 진행되어 정상적인 성능 경로로 볼 수 없다.

timeout 후 남은 WSL 자식 프로세스를 종료했고, 스크립트의 trap이 다음 기본 설정을 복구한 것을 확인했다.

```text
HIERARCHY_SOURCE_QUEUES=false
LOGIC_OUTPUT_BUFFER_ENABLE=false
LOGIC_HAB_RESIDENCY=false
LOGIC_MODE_TRANSITION_LATENCY=0
```

## 5. 축소 재현

실제 expand 채널 크기 `96 -> 192`를 유지하고 position을 `196 -> 42`로 줄인 다음 테스트에서도 문제가 재현됐다.

```text
MobileNetV4WorkloadTest.NonblockingExpandFeedsTwoDepthwiseTileRows
```

| Output buffer entries | 결과 | 제한 시간 |
|---:|---:|---:|
| 2 | TIMEOUT | 240초 |
| 64 | TIMEOUT | 240초 |

출력 버퍼를 32배 늘려도 진행 문제가 사라지지 않았으므로 단순 output buffer capacity 부족은 원인이 아니다.

## 6. 현재까지 확인된 범위

| 조건 | 결과 |
|---|---|
| 1 channel, 1 group, 2 waves | 정확성 PASS, cycle 감소 |
| 64 groups, group당 1 channel, 2 waves, 작은 channel dimension | 정확성 PASS, 교착 없음 |
| MobileNetV4 expand 크기, group당 여러 channel, 긴 command stream | timeout 재현 |
| 위 조건에서 output buffer 2 -> 64 | timeout 유지 |

이 판단은 수정 전 코드에만 적용된다. 수정 후에는 `LOGIC_HAB_RESIDENCY=true`에서도 full workload 정확성 검증이 통과했다. 기본값 `false`는 하드웨어 수치가 확정되지 않은 실험 기능이라는 이유로 계속 유지한다.

## 7. 유력한 원인 범위

현재 증거로 확정된 단일 원인은 없지만 다음 범위로 좁혀졌다.

1. 여러 channel이 하나의 spatial group을 구성할 때 group별 HAB 상태와 channel별 실제 mode 완료 시점이 어긋날 가능성
2. HAB에 상주한 여러 channel의 source-scoped mode epoch와 다음 wave command epoch 사이 순환 대기
3. 긴 CRF/MAC/writeback stream에서 direct output drain barrier가 다음 `HAB -> HAB_PIM` control queue와 만드는 ordering 문제
4. mode latency ready가 command queue head를 막는 동안 다른 channel의 동일 group barrier가 완료되지 않는 현상

출력 버퍼 capacity 실험으로 1차적인 저장 공간 부족은 제외했다.

## 8. 다음 축소 실험

다음 순서로 최소 재현점을 찾아야 한다.

1. 3 channels, 1 group, 2 waves, `3 -> 192` pointwise
2. 6 channels, 2 groups, 2 waves, `3 -> 192` pointwise
3. 입력 channel을 `3 -> 96`으로 늘려 CRF/MAC stream 길이만 증가
4. 각 단계에서 mode latency 0/32 비교
5. epoch mismatch, barrier outstanding, rank command reject를 일정 sim-cycle마다 출력
6. 마지막 진행 command tag와 각 channel의 mode/ready cycle을 watchdog dump로 기록

이 과정을 통해 channel 수, group 수, input tile 수 중 어느 축에서 진행 불능이 시작되는지 구분할 수 있다.

## 9. 결론

수정 전 결론은 mode-independent output drain의 데이터 소스만 logic PIM으로 바뀌었고 command frontend는 여전히 일반 DRAM READ 경로를 사용했다는 점을 놓쳤다. 후속 64차 실험에서 이 불일치를 수정했으며, residency ON full UIB가 18,816개 출력을 모두 통과했다.
