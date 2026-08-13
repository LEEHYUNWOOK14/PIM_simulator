# Logic-die PCU 시스템 목표 재분류

## 결론

프로젝트의 성공 조건은 PCU 면적 또는 특정 공정 주파수를 최소화하는 것이 아니다. 여러 bank에 걸친 normalization을 logic die에서 완결하여 activation·중간 통계·최종 결과가 외부 memory I/O를 왕복하지 않게 만드는 것이 1차 목표다. PCU 비용은 이 외부 I/O 제거를 달성한 후보들 사이에서 필요한 최소 구성을 고르는 2차 기준이다.

## 기존 결과의 재분류

| 기존 산출물 | 새 목표에서의 처리 |
|---|---|
| 실제 action-head BF16 trace 6종 | 그대로 사용. workload/정확도/traffic의 기준 입력이다. |
| PyTorch 및 mixed-precision golden | 그대로 사용. 수치 contract를 변경하지 않는다. |
| 4/8/16-lane reducer·scalar·apply RTL | 그대로 사용. PCU top 내부 arithmetic core다. |
| multi-row/context overlap | 그대로 사용. 여러 row가 scalar latency를 숨기는 핵심 구조다. |
| 기존 component STA·공정 면적 | 참고 자료로만 유지. 최종 gate에서 제외한다. |
| `PIM logical traffic = 130,969,088 B` | 폐기하지 않지만 단일 합계로 판정하지 않는다. 경계별 byte로 다시 분해한다. |
| `35.88 MHz`, `111.1 MHz 필요`, production NO-GO | 특정 공정 성능 판정이므로 새 목표의 필수 gate에서 제외한다. |
| 기존 8-lane 후보 | 재검증 대상. 자동 확정하지 않고 새 PCU top RTL 결과로 다시 판정한다. |

## 새로운 판정 순서

1. normalization 입력과 출력이 memory bank에 resident한 상태에서 PCU가 전체 연산을 완결해야 한다.
2. 외부 memory I/O에는 invocation descriptor와 cold parameter load만 남겨야 한다.
3. bank-array 접근, bank↔logic-die traffic, 외부 traffic을 서로 합치지 않고 각각 공개해야 한다.
4. 4/8/16-lane 모두 같은 정확도와 같은 외부 I/O 제거를 제공해야 한다.
5. 그 조건을 통과한 후보 중 실제 RTL cycle 감소가 추가 arithmetic/storage 비용을 정당화하는 최소 knee를 고른다.

## 범위와 한계

- 공정, PVT, 배치배선, mm², sign-off 주파수는 이번 의사결정 범위 밖이다.
- hardware cost는 FP32 adder/multiplier/rsqrt 수와 state bit를 이용한 공정 독립 상대 비용으로 비교한다.
- trace는 `PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`이며 full GR00T inference capture는 아니다.
- 따라서 선정 구조는 현재 action-head workload에 대한 RTL freeze 후보이며, 전체 모델 일반화 주장은 하지 않는다.

