# 40차 실험 보고서: Pointwise session CRF residency

## 1. 실험 목적

같은 pointwise layer의 여러 spatial position과 행 범위가 동일한 GEMV 명령을 사용할 때, logic-die PCU의 CRF를 channel group마다 한 번만 프로그램한다. Shared weight뿐 아니라 명령 상태도 세션 동안 유지해 반복 command traffic을 줄인다.

## 2. 구현 방식

`PointwiseSpatialSession`은 `logicCrfResidentGroups` bitmap을 보관한다.

1. Position을 담당할 channel group을 계산한다.
2. 해당 group의 bit가 0이면 CRF를 프로그램하고 bit를 1로 바꾼다.
3. Bit가 1이면 `PROGRAM_CRF`만 생략한다.
4. GEMV mode reset, 입력 전송, MAC, 결과 write/read는 그대로 실행한다.

일반 blocking pointwise API는 기존처럼 매 position에서 CRF를 프로그램한다. 이번 최적화는 명시적 session 경로에만 적용했다.

## 3. 아키텍처 전제

설계하는 계층형 구조에서는 bank-side PCU와 logic-die PCU가 서로 다른 CRF 상태를 가진다. 따라서 중간에 bank-side depthwise가 실행되어도 logic-die pointwise CRF는 보존된다고 모델링한다. Logic-die의 다른 layer가 같은 CRF를 사용하려면 별도의 generation 또는 context 전환이 필요하다.

## 4. 재현 명령

```bash
bash experiment/run_nonblocking_pointwise_test.sh
```

결과는 다음 파일에 저장된다.

```text
experiment/results/nonblocking_pointwise_test.csv
```

## 5. 출력 예시

```text
session_crf_program_calls  session_reused_crf_calls  session_outputs_checked  session_total_cycle
8                          0                         36                       2658
```

| 항목 | 값 | 해석 |
|---|---:|---|
| 전체 CRF program calls | 8 | 첫 범위에서 사용한 8개 channel group을 각각 1회 프로그램 |
| 재사용 범위 CRF calls | 0 | 두 번째 범위는 기존 group CRF를 그대로 사용 |
| 검증 출력 | 36 | 전체 CPU reference와 일치 |
| 총 cycle | 2,658 | Weight와 CRF residency를 모두 적용한 순차 행 실행 |

## 6. 단계별 비교

| 단계 | 총 cycle | 직전 단계 대비 | 최초 대비 |
|---|---:|---:|---:|
| 38차: 행마다 weight/CRF 준비 | 2,770 | 기준 | 기준 |
| 39차: weight residency | 2,672 | -98 | -98 |
| 40차: weight+CRF residency | 2,658 | -14 | -112 (-4.04%) |

CRF 절감이 14 cycle인 것은 작은 형상과 transaction overlap의 결과다. CRF call 수 8→0이 기능 검증의 직접 지표이며, 더 큰 MobileNetV4 행 타일에서 별도 cycle sweep이 필요하다.

## 7. 회귀 결과

- Row session: 36개 출력 통과
- 재사용 범위 weight fill: 0 bursts
- 재사용 범위 CRF program: 0 calls
- Expand→bank depthwise halo: 5,376개 출력 통과
- 전체 MobileNetV4 UIB: 18,816개 출력 통과
- 기존 전체 UIB cycle: 214,228 유지

## 8. RTL 인터페이스 요구사항

| 상태 | 최소 RTL 표현 |
|---|---|
| Weight residency | `weight_layer_id`, `weight_valid` |
| CRF residency | group별 `crf_context_id`, `crf_valid` |
| Context 교체 | generation 증가 또는 valid clear |
| 행 작업 | `row_start`, `row_count`, completion token |
| 계층 독립성 | bank-side와 logic-die CRF state 분리 |

## 9. 다음 구현

이제 준비 상태 재사용은 확보했지만 행 범위는 여전히 순차 실행된다. 다음 단계는 최소 3행 activation line buffer와 row completion token을 추가하고, logic-die expand의 다음 행과 bank-side depthwise의 준비된 행을 겹쳐 실행하는 실제 wavefront scheduler다.
