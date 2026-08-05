# 실험 46: 독립 logic command frontend 1차 구현

## 1. 구현 내용

- `MemoryController`에 `logicControlCommandQueue`를 추가했다.
- Logic domain이면서 row bit 13이 설정된 PIM 예약주소 transaction만 제어 큐로 보낸다.
- 제어 큐는 `logicControlBankStates`를 사용하므로 물리 HBM의 열린 row를 변경하지 않는다.
- 일반 row의 logic weight/input/output은 기존 물리 큐와 `bankStates`를 사용한다.
- 두 큐는 공용 command bus 앞에서 한 cycle에 하나만 발행한다.
- 분리된 두 큐 사이의 source 순서를 보존하기 위해 `LOGIC_SEQ_n_` 순번을 추가했다.

## 2. 검증 명령

```bash
wsl scons -j4
wsl ./sim --gtest_filter=PIMKernelFixture.add

HIERARCHY_SOURCE_QUEUES=false \
bash experiment/run_hierarchy_shared_drain.sh

HIERARCHY_SOURCE_QUEUES=true \
bash experiment/run_hierarchy_shared_drain.sh
```

## 3. 현재 결과

| 검증 | 결과 |
|---|---|
| 빌드 | 통과 |
| Bank-PIM ADD | 1,048,576/1,048,576 통과 |
| Source queue OFF shared drain | 통과, 1,942 cycles |
| Source queue ON shared drain | 미완료, sequence 18에서 교착 |

Source queue OFF 결과:

```text
logic_outputs_checked[12]
bank_issues[2048]
logic_issues[288]
pending_after_drain[0]
```

Source queue ON stall 요약:

```text
logic_expected[18]
logic_ctrl ... type[1] row[10239] tag[LOGIC_DOMAIN_LOGIC_SEQ_18_] state[1]
physical queue head ... tag[LOGIC_DOMAIN_MAC_LOGIC_SEQ_30_]
```

`state[1]`은 해당 가상 bank가 RowActive라는 뜻이다. 현재 순번 18의 예약주소
WRITE가 발행되지 않아 이후 MAC sequence 30까지 진행하지 못한다. stale readback은
독립 상태로 차단됐지만, 가상 bank의 open-row/precharge 전이가 아직 완성되지 않았다.

## 4. 다음 수정

1. 제어 큐 stall 출력에서 `openRowAddress`, `nextWrite`, `nextPrecharge`를 확인한다.
2. 현재 sequence만 고려한 precharge가 실제로 발행되는지 추적한다.
3. 예약주소 제어 frontend가 물리 DRAM처럼 ACT/PRE를 요구해야 하는지 모델을 재검토한다.
4. 필요하면 logic 제어 register file을 row-buffer와 분리하고 command-bus latency만 적용한다.
5. source queue ON shared-drain 정확도와 `logic_issues>0`을 통과시킨다.

## 5. 판정

이 보고서의 sequence 18 교착은 이후 직접 control frontend로 해결됐다. 최신 소형 검증
결과와 중첩 성능은 `experiment/report_47_direct_control_frontend_and_overlap.md`를 따른다.
전체 실제 형상 UIB 회귀는 아직 완료되지 않았으므로 전체 구현 완료로 판정하지 않는다.
