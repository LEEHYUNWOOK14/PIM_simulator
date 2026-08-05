# 43차 실험 보고서: 계층별 issue window 진단

## 1. 실험 목적

Bank depthwise stage와 logic pointwise row가 같은 drain에 들어갔다는 사실만으로 실제 병렬 실행을 주장할 수 없다. 두 source의 실제 명령 issue cycle을 기록해 시간 구간이 겹치는지 직접 확인한다.

## 2. 계측 방법

모든 channel/rank가 공유하는 `LogicDieScheduler`에 hierarchy activity tracker를 추가했다.

- Bank compute command issue 수와 cycle 집합
- Logic compute command issue 수와 cycle 집합
- Source별 first/last issue
- 동일 cycle에 두 source가 issue된 횟수
- First/last issue window의 교집합 길이

PIM block 8개 중 block 0에서만 기록해 같은 packet의 block별 중복을 제거했다. NOP/JUMP/EXIT는 제외한다.

## 3. 재현 명령

```bash
bash experiment/run_hierarchy_shared_drain.sh
```

결과 CSV:

```text
experiment/results/hierarchy_shared_drain.csv
```

## 4. 측정 결과

| 항목 | 값 |
|---|---:|
| Shared drain cycle | 1,942 |
| Bank command issues | 2,048 |
| Logic command issues | 288 |
| Bank first/last issue | 1,748 / 2,344 |
| Logic first/last issue | 2,758 / 3,080 |
| 동일 cycle issue 교집합 | 0 |
| Issue window 교집합 | 0 cycle |
| Bank 종료→logic 시작 공백 | 414 cycle |
| Logic 출력 정확도 | 12/12 |

## 5. 해석

두 작업은 동시에 pending 상태였고 한 번의 `runPIM()`에서 모두 완료됐지만, issue 순서는 완전히 직렬이었다.

```text
bank issue:  [1748 ---------------- 2344]
gap:                                  [414 cycles]
logic issue:                                      [2758 -------- 3080]
```

따라서 42차의 `shared drain`은 co-pending 기능 검증이며 실제 overlap 성능 검증이 아니다. 현재 command queue는 enqueue 순서와 barrier를 보존해 bank command 묶음을 모두 발행한 뒤 logic command 묶음을 시작한다.

## 6. 구조적 결론

Logic PCU와 bank PCU의 연산 자원이 독립이어도 command 발행 경로가 하나이면 병렬성이 나타나지 않는다. 설계한 계층형 구조에는 최소한 다음이 필요하다.

1. Bank command queue
2. Logic command queue
3. 두 queue의 독립 ready 판단
4. Shared DRAM command/address bus에서의 arbitration
5. Barrier scope를 global이 아니라 source 또는 dependency token 단위로 구분
6. Bank/logic PC와 CRF context 독립성

## 7. 다음 통과 조건

독립 queue 통합 후 같은 테스트에서 다음을 만족해야 한다.

- Logic 출력 12개 정확도 유지
- Bank stage 완료 유지
- `overlapping_window_cycles > 0`
- 가능하면 `overlapping_issue_cycles > 0`
- Sequential 대조군보다 공동 실행 cycle 감소
- 전체 UIB 정확도와 기존 blocking 회귀 유지

## 8. 연구적 의미

이번 결과는 PCU를 logic die에 추가하는 것만으로 메모리 I/O나 latency가 자동 감소하지 않는다는 근거다. 계층별 command queue와 barrier scope가 실제 architecture novelty의 일부이며, RTL에서도 독립 issue 경로를 명시해야 한다.
