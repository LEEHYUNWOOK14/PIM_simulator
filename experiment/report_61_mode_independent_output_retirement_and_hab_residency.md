# 61차 실험 보고서: Mode-independent output retirement와 HAB residency

## 1. 목표

Logic-die PIM이 HAB 상태에 머무르는 동안에도 결과를 안전하게 회수하고, 같은 spatial group의 다음 GEMV를 처리할 수 있는 최소 기능 경로를 구현한다.

## 2. 구현 내용

### 2.1 명시적 logic output drain

- Logic 결과 transaction에 `logicOutputDirect` 속성을 추가했다.
- 출력 버퍼를 사용하는 pointwise 결과는 `LOGIC_OUTPUT_DRAIN` 태그로 발행한다.
- transaction 속성을 `BusPacket`까지 전달한다.
- Rank는 `logicOutputDirect=true`인 READ를 SB/HAB/HAB_PIM mode와 무관하게 처리한다.
- `PIMRank::readLogicOutput()`이 주소의 bank와 column을 각각 logic PIM block과 GRF_B index로 해석하여 결과를 반환한다.
- 반환된 burst는 기존 READ completion 경로를 통해 `LogicDieOutputBuffer`에 기록되고 drain latency/bandwidth 모델을 거쳐 commit된다.

현재 단계에서는 command/data bus와 READ timing을 재사용한다. 따라서 기능 의미는 독립됐지만, 향후 RTL 대응에서는 별도 output drain port 또는 내부 NoC transaction으로 세분화할 수 있다.

### 2.2 spatial group별 HAB residency

- `LOGIC_HAB_RESIDENCY=false` 설정을 추가했다.
- 이 설정은 `LOGIC_OUTPUT_BUFFER_ENABLE=true`일 때만 적용된다.
- 각 spatial group의 첫 wave에서만 `SB -> HAB`로 진입한다.
- 중간 wave에서는 HAB 상태를 유지한다.
- `HAB <-> HAB_PIM` 전환은 유지하므로 기존 PC reset 의미는 보존한다.
- 각 group의 마지막 wave에서는 반드시 `HAB -> SB`로 복귀한다.

## 3. 재현 명령

WSL의 프로젝트 루트에서 다음을 실행한다.

```bash
bash experiment/run_hab_residency_ab.sh
```

스크립트는 네 가지 조합을 실행한다.

1. source queue OFF, HAB residency OFF
2. source queue OFF, HAB residency ON
3. source queue ON, HAB residency OFF
4. source queue ON, HAB residency ON

각 실행 전 설정 파일을 임시 수정하고 종료 시 원래 설정으로 복구한다.

## 4. 출력 예시

```text
HAB_RESIDENCY_WAVE_RESULT positions[128] outputs_checked[384]
spatial_groups[64] batch_waves[2]
hab_entries[64] hab_exits[64]
hab_residency[1] source_queues[1] total_cycle[18305]
[  PASSED  ] 1 test.
```

- `positions[128]`: 128개 spatial position을 실행했다.
- `outputs_checked[384]`: position당 3개, 총 384개 결과를 기준값과 비교했다.
- `spatial_groups[64]`: 64개 channel group을 사용했다.
- `batch_waves[2]`: 각 group이 두 position을 순차 처리했다.
- `hab_entries`, `hab_exits`: 실제로 발행한 HAB 진입·이탈 횟수다.
- `[ PASSED ]`: 모든 출력이 정확하며 교착 없이 종료됐다는 뜻이다.

## 5. A/B 결과

| Source queues | HAB residency | HAB 진입 | HAB 이탈 | Cycle | 정확성 |
|---:|---:|---:|---:|---:|---:|
| OFF | OFF | 128 | 128 | 18,332 | PASS |
| OFF | ON | 64 | 64 | 18,332 | PASS |
| ON | OFF | 128 | 128 | 18,305 | PASS |
| ON | ON | 64 | 64 | 18,305 | PASS |

원본 CSV는 `experiment/results/hab_residency_ab.csv`에 있다.

## 6. 해석

1. mode-independent drain이 이전 실패를 해결했다. HAB residency ON에서도 stale output, 정확성 실패, callback 교착이 발생하지 않았다.
2. residency는 실제로 동작했다. 두 wave에서 HAB 진입·이탈이 각각 128회에서 64회로 50% 감소했다.
3. cycle은 감소하지 않았다. 현재 mode 전환 transaction이 전체 critical path를 늘리지 않거나, 전환 자체의 logic-die 비용이 별도 latency로 모델링되지 않았기 때문이다.
4. 따라서 이 결과를 “HAB residency가 성능에 효과가 없다”로 해석하면 안 된다. 현재 증거는 “기능적으로 안전하지만 현 timing 모델에서는 절감된 전환 비용이 관측되지 않는다”이다.

## 7. 다음 구현 판단

다음 단계에서는 다음 두 수치를 분리해야 한다.

- mode 전환 명령이 command bus와 barrier에서 소비한 cycle
- RTL에서 가정할 mode transition 자체의 state-machine latency

그 후 `LOGIC_MODE_TRANSITION_LATENCY` 또는 동등한 구조 파라미터를 명시하고, residency OFF/ON의 전환 횟수와 총 cycle이 일관되게 연결되는지 검증해야 한다. 이 파라미터 값은 향후 Verilog state machine의 실제 latency 또는 합성 결과를 근거로 설정해야 한다.

## 8. 결론

Logic-die 결과 회수는 이제 SB 복귀에 의존하지 않는다. 또한 group별 HAB residency가 정확성을 유지하면서 실제 mode 전환 수를 절반으로 줄이는 것까지 검증했다. 남은 핵심은 이 구조적 절감을 timing 모델과 RTL 파라미터에 연결하는 일이다.
