# 13차 기술 구현 보고서: Logic PIM Crossover Sweep

## 1. 실험 질문

다음 질문을 실제 MobileNetV4 pointwise와 UIB에서 확인한다.

> logic PCU 수, logic latency, 내부 bandwidth, bank↔logic bandwidth만 조절하면 hybrid가 bank-only보다 빨라질 수 있는가?

## 2. 새 설정 변수

계층 간 전송 대역폭을 하드코딩하지 않고 설정 파일에서 변경하도록 다음 변수를 추가했다.

```ini
HIERARCHY_PIM_BW=64
```

- 단위: byte/cycle
- 의미: bank-side PCU와 logic-die PCU 사이의 중간 tensor 전송 대역폭
- `0`: 전송 byte는 계측하지만 추가 transfer cycle은 적용하지 않는 ideal unlimited 조건

`LOGIC_PIM_BW`는 logic PCU가 command 내부에서 처리하는 burst 경로이고, `HIERARCHY_PIM_BW`는 layer 배치가 바뀔 때 이동하는 전체 중간 tensor 경로다. 두 값을 구분해야 한다.

## 3. 실행 방법

실제 `14×14×96→192` pointwise crossover sweep:

```bash
bash experiment/run_logic_crossover_sweep.sh
```

결과 CSV:

```text
experiment/results/logic_crossover_pointwise.csv
```

ideal logic 조건에서 전체 UIB 확인:

```bash
bash experiment/run_ideal_logic_actual_uib.sh
```

두 스크립트 모두 세 설정 파일을 임시 변경하고 종료·실패 시 원래 파일을 복원한다.

## 4. Pointwise Sweep 결과

| 조건 | Units | Logic latency | Logic BW | Hierarchy BW | Cycle | Bank 대비 speed-up |
|---|---:|---:|---:|---:|---:|---:|
| bank baseline | 8 | 0 | 0 | 64 | 120,164 | 1.000000 |
| ideal unlimited | 8 | 0 | 0 | 0 | 120,164 | 1.000000 |
| compute one cycle | 8 | 1 | 0 | 0 | 120,126 | 1.000316 |
| balanced fast | 8 | 1 | 256 | 256 | 120,126 | 1.000316 |
| half units | 4 | 2 | 0 | 64 | 150,998 | 0.795799 |
| current model | 8 | 2 | 64 | 64 | 150,998 | 0.795799 |
| constrained | 2 | 4 | 32 | 32 | 335,180 | 0.358506 |

`compute one cycle`이 baseline보다 38 cycle 빠르지만 차이는 약 0.032%다. 추가 지연이 있는 모델이 구조적으로 더 빠른 것이 아니라 refresh와 queue 시점이 달라져 생긴 위상 차이 수준이다. 이를 logic PIM의 성능 향상으로 주장해서는 안 된다.

## 5. Full UIB 확인

| 조건 | Logic service | Hierarchy transfer cycle | 총 Cycle | 결과 |
|---|---|---:|---:|---|
| bank-only | 사용 안 함 | 0 | 346,600 | 정확 |
| ideal hybrid | latency 0, BW unlimited | 0 | 346,600 | 정확 |
| current hybrid | latency 2, BW 64 | 3,528 | 436,861 | 정확 |

ideal hybrid는 최종 18,816개 출력이 모두 정확하면서 bank-only와 정확히 같은 cycle을 기록했다. 현재 hybrid는 bank-only보다 약 26.0% 느리다.

## 6. 왜 자원 Sweep만으로 Speed-up이 없는가

현재 simulator에서 bank-side MAC은 DRAM command 처리 과정에서 실행되며 별도의 bank-PCU compute service cycle이 없다. 반면 logic-die MAC에는 다음 추가 시간이 붙는다.

```text
logic_service = max(
  ceil(NUM_PIM_BLOCKS / NUM_LOGIC_PIM_UNITS) × LOGIC_PIM_LATENCY,
  ceil(command_transfer_bytes / LOGIC_PIM_BW)
)
```

logic 자원을 무제한으로 만들면 이 추가 시간이 0이 되어 bank와 동률이 된다. 하지만 같은 GEMV command 수와 같은 `4096×128/256` 물리 tile을 사용하므로 bank보다 적은 일을 수행하지는 않는다.

따라서 현재 모델의 성능 관계는 본질적으로 다음과 같다.

```text
hybrid cycle ≈ bank command cycle
             + logic service penalty
             + hierarchy transfer penalty
```

자원값은 penalty를 0까지 줄일 수 있지만, bank command cycle 자체를 줄이지 못한다.

## 7. 연구적으로 중요한 결론

logic die를 추가했다는 사실만으로는 speed-up이 생기지 않는다. 성능 우위를 만들려면 logic die가 다음 중 하나 이상을 제공해야 한다.

1. 96/192 channel에 맞는 compact output tile로 불필요한 4096-output 명령을 제거한다.
2. 여러 bank의 partial sum을 logic die에서 모아 host 또는 HBM I/O 왕복을 줄인다.
3. 여러 spatial position을 logic PCU에서 병렬 처리해 command 수를 줄인다.
4. bank-side에서는 불가능한 cross-bank reduction을 한 번의 logic operation으로 합친다.
5. 중간 tensor 전체가 아니라 partial sum 또는 필요한 channel만 전송한다.

이 항목들은 단순 파라미터 튜닝이 아니라 제안 architecture의 실질적인 기능 차이가 된다.

## 8. 다음 구현

다음 simulator 수정은 `compact output mapping` 후보 모델이다.

- 기존 물리 output tile: 4096
- MobileNetV4 논리 output: 96 또는 192
- 비교 후보: 128/256 단위 compact tile
- 측정값: command 수, padded MAC 수, cycle, logic service, 계층 전송량

그 다음 partial-sum protocol 후보를 추가해 compact mapping만 적용한 경우와 결합한 경우를 ablation으로 비교한다.
