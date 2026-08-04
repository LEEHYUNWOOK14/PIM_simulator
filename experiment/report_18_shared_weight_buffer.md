# 18차 기술 구현 보고서: Logic-die 공유 가중치 버퍼 실제 경로

## 1. 목적

MobileNetV4 UIB pointwise 연산에서 같은 가중치를 spatial group마다 HBM bank에 복제하던 방식을 logic die의 중앙 공유 버퍼 한 벌로 대체한다. 이번 단계는 통계 예측이 아니라 다음 기능을 실제 실행 경로에 반영한다.

1. 첫 spatial group의 가중치 한 벌만 메모리 write transaction으로 적재한다.
2. 모든 채널의 logic PCU가 중앙 버퍼를 공동 참조한다.
3. 이후 group의 중복 preload transaction을 생성하지 않는다.
4. 정확도, 실제 write 수, buffer hit/miss, cycle을 함께 검증한다.

## 2. 구현 구조

공유 버퍼 키는 다음과 같다.

```text
(group 내부 channel, rank, bank, row, column)
```

물리 channel은 `physical_channel % channels_per_group`으로 정규화한다. 따라서 expand의 21개 group과 project의 32개 group이 서로 다른 물리 channel을 사용해도 동일한 논리 가중치 주소를 읽는다.

새 계층이 시작될 때 버퍼를 비운다. 해당 계층의 가중치 한 벌이 용량보다 크면 버퍼를 비활성화하고 기존 bank preload 경로를 사용한다. 이전 계층의 stale weight가 다음 계층에서 hit하는 것을 금지한다.

## 3. 설정

```ini
LOGIC_SHARED_WEIGHT_BUFFER=true
LOGIC_WEIGHT_BUFFER_BYTES=65536
```

기본 설정은 `false/0`이므로 bank-side 기준선과 기존 실험에는 영향을 주지 않는다.

## 4. MobileNetV4 UIB 용량

실제 형상은 `14x14x96 -> 192 -> 96`이다.

| 계층 | 한 벌 | Group 수 | 기존 복제량 |
|---|---:|---:|---:|
| Expand pointwise | 49,152 B | 21 | 1,032,192 B |
| Project pointwise | 65,536 B | 32 | 2,097,152 B |
| 합계 | 114,688 B(순차 적재) | - | 3,129,344 B |

두 계층은 순차 실행되므로 65,536 B 버퍼 하나를 재사용하면 둘 다 수용할 수 있다.

## 5. 재현 방법

WSL에서 저장소 루트로 이동한 뒤 실행한다.

```bash
bash experiment/run_shared_weight_buffer_sweep.sh
```

스크립트는 `0, 32768, 49152, 65536 B`를 차례로 적용하고 종료 시 원래 설정을 복원한다.

```text
experiment/results/shared_weight_buffer_sweep.csv
```

## 6. 실제 결과

| Buffer | Baseline weight | Physical weight | Actual writes | Fill bursts | Read hits | Misses | Cycle |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 B | 3,129,344 B | 3,129,344 B | 319,668 | 0 | 0 | 0 | 219,854 |
| 32 KiB | 3,129,344 B | 3,129,344 B | 319,668 | 0 | 0 | 0 | 219,854 |
| 48 KiB | 3,129,344 B | 2,146,304 B | 288,948 | 1,536 | 301,056 | 0 | 226,757 |
| 64 KiB | 3,129,344 B | 114,688 B | 225,460 | 3,584 | 702,464 | 0 | 231,084 |

모든 행에서 MobileNetV4 UIB 출력 18,816개가 CPU 기준값과 일치했다.

## 7. 해석

### 7.1 트래픽

64 KiB에서 중복 가중치 3,014,656 B가 실제 transaction 경로에서 제거됐다.

```text
가중치 트래픽 감소율 = 3,014,656 / 3,129,344 = 96.34%
전체 write 감소율 = (319,668 - 225,460) / 319,668 = 29.47%
```

`buffer_read_hits=702464`, `buffer_read_misses=0`이므로 logic MAC이 누락된 bank 데이터로 fallback하지 않고 공유 버퍼를 실제 사용했다.

### 7.2 성능

64 KiB cycle은 219,854에서 231,084로 11,230 cycle, 즉 5.11% 증가했다.

기존 복제 방식은 더 많은 데이터를 쓰지만 21개 또는 32개 channel group이 preload를 병렬 처리한다. 현재 공유 방식은 한 벌을 2~3개 channel에 집중해 채우므로 총 트래픽은 감소해도 fill 완료가 직렬 병목이 된다.

따라서 이번 결과는 “공유 버퍼가 실패했다”가 아니라 다음 설계 조건을 보여준다.

> 중앙 공유 버퍼는 용량뿐 아니라 여러 HBM channel에서 동시에 fill할 수 있는 striping 또는 multicast 경로가 필요하다.

## 8. 출력 읽는 법

```text
baseline_logic_weight_bytes[3129344]
physical_logic_weight_bytes[114688]
saved_logic_weight_bytes[3014656]
writes[225460]
logic_weight_buffer_fill_bursts[3584]
logic_weight_buffer_read_hits[702464]
logic_weight_buffer_read_misses[0]
total_cycle[231084]
```

- `baseline_logic_weight_bytes`: 공유 버퍼가 없을 때 필요한 복제량
- `physical_logic_weight_bytes`: 실제 적재한 가중치량
- `saved_logic_weight_bytes`: 제거된 중복 적재량
- `writes`: 메모리 컨트롤러가 실제 처리한 전체 write transaction
- `fill_bursts`: 중앙 버퍼에 적재한 32 B burst 수
- `read_hits/misses`: logic MAC의 중앙 버퍼 조회 결과
- `total_cycle`: 중복 transaction 제거 후 실제 시뮬레이션 cycle

## 9. 검증

```bash
./sim --gtest_filter='LogicDieWeightBufferTest.*:LogicDieSchedulerTest.*'
```

총 6개 단위 테스트가 통과했다. 실제 UIB 테스트에는 다음 회귀 조건도 포함했다.

- baseline weight = 3,129,344 B
- 용량별 physical weight가 계산값과 일치
- 중앙 버퍼 사용 시 read hit가 0보다 큼
- 모든 경우 read miss = 0
- 최종 출력 18,816개 일치

## 10. 다음 실험

다음 구현은 한 벌의 가중치를 중앙 버퍼에 넣는 source transaction을 여러 HBM channel에 stripe하는 모델이다. fill channel 수를 `1, 2, 4, 8, 16, 32, 64`로 바꾸어 96.34% 트래픽 절감은 유지하면서 5.11% cycle 증가를 제거할 최소 병렬도를 찾는다.
