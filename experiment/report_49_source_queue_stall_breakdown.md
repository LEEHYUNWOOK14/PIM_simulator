# Source queue stall 원인 분해 및 WRITE 완화 실험

## 1. 목적

Source queue ON 전체 MobileNetV4 UIB가 OFF보다 10.5% 느린 원인을 분해하고,
가장 큰 거절 원인을 안전하게 완화할 수 있는지 확인한다.

## 2. 재현 명령

WSL 프로젝트 루트에서 다음 명령을 실행한다. 내부 스크립트가 설정 파일을 백업하고,
실험 종료 시 `HIERARCHY_SOURCE_QUEUES=false`로 원래 상태를 복원한다.

```bash
bash experiment/run_source_queue_stall_breakdown.sh
```

전체 출력은
`experiment/results/full_uib_source_queue_on_stall_breakdown.log`에 저장된다.

## 3. 추가한 계측

명령 발행 predicate의 거절 원인을 다음 네 종류로 분리했다.

| 출력 필드 | 의미 |
|---|---|
| `epoch_mismatch_rejects` | 아직 발행할 차례가 아닌 epoch의 명령 후보 |
| `barrier_outstanding_rejects` | 같은 epoch의 이전 transaction 완료를 기다리는 BAR |
| `write_bus_busy_rejects` | 예약 또는 전송 중인 WRITE data 때문에 대기한 WRITE |
| `rank_command_rejects` | 현재 Rank/PIM mode에서 받을 수 없는 명령 |

이 값들은 여러 채널과 명령 후보에 대한 **predicate 평가 횟수**다. 벽시계 stall cycle이나
총 simulation cycle과 직접 더하거나 빼면 안 된다. 기존
`command_predicate_reject_cycles`는 CommandQueue가 센 최초 후보 거절 횟수라 집계 범위도 다르다.

## 4. 보수적 WRITE 직렬화 결과

| 항목 | 값 |
|---|---:|
| 출력 정확도 | 18,816개 PASS |
| 총 cycle | 239,847 |
| CommandQueue 최초 후보 거절 | 1,304,360 |
| Epoch mismatch 평가 | 10,689,866 |
| Barrier outstanding 평가 | 977,410 |
| WRITE bus busy 평가 | 22,401,726 |
| Rank command reject 평가 | 0 |

WRITE bus busy가 가장 많이 평가됐으므로 현재의 “WRITE가 하나라도 예약되어 있으면 새
WRITE 금지” 조건이 가장 먼저 검토할 병목임을 확인했다.

## 5. WRITE 구간 비중첩 완화 실험

예약 WRITE의 데이터 구간 `[countdown, countdown + BL/2)`와 새 WRITE의
`[WL, WL + BL/2)`가 겹치지 않을 때 연속 발행하도록 임시 수정했다.

결과는 정확도 검사 전 다음 Rank 상태 오류로 실패했다.

```text
[ERROR (src/Rank.cpp:192)]: == Error - ch 4 ra0 received a REF when not allowed
```

오류 직전 패킷은 `BANK_DOMAIN_GRF_TO_BANK` 태그의 NOP writeback이었다. 이 WRITE는
단순 메모리 데이터가 아니라 PIM mode와 명령 완료 순서에 영향을 준다. 따라서 물리적인
data-bus 구간만 겹치지 않는다고 연속 발행하면 command와 data completion 순서가 깨진다.
해당 완화는 폐기하고 보수적 직렬화로 복원했다.

## 6. 복원 검증

```bash
HIERARCHY_SOURCE_QUEUES=true bash experiment/run_hierarchy_shared_drain.sh
```

복원 후 마이크로 결과는 출력 12개 PASS, 1,483 cycles, overlap window 404 cycles다.
세 설정 파일의 `HIERARCHY_SOURCE_QUEUES`도 모두 `false`로 복원했다.

## 7. 다음 구현 판단

다음 최적화에는 WRITE를 주소만으로 분류해서는 안 된다. transaction에 다음 의미를
명시하는 completion class가 필요하다.

1. 일반 activation/weight/output data WRITE
2. PIM mode 전환 WRITE
3. CRF/GRF 제어 및 writeback WRITE
4. 이전 WRITE data completion을 기다려야 하는 barrier

일반 데이터 WRITE만 JEDEC data-bus timing으로 파이프라인하고, mode/control WRITE는
completion dependency를 유지해야 한다. 이 분류를 명령 생성 시 태그가 아닌 구조화된
메타데이터로 전달하는 것이 다음 코드 작업이다.
