# 72차 실험 보고서: 단계별 계층 정지 원인과 다음 아키텍처

## 1. 실험 목적

Speculative PRECHARGE 계측 오류를 제거한 상태에서 MobileNetV4 UIB의 각 단계가 왜 전 채널 정지하는지 분해한다. 특히 logic-die PCU가 맡아야 할 다음 기능을 실행시간이 아닌 실제 병목 근거로 선택한다.

## 2. 재현 명령

WSL에서 저장소 루트로 이동한 뒤 다음 명령을 실행한다.

```bash
cmake --build build -j$(nproc)
./build/sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
  > experiment/results/stage_predicate_breakdown.log 2>&1
grep -E 'STAGE_PREDICATE_RESULT|STAGE_BLOCKED_RESULT|PASSED|FAILED' \
  experiment/results/stage_predicate_breakdown.log
```

이 실험은 64채널, mode transition latency 32, HAB residency와 logic output buffer가 활성화된 계층형 UIB 검증 조건이다.

## 3. 정확도와 전체 실행 결과

```text
outputs_checked[18816]
total_cycle[235182]
[  PASSED  ] 1 test.
```

- `outputs_checked[18816]`: UIB의 최종 출력 18,816개를 기준값과 비교했다.
- `[ PASSED ]`: 모든 출력이 기준값과 일치했다.
- `total_cycle[235182]`: 계측을 포함한 전체 시뮬레이션 모델의 실행 사이클이다.

## 4. 단계별 결과

| 단계 | 단계 사이클 | 계층 조건 합집합 | Epoch mismatch | Barrier outstanding | Write bus busy |
|---|---:|---:|---:|---:|---:|
| Expand | 88,345 | 3,849 | 3,783 | 3,094 | 886 |
| Depthwise | 38,884 | 30,173 | 10,031 | 8,729 | 22,394 |
| Project | 103,431 | 3,800 | 3,705 | 2,278 | 241 |
| Add | 3,715 | 3,106 | 1,921 | 1,280 | 2,366 |
| ReLU/readback | 807 | 431 | 426 | 337 | 126 |

각 원인은 같은 사이클에 동시에 참일 수 있다. 따라서 `epoch + barrier + write bus`를 더하면 안 된다. 중복을 제거한 계층 조건 전체 정지시간은 `계층 조건 합집합` 열이다.

## 5. 핵심 분석

Depthwise 단계는 38,884사이클 중 30,173사이클, 즉 77.60%에서 모든 활성 채널이 하나 이상의 계층 조건에 막혔다. 그중 write bus busy가 22,394사이클(단계의 57.59%)로 가장 크다. Epoch mismatch는 10,031사이클(25.80%), outstanding barrier는 8,729사이클(22.45%)이다.

Expand와 project는 각각 88,345, 103,431사이클로 실행시간은 길지만 계층 조건에 의한 전 채널 정지는 4.36%, 3.67%에 불과하다. 따라서 pointwise의 다음 최적화보다 depthwise의 중간 writeback과 동기화 제거가 현재 계층형 PIM 목표에 더 직접적이다.

Add는 비율은 높지만 절대 실행시간이 3,715사이클로 작다. Add만 먼저 최적화하면 전체 UIB에서 얻을 수 있는 최대 이득이 제한된다.

## 6. 다음 아키텍처 실험

다음 구현 후보는 `Depthwise hierarchical accumulation`이다.

현재 depthwise lowering은 `9 MUL + 8 ADD`의 17개 bank-side 단계로 실행되며 각 단계 사이에서 중간 결과를 DRAM에 기록하고 다음 단계가 이를 다시 사용한다. 다음 실험에서는 다음 기능을 선택적으로 추가한다.

1. Bank-side PCU는 3x3 tap별 곱셈 또는 부분합을 생성한다.
2. 부분합을 일반 DRAM writeback 대신 logic-die PCU의 accumulation buffer로 전달한다.
3. Logic-die PCU는 같은 출력 원소의 9개 tap을 누산한다.
4. 최종 합만 DRAM 또는 다음 계층으로 기록한다.
5. 기존 경로와 새 경로를 설정값으로 선택해 정확도, cycle, write 수, transfer bytes를 A/B 비교한다.

이 기능은 최종 물리 구현을 확정하는 것이 아니다. 연구자가 reduction network 폭, accumulator 수, 정밀도와 배치 정책을 결정할 수 있도록 시뮬레이터에 실험 가능한 구조를 만드는 단계다.

## 7. 통과 조건

- 최종 출력 18,816개 전부 기준값과 일치
- 기존 bank-only depthwise 경로 보존
- depthwise 중간 write 수 감소
- depthwise `write_bus_all_active_cycles` 감소
- 전체 `total_cycle`이 악화될 경우 전송 대역폭 또는 accumulator 수에 따른 원인 분리

원시 결과는 `experiment/results/stage_predicate_breakdown.log`, 정리 데이터는 `experiment/results/stage_predicate_breakdown.csv`에 저장한다.
