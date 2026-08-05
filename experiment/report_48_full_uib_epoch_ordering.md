# 전체 MobileNetV4 UIB epoch 순서 보장 실험 보고서

## 1. 실험 목적

독립적인 bank-side PIM 및 logic-die PIM 명령 프런트엔드를 활성화했을 때도 전체
MobileNetV4 UIB 연산의 정확성이 유지되는지 확인하고, 현재 구현의 성능 영향을 측정한다.

## 2. 구현 요약

- logic 제어 명령은 별도 `logicControlCommandQueue`에서 직접 발행한다.
- 실제 activation, weight, output 데이터는 기존 물리 HBM command queue를 사용한다.
- 두 프런트엔드는 command bus를 공유한다.
- 각 명령 흐름에 barrier epoch를 부여한다. BAR 경계에서는 이전 epoch의 outstanding
  transaction이 완료된 뒤 다음 epoch를 연다.
- 이 방식은 Rank mode 변경과 실제 데이터 접근 순서를 보존하면서, 같은 epoch 안의
  독립적인 transaction 재정렬을 허용한다.

## 3. 재현 명령

설정 파일의 `HIERARCHY_SOURCE_QUEUES`를 각각 `true`, `false`로 바꾼 뒤 다음 명령을
WSL 프로젝트 루트에서 실행한다.

```bash
./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd
```

실험 후에는 세 설정 파일의 값을 기본값인 `false`로 복원한다.

## 4. 결과

| 항목 | Source queue ON | Source queue OFF |
|---|---:|---:|
| 비교한 출력 | 18,816 | 18,816 |
| 총 cycle | 239,847 | 216,976 |
| Expand stage | 88,576 | 89,382 |
| Depthwise stage | 37,140 | 20,346 |
| Project stage | 110,086 | 104,703 |
| Add stage | 3,353 | 1,288 |
| ReLU stage | 692 | 1,257 |
| 정확도 결과 | PASS | PASS |

원시 결과는 `experiment/results/full_uib_source_queue_comparison.csv`에 저장했다.

## 5. 결과 해석

ON과 OFF 모두 18,816개 출력이 일치했으므로 독립 프런트엔드와 epoch 순서 보장은
기능적으로 동작한다. 소형 shared-drain 실험에서는 ON이 459 cycles, 즉 23.6% 짧아져
bank/logic 실행 중첩 자체도 확인했다.

그러나 전체 UIB에서 ON은 OFF보다 22,871 cycles 길며, 증가율은
`22,871 / 216,976 = 10.5%`이다. 따라서 현재 결과는 성능 향상이 아니라
**정확한 동시 실행 기반을 확보했지만 보수적인 동기화 비용이 남아 있음**을 뜻한다.
특히 Depthwise, Project, Add 단계의 증가가 전체 손실을 주도한다.

## 6. 다음 기술 작업

1. 공유 WRITE bus 예약 조건이 필요 이상으로 bank와 logic 발행을 막는지 측정한다.
2. epoch barrier 대기 cycle과 command predicate reject cycle을 단계별로 분리한다.
3. 개별 transaction이 아니라 MobileNetV4 tile 경계에서 bank/logic 작업을 겹친다.
4. 변경 후 정확도 18,816개 PASS를 유지하면서 총 cycle이 OFF 기준보다 감소하는지 확인한다.

첫 stall 분해와 WRITE 완화 시도 결과는
`experiment/report_49_source_queue_stall_breakdown.md`에 기록했다. 단순 데이터 구간
비중첩 완화는 PIM 제어 완료 순서를 깨뜨려 폐기했으며, 다음 단계는 WRITE completion
class를 명시적으로 모델링하는 것이다.
