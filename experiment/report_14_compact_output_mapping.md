# 14차 기술 구현 보고서: Logic Compact Output Mapping

## 1. 실험 목적

기존 pointwise GEMV는 논리 output이 96 또는 192여도 64개 HBM channel 전체에 걸친 4096-output 물리 tile을 사용한다. logic die에서 필요한 channel만 활성화하는 compact mapping을 실제 transaction 경로에 구현하고 다음을 확인한다.

- 수치 정확도가 유지되는가?
- 물리 output과 memory transaction이 감소하는가?
- simulation cycle이 감소하는가?

## 2. 새 설정 변수

```ini
LOGIC_COMPACT_OUTPUT=false
```

- `false`: 기존 64-channel, 4096-output mapping
- `true`: logic-die pointwise에만 논리 output을 수용하는 최소 channel 수 사용
- bank-only baseline은 항상 기존 mapping 유지

한 channel은 `8 PIM blocks × 8 GRF_B = 64 outputs`를 담당한다.

```text
192 outputs → 3 active channels → physical output 192
96 outputs  → 2 active channels → physical output 128
```

## 3. 구현 방식

`PIMKernel::executePointwiseBatchAndRead()`가 compact 조건에서 다음을 수행한다.

1. 논리 output에 필요한 active channel 수를 계산한다.
2. 기존 zero-padded weight에서 compact output 범위만 가진 실행용 view를 만든다.
3. preload, MAC, writeback, readback loop를 active channel subset에만 실행한다.
4. 논리 출력값을 모두 복원한다.
5. 정상 종료와 예외 발생 모두에서 원래 64-channel 상태를 복원한다.

마지막 pointwise의 `active_channels`, `physical_output_dim`과 전체 memory-controller read/write 수를 출력하도록 통계를 추가했다.

## 4. Pointwise Ablation 실행

```bash
bash experiment/run_compact_mapping_ablation.sh
```

결과 CSV:

```text
experiment/results/compact_mapping_pointwise.csv
```

결과:

| 조건 | Active channels | Physical output | Reads | Writes | Cycle |
|---|---:|---:|---:|---:|---:|
| bank fixed | 64 | 4096 | 842,496 | 259,008 | 120,164 |
| hybrid fixed/current | 64 | 4096 | 842,496 | 259,008 | 150,998 |
| hybrid compact/current | 3 | 192 | 75,360 | 12,141 | 150,998 |
| hybrid compact/ideal | 3 | 192 | 75,360 | 12,141 | 120,164 |

compact pointwise의 변화:

- read 약 91.1% 감소
- write 약 95.3% 감소
- physical output 4096→192
- active channel 64→3
- cycle 변화 없음

37,632개 pointwise 출력은 모든 조건에서 CPU 기대값과 일치했다.

## 5. 실제 UIB Ablation

Fixed hybrid 실행:

```bash
bash experiment/run_fixed_hybrid_actual_uib.sh
```

Compact hybrid 실행:

```bash
bash experiment/run_compact_actual_uib.sh
```

결과:

| 조건 | 마지막 project mapping | Reads | Writes | Cycle | 정확도 |
|---|---|---:|---:|---:|---|
| fixed hybrid | 64 channels, 4096 outputs | 2,562,176 | 845,376 | 436,861 | 18,816/18,816 |
| compact hybrid | 2 channels, 128 outputs | 237,600 | 218,635 | 436,861 | 18,816/18,816 |

전체 UIB transaction 감소율:

- read 90.727% 감소
- write 74.138% 감소
- 계층 전송량은 동일한 225,792 B
- simulation cycle은 동일한 436,861

## 6. Cycle이 줄지 않는 이유

현재 64개 HBM channel은 서로 병렬로 update된다. fixed mapping이 64개 channel에서 동시에 수행되든 compact mapping이 3개 channel에서 수행되든, 가장 느린 활성 channel의 command sequence 길이는 같다.

compact mapping은 다음 값을 줄인다.

- 활성 channel 수
- weight preload 수
- 전체 read/write transaction 수
- padded MAC 수

하지만 한 spatial position의 critical-path command 수는 줄이지 않는다. 따라서 현재 timing 모델에서는 traffic과 예상 에너지는 크게 감소하지만 latency는 그대로다.

## 7. 연구적 의미

compact mapping 단독 결과를 speed-up으로 주장하면 안 된다. 대신 다음 두 가지 근거로 사용할 수 있다.

1. logic-die mapping이 불필요한 memory activity를 74~91% 줄일 수 있다는 traffic/energy 근거
2. 비활성화된 channel을 다른 spatial position에 재할당할 수 있는 병렬화 여유

192-output expand는 3 channel만 사용하므로 64 channel에서 최대 `floor(64/3)=21`개 spatial group을 동시에 배치할 수 있다. 96-output project는 2 channel만 사용하므로 최대 32개 group이 가능하다. 실제 speed-up은 이 channel-group 병렬 실행을 command scheduler에 구현해야 발생한다.

## 8. 다음 구현

다음 단계는 spatial-group compact mapping이다.

```text
기존 batch 실행:
position 0 → 전체 channel command
position 1 → 전체 channel command
...

제안 실행:
position 0 → channel group 0
position 1 → channel group 1
...
여러 position을 같은 command wave에서 병렬 실행
```

구현 후 비교할 항목:

- group당 channel 수
- 동시에 처리하는 spatial position 수
- batch wave 수
- 실제 cycle speed-up
- read/write transaction
- logic service 및 hierarchy transfer

이 spatial parallel mapping이 compact traffic 감소를 실제 latency 감소로 바꾸는 핵심 후속 구조다.

## 9. 전체 회귀 확인

compact mapping 구현 후 기본 설정(`LOGIC_COMPACT_OUTPUT=false`)에서 전체 테스트를 다시 실행했다.

```bash
./sim
```

```text
[==========] 27 tests from 4 test suites ran.
[  PASSED  ] 26 tests.
[  FAILED  ] PIMBenchFixture.add
```

실패한 ADD benchmark의 계산 결과가 틀린 것은 아니다. non-PIM 6,651 cycle, PIM 3,349 cycle로 speed-up은 `1.98597x`였으며, 테스트가 요구하는 `2.0x 초과` 조건에 약 0.7% 미달해 실패로 표시됐다. GEMV, MUL, ReLU benchmark와 모든 정확도 테스트, MobileNetV4 실제 UIB 테스트는 통과했다. 따라서 compact 구현의 기능 회귀는 발견되지 않았지만 ADD 성능 임계값 실패는 별도의 기준선 이슈로 계속 기록한다.
