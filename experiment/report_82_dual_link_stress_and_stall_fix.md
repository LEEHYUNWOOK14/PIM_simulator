# 82차 RTL 보고서: Dual-link stress 검증과 stall 안정성 수정

## 1. 목적

Dual-link가 짧은 예제에서 두 burst를 한 번 보내는 수준을 넘어 다음 조건을 만족하는지 검증한다.

- 포화 트래픽에서 지속적으로 64 B/cycle을 유지
- Random valid/ready에서도 데이터 손실 없이 진행
- 8개 source 중 starvation이 없음
- Downstream stall 동안 valid payload와 source ID가 변하지 않음

## 2. Stress test 구성

`rtl/tb/logic_die_dual_link_stress_tb.sv`는 두 구간을 실행한다.

| 구간 | 길이 | 입력 | 출력 ready | 검사 |
|---|---:|---|---|---|
| Saturation | 512 cycles | 8 source 항상 valid | 두 lane 항상 ready | 매 cycle 2 burst, source별 공정성 |
| Random | 2,000 cycles | LFSR 기반 valid 생성 | LFSR 기반 ready | 진행, starvation, payload 안정성 |

각 source는 ready handshake 전까지 valid와 data를 유지한다. Scoreboard는 output source ID로 원래 input payload를 찾아 매 cycle 비교한다.

## 3. 발견한 결함

초기 조합 arbiter는 downstream stall 중 pointer는 멈췄지만, 새로운 input valid가 들어오면 우선순위 검색 결과가 바뀔 수 있었다. 따라서 output valid가 유지되는 동안 payload가 바뀌는 valid/ready 계약 위반이 발생했다.

```text
FATAL: output changed while coupled-ready transaction was stalled
```

짧은 directed test에서는 stall 도중 새 source가 들어오지 않아 드러나지 않았고 random traffic에서 발견됐다.

## 4. 수정

Dual arbiter에 다음 hold state를 추가했다.

- `hold_q`: 현재 output이 stall 중인지 표시
- `hold_grant_q`: 선택된 input source 고정
- `hold_valid_q`, `hold_key_q`, `hold_data_q`, `hold_source_q`: 두 output payload 보존

Stall을 처음 관찰한 clock edge에서 선택과 payload를 register에 저장한다. 두 output이 모두 ready가 될 때까지 input ready를 내리지 않고 저장된 output을 유지한다. Handshake가 끝난 뒤에만 round-robin pointer를 이동한다.

## 5. 최종 결과

```text
LOGIC_DIE_DUAL_LINK_STRESS_TB PASS
saturation_bursts[1024]
saturation_bytes_per_cycle[64]
random_bursts[1052]
```

- 포화 구간: `1,024 bursts × 32 B / 512 cycles = 64 B/cycle`
- 각 source: 포화 구간에서 정확히 128 burst씩 서비스
- Random 구간: 1,052 burst가 handshake되어 진행 정지 없음
- 모든 source가 random 구간에서도 추가 서비스되어 starvation 없음
- Stall 중 output valid/data/source 안정성 PASS

전체 RTL 회귀도 통과했다.

```text
BANK_LOCAL_REDUCTION_BUFFER_TB PASS
LOGIC_DIE_DUAL_LINK_STRESS_TB PASS
HIERARCHICAL_REDUCTION_PATH_TB PASS
LOGIC_DIE_DUAL_LINK_ARBITER_TB PASS
LOGIC_DIE_LINK_ARBITER_TB PASS
```

## 6. C++ 모델 해석

C++의 `LOGIC_ACCUMULATOR_BW=64`는 이제 RTL 포화 최대폭과 일치한다. 하지만 random 구간처럼 valid source가 두 개 미만이거나 downstream이 막히면 실제 평균 bandwidth는 64 B/cycle보다 낮다. 따라서 C++의 고정 bandwidth 모델은 최대폭 모델이며, 최종 보정에는 MobileNetV4에서 추출한 valid/ready trace 기반 link utilization이 필요하다.

## 7. 다음 단계

1. C++에서 accumulator source-valid와 link-ready trace 또는 occupancy를 출력한다.
2. 실제 MobileNetV4 trace를 RTL stress test에 재생한다.
3. 측정된 sustained bandwidth를 C++ transfer cycle 모델과 비교한다.
4. FP16 vector adder에 1-cycle 이상 latency가 있을 때 hold/backpressure가 유지되는지 검증한다.
