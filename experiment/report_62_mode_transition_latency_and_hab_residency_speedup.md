# 62차 실험 보고서: Mode transition latency와 HAB residency 성능 효과

## 1. 실험 목적

61차 실험에서는 HAB 전환 횟수가 절반으로 감소했지만 64개 spatial group이 여러 채널에서 병렬 실행되어 총 cycle 차이가 보이지 않았다. 이번 실험은 mode 전환 state-machine latency를 모델링하고, 한 채널에서 두 wave를 직렬 실행하여 HAB residency의 구조 효과를 분리해 측정한다.

## 2. Timing 모델

새 설정은 다음과 같다.

```ini
LOGIC_MODE_TRANSITION_LATENCY=0
```

동작 규칙:

1. Rank의 mode가 실제로 변경된 cycle을 기록한다.
2. `current_cycle + LOGIC_MODE_TRANSITION_LATENCY`를 ready cycle로 설정한다.
3. ready cycle 전에는 같은 실행 문맥의 후속 command를 받지 않는다.
4. source queue ON에서는 bank와 logic ready cycle을 분리한다.
5. 중간 mode packet이나 동일 mode 재설정에는 latency를 다시 부과하지 않는다.
6. 기본값 0은 기존 시뮬레이터 timing을 유지한다.

RTL 대응 예시는 다음과 같다.

```systemverilog
parameter int MODE_TRANSITION_LATENCY = 0;
mode_ready = (mode_transition_countdown == 0);
command_ready = source_ready && mode_ready;
```

## 3. 마이크로벤치마크 구성

| 항목 | 값 |
|---|---:|
| 활성 HBM 채널 | 1 |
| Spatial group | 1 |
| Position / batch wave | 2 / 2 |
| 입력/출력 logical channel | 3 / 3 |
| 검증 출력 | 6개 |
| Source queue | ON |
| Output buffer | 2 entries |
| Output drain latency/BW | 4 cycles / 8 bursts per cycle |

한 group이 두 position을 연속 처리한다. Residency OFF에서는 HAB 진입·이탈이 각각 2회이고, ON에서는 각각 1회다.

## 4. 재현 명령

WSL 프로젝트 루트에서 실행한다.

```bash
bash experiment/run_mode_transition_latency_sweep.sh
```

다른 가정값은 다음처럼 지정한다.

```bash
LATENCIES="0 4 8 16 32 64" bash experiment/run_mode_transition_latency_sweep.sh
```

실험 종료 후 설정 파일은 원래 값으로 복구된다.

## 5. 출력 예시

```text
MODE_TRANSITION_LATENCY_RESULT channels[1] positions[2]
outputs_checked[6] spatial_groups[1] batch_waves[2]
hab_entries[1] hab_exits[1] mode_latency[64]
hab_residency[1] source_queues[1] total_cycle[1638]
[  PASSED  ] 1 test.
```

- `hab_entries[1]`, `hab_exits[1]`: 두 wave 사이에서 HAB 상태가 유지됐다.
- `mode_latency[64]`: mode 변경 뒤 64 cycle 동안 후속 명령 ready가 내려간다.
- `total_cycle[1638]`: 준비, compute, mode 전환, output drain을 포함한 종료 cycle이다.
- `[ PASSED ]`: 6개 출력이 모두 기준값과 같고 교착 없이 종료됐다.

## 6. 결과

| Mode latency | Residency OFF | Residency ON | 절감 cycle | 개선율 |
|---:|---:|---:|---:|---:|
| 0 | 1,401 | 1,294 | 107 | 7.64% |
| 32 | 1,585 | 1,446 | 139 | 8.77% |
| 64 | 1,841 | 1,638 | 203 | 11.03% |

모든 조합에서 출력 6개가 정확성 검증을 통과했다. 원본 결과는 `experiment/results/mode_transition_latency_sweep.csv`에 저장된다.

## 7. 해석

1. Mode latency가 0이어도 residency는 mode command와 barrier를 줄여 107 cycle을 절감했다.
2. Mode latency가 커질수록 절감량은 107에서 203 cycle로 증가했다.
3. 64-group 실험에서 차이가 없었던 이유는 채널별 전환이 병렬로 겹쳤기 때문이다.
4. 실제 MobileNetV4 효과는 group별 wave 수, 채널 동시성, output backpressure와 barrier 위치에 따라 결정된다.

## 8. 연구자가 결정해야 하는 값

`LOGIC_MODE_TRANSITION_LATENCY`는 simulator가 자동으로 확정할 수 있는 물리 상수가 아니다. 다음 근거 중 하나로 결정해야 한다.

- Verilog mode-control FSM의 request부터 `mode_ready`까지의 RTL cycle
- 합성 후 목표 주파수에서 필요한 pipeline stage 수
- 구현하려는 HBM-PIM command protocol의 mode register timing
- 설계 가정값을 쓸 경우 최소/중간/보수적 값의 sensitivity sweep

현재 32와 64는 구조 민감도를 확인하기 위한 실험값이며 최종 하드웨어 수치가 아니다.

## 9. 결론

Logic-die output retirement와 HAB residency가 기능적으로 안전할 뿐 아니라, mode 전환 비용이 직렬 critical path에 있을 때 실제 cycle을 줄인다는 것까지 확인했다. 다음 단계는 full MobileNetV4 UIB에서 group별 wave 수와 mode 전환 병렬성을 계측하고 workload 전체 이득을 평가하는 것이다.
