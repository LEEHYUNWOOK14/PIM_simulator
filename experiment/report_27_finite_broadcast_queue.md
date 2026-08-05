# 27차 실험 보고서: Finite Broadcast Queue와 Backpressure

## 1. 목적

26차에서 측정한 peak open mask 78을 실제 설정 변수로 연결하고, broadcast mask queue가 부족할 때 발생하는 command issue stall을 전체 UIB timing에 반영한다.

## 2. 추가 설정

```ini
LOGIC_BROADCAST_QUEUE_DEPTH=0
```

- `0`: queue 용량 제한을 적용하지 않는다.
- `1 이상`: 동시에 조립할 수 있는 broadcast mask entry 수다.

현재 모델은 완성된 mask interval trace를 시작 cycle 순으로 재생한다. Queue가 가득 차면 가장 먼저 완성되는 entry가 빠질 때까지 이후 command issue를 정지시키고 stall cycle을 누적한다.

## 3. 재실행 명령

```bash
bash experiment/run_broadcast_queue_depth_sweep.sh
```

기본 sweep 범위는 `0 32 64 78 96 128`이다. 결과는 `experiment/results/broadcast_queue_depth_sweep.csv`에 저장된다.

## 4. 결과

| Depth | Full events | Queue stall | Total cycle | 무제한 대비 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 214,228 | 0 |
| 32 | 11 | 1,561 | 215,417 | +1,189 |
| 64 | 1 | 53 | 214,289 | +61 |
| **78** | **0** | **0** | **214,228** | **0** |
| 96 | 0 | 0 | 214,228 | 0 |
| **128** | **0** | **0** | **214,228** | **0** |

모든 조건에서 dispatch 1,616, coalesced 90,896, buffer miss 0과 최종 출력 정확도가 유지됐다.

## 5. Stall 적용 검증

추가 진단 결과:

| Depth | Stall 직전 cycle | 추정 stall | 실제 적용 cycle |
|---:|---:|---:|---:|
| 0 | 211,108 | 0 | 0 |
| 32 | 211,108 | 1,561 | 1,561 |
| 64 | 211,108 | 53 | 53 |

세 조건의 stall 직전 cycle이 같으므로 queue depth가 원래 command trace를 바꾸지는 않았다. 추정값과 실제 `mem_->update()` 적용 횟수도 일치한다.

## 6. Total cycle 증분 해석

Total cycle 증분은 stall과 정확히 같지 않다. UIB에는 logic-side project 이후 bank-side 후속 연산이 남아 있으며, queue stall이 DRAM command의 절대 phase를 이동시킨다. 그 결과 일부 timing gap이 흡수되거나 추가되어 depth 32는 1,561 stall 중 1,189 cycle이 최종 증가로 나타나고, depth 64는 53 stall이 61 cycle 증가로 나타났다.

이는 bank-side와 logic-die PIM을 함께 사용하는 계층형 구조에서 한 계층의 backpressure가 다음 계층의 DRAM timing에 영향을 준다는 의미다.

## 7. 설계 판단

- 64 entries는 평균적으로 충분해 보여도 project의 순간 peak에서 한 번 queue full이 발생한다.
- 78 entries는 현재 MobileNetV4 UIB trace의 정확한 경계다.
- RTL 구현 후보는 여유와 power-of-two 주소화를 고려해 128 entries가 적절하다.
- 최소 128-bit/entry 가정에서는 약 2 KiB이며 제어 필드 추가 시 더 커진다.

## 8. 모델 한계

현재 backpressure는 실행 후 확보한 mask interval을 이용한 trace-derived timing 모델이다. 기능 정확도와 총 stall 비용은 검증할 수 있지만, command queue full 신호가 DRAM command issue 순간에 직접 전달되는 완전한 online 모델은 아니다.

완전한 online 모델에는 workload scheduler가 ordinal별 expected channel mask 또는 각 stream의 EOS를 미리 제공해야 한다.

## 9. 다음 단계

1. `LogicCommandContext`에 expected channel mask 또는 EOS 정보를 추가한다.
2. Scheduler가 mask 완성을 online으로 판정하도록 한다.
3. Queue full을 `PIMRank`와 command issue 경로의 ready 신호로 전달한다.
4. Online 64/78/128 sweep이 이번 trace-derived 결과와 같은 경향인지 검증한다.

Expected-mask/EOS 기반 online completion 검증은 `report_28_online_expected_mask.md`에 기록했다. Online peak와 사후 trace peak가 expand/project 모두 일치했다.
