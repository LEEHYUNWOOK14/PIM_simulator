# Project barrier 분해 및 context residency 실험

## 1. 의존성 재진단

Project 결과는 WRITE drain이 아니었다. `executePointwiseBatchAndRead()`가 각 position의
GRF 결과를 bank에 writeback한 뒤 `readResult()` READ로 회수하고, 이후 ADD 입력으로
다시 preload한다. 따라서 Project output WRITE를 단순 조기 release하는 계획은 폐기했다.

## 2. Completion class별 계측

64채널 MemoryController에서 WRITE DATA 완료와 BAR 완료를 completion class별로 세고,
Project 시작/종료 스냅샷 차이를 기록했다. 계측 전후 총 cycle은 모두 247,342로 같아
정책에 영향을 주지 않았다.

| Project 196 positions | BAR WRITE 완료 수 | Position당 |
|---|---:|---:|
| `ORDERED` | 784 | 4 |
| `PIM_MODE` | 1,568 | 8 |
| `PIM_CONTROL` | 392 | 2 |
| `PIM_WRITEBACK` | 392 | 2 |

Project stage는 117,559 cycles다. Mode barrier가 가장 많이 반복된다.

## 3. Context residency 시도

Source queue ON spatial session에서 group별 HAB context를 유지하고, position마다 수행하던
SB/HAB 진입·종료와 park 동작을 생략하는 실험을 했다. HAB 상태에서도 `output` READ가
bank 결과를 회수하도록 임시 우회 경로를 추가했다.

```bash
bash experiment/run_source_queue_stall_breakdown.sh
```

실험은 300초가 지나도 반복 MAC 구간을 끝내지 못했다. 기존 기준선은 약 169초에
완료되므로 성능 목표에 명백히 역행했다. 프로세스를 종료하고 변경을 모두 제거했다.

## 4. 실패 원인

현재 GRF writeback은 position마다 같은 물리 결과 위치를 재사용한다. 별도 output buffer와
retirement 추적 없이 context만 유지하면 이전 결과 READ, 다음 position compute, mode
명령이 긴 queue/epoch 의존성으로 묶인다. Bank READ를 HAB에서 강제로 수행하는 것도
실제 logic-die 출력 경로를 모델링하지 못한다.

## 5. 복원 검증

- 빌드 PASS
- Source queue ON 마이크로 출력 12개 PASS
- Cycle 1,425
- Overlap window 57
- 세 설정 파일의 `HIERARCHY_SOURCE_QUEUES=false` 복원
- 잔류 실험 프로세스 없음

## 6. 설계 판단

Mode barrier 제거 전에 logic-die output buffer와 retirement queue가 필요하다. 필요한
구조와 신호는 `design/logic_die_output_retirement_contract.md`에 정리했다. 다음 구현은
2-entry output buffer와 tile ID scoreboard를 먼저 시뮬레이터에 추가하는 것이다.
