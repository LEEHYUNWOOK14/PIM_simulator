# 70차 실험 보고서: Direct staging Architecture A/B와 Stage 병목

> **부분 정정(71차):** Direct staging OFF/ON의 정확도, cycle, fill ACT/completion 결과는 유효하다. 다만 stage별 bank-state-only 및 bank-all 수치는 speculative PRECHARGE 계측 오염으로 무효이며, 보정된 stage 병목은 71차 보고서를 따른다.

## 1. 목적

69차 판단에 따라 logic-die weight staging command를 일반 DRAM bank-state에서 분리하고, 기능 정확성과 Full MobileNetV4 UIB 성능 효과를 검증한다. 동시에 stage별 blocker를 분해해 다음 변경 대상을 찾는다.

## 2. 구현한 Architecture 옵션

```ini
LOGIC_DIRECT_STAGING_COMMAND_PATH=false
```

ON일 때 `LOGIC_WEIGHT_FILL`은 다음처럼 동작한다.

- 일반 DRAM command queue 대신 logic-control frontend 사용
- ACT/PRE/open-row 조건 우회
- 기존 write data bus 예약 유지
- Shared weight buffer write-port latency와 completion 유지
- Fill burst와 modeled write 수 유지

기본값은 기존 동작 보존을 위해 false다.

## 3. 재현 명령

```bash
bash experiment/run_direct_staging_ab.sh
```

결과 파일:

- `experiment/results/direct_staging_ab.csv`
- `experiment/results/direct_staging_stage_breakdown.csv`

## 4. 기능 검증

3-channel microbenchmark:

| 설정 | Total cycle | 결과 |
|---|---:|---:|
| Direct staging OFF | 1,706 | PASS |
| Direct staging ON | 1,655 | PASS |

ON 조건에서 fill completion은 0보다 크고 fill ACT/PRE는 0이라는 assertion도 통과했다.

## 5. Full UIB A/B

| 지표 | OFF | ON | 차이 |
|---|---:|---:|---:|
| 출력 검증 | 18,816 PASS | 18,816 PASS | 동일 |
| Total cycle | 235,182 | 235,130 | -52 (-0.022%) |
| Modeled writes | 220,342 | 220,342 | 동일 |
| Fill completed writes | 3,584 | 3,584 | 동일 |
| Fill ACT | 1,120 | 0 | -1,120 |
| Fill PRE | 0 | 0 | 동일 |
| Bank-state only | 175,229 | 175,205 | -24 |

데이터 이동이나 fill completion을 생략하지 않고 ACT 1,120회를 제거했으므로 architecture path는 의도대로 동작했다. 그러나 전체 개선은 52 cycles뿐이다.

## 6. Stage별 결과

### Direct staging OFF

| Stage | Stage cycles | Bank-state only | Bank all-active | Hierarchy all-active |
|---|---:|---:|---:|---:|
| Expand | 88,345 | 79,748 | 84,078 | 3,849 |
| Depthwise | 38,884 | 665 | 32,206 | 30,173 |
| Project | 103,431 | 94,758 | 99,579 | 3,800 |
| Add | 3,715 | 38 | 3,217 | 3,106 |
| ReLU/readback | 807 | 20 | 565 | 431 |

### Direct staging ON

| Stage | Stage cycles | Bank-state only | Bank all-active | Hierarchy all-active |
|---|---:|---:|---:|---:|
| Expand | 88,297 | 79,710 | 84,788 | 4,637 |
| Depthwise | 38,932 | 665 | 32,250 | 30,218 |
| Project | 103,379 | 94,772 | 100,013 | 4,239 |
| Add | 3,715 | 38 | 3,217 | 3,106 |
| ReLU/readback | 807 | 20 | 565 | 431 |

## 7. 해석

1. 전체 bank-state-only의 약 99.59%가 expand와 project pointwise 단계에서 발생한다.
2. Depthwise는 bank-state all-active가 크지만 대부분 hierarchy predicate와 겹치며 bank-state-only는 665 cycles에 불과하다.
3. Add와 ReLU의 독립 bank-state 병목은 매우 작다.
4. Weight fill ACT는 pointwise 병목의 일부일 뿐이다.
5. 다음 대상은 logic pointwise 내부의 mode/park/input/MAC command 중 일반 bank-state를 기다리는 command다.

## 8. 연구적 의미

Logic-die shared weight buffer를 두는 것만으로는 pointwise command stream이 DRAM bank-state에 묶이는 문제를 해결하지 못한다. 계층형 PCU의 성능을 얻으려면 데이터 저장 위치뿐 아니라 다음 제어 경로도 분리해야 할 가능성이 크다.

- Mode 진입과 이탈 command
- Input GRF upload
- MAC trigger stream
- Output retirement
- Spatial wave barrier

## 9. 다음 구현

Bank-state reject packet을 operation tag별로 분류한다.

```text
WEIGHT_FILL
PARK
MODE_CONTROL
WRIO_TO_GRF
MAC
OUTPUT
OTHER
```

Expand/project stage별 top tag와 blocked cycle을 측정한 뒤, 가장 큰 command class를 logic-control frontend로 옮기는 두 번째 architecture 실험을 수행한다.

## 10. 결론

Direct weight staging command path는 기능적으로 올바르지만 Full UIB 개선은 52 cycles에 그쳤다. 실제 독립 bank-state 병목은 logic pointwise expand/project command stream에 있으며, 다음 단계는 command tag별 원인 확정이다.
