# 56차 실험 보고서: 출력 버퍼 A/B 및 배출 타이밍

## 1. 목적

55차 구현의 READ 완료 기반 출력 버퍼를 설정으로 켜고 끌 수 있게 만들고, 출력 버퍼 용량과
downstream 배출 지연·대역폭을 cycle 모델에 반영한다. 동일 바이너리와 동일 MobileNetV4 UIB에서
사후 복사 기준과 실제 콜백 모델을 비교한다.

## 2. 추가한 설정

| 설정 | 의미 | 기본값 |
|---|---|---:|
| `LOGIC_OUTPUT_BUFFER_ENABLE` | `true`: 실제 READ 완료 기반, `false`: 사후 복사 기준 | `false` |
| `LOGIC_OUTPUT_BUFFER_ENTRIES` | 동시에 조립할 수 있는 위치 타일 수 | 2 |
| `LOGIC_OUTPUT_DRAIN_LATENCY` | 완성된 선두 타일의 이동 시작 전 지연 cycle | 0 |
| `LOGIC_OUTPUT_DRAIN_BW` | cycle당 downstream 이동 burst 수, 0은 즉시 커밋 | 0 |

용량에 0을 입력하면 무한 대기를 막기 위해 내부적으로 1 entry로 정규화한다.

## 3. 실행 방법

WSL 프로젝트 루트에서 다음 한 줄을 실행한다.

```bash
bash experiment/run_output_buffer_ab_sweep.sh
```

스크립트는 다음 작업을 자동 수행한다.

1. `system_hbm.ini`, `system_hbm_64ch.ini`를 임시 폴더에 백업한다.
2. 세 실험 조건에 맞게 네 설정값을 수정한다.
3. 실제 `14x14x96 -> 192 -> 96` UIB를 실행한다.
4. 출력 행의 실제 설정값이 요청한 값과 일치하는지 검사한다.
5. 결과를 `experiment/results/output_buffer_ab_sweep.csv`에 저장한다.
6. 성공, 실패, 중단 여부와 관계없이 원본 설정 파일을 복원한다.

단순히 다음처럼 환경변수를 앞에 붙이는 방법은 이 시뮬레이터에서 설정을 변경하지 못한다.

```bash
# 사용하지 말 것: INI 값이 바뀌지 않는다.
LOGIC_OUTPUT_BUFFER_ENABLE=true ./sim --gtest_filter=...
```

## 4. 결과

| 모델 | Enable | Latency | BW | 출력 검사 | 반환 재시도 | 포화 wall-cycle | Drain busy | 총 cycle |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 사후 복사 기준 | 0 | 0 | 0 | 18,816 PASS | 388 | 0 | 0 | 214,228 |
| READ 콜백, 즉시 배출 | 1 | 0 | 0 | 18,816 PASS | 751,369 | 25,987 | 0 | 214,842 |
| READ 콜백, 유한 배출 | 1 | 4 | 8 | 18,816 PASS | 891,233 | 30,432 | 8,624 | 214,947 |

세 조건 모두 타일 예약/퇴출은 `392/392`, 최대 점유는 2였다.

## 5. 상세 해석

READ 콜백을 켜면 사후 복사 기준보다 614 cycles, 약 0.287% 증가했다. 이 차이는 실제 READ
반환이 2-entry 버퍼 공간을 기다리도록 연결했을 때 발생한 cycle-level 비용이다.

`latency=4`, `BW=8 bursts/cycle` 조건은 즉시 배출 콜백보다 105 cycles, 약 0.049% 증가했다.
각 완성 타일에 누적된 drain busy 비용은 총 8,624 cycles지만 대부분 기존 연산과 메모리 동작에
겹쳐 전체 critical path에는 105 cycles만 노출되었다.

`full_retry_channel_cycles`는 wall-clock 지연이 아니다. 여러 채널이 같은 cycle에 버퍼 포화를
만나면 각각 증가하므로 891,233이라는 큰 수를 총 cycle에 더하면 안 된다. 이는 interconnect와
반환 포트가 받은 backpressure 강도를 비교하는 지표다.

즉시 배출 모델은 포화된 25,987 cycles 동안 평균 `751,369 / 25,987 = 28.91`개 채널이
동시에 막혔다. 유한 배출 모델은 30,432 cycles 동안 평균 29.29개 채널이 막혔다. 전체
critical-path 증가는 작지만 반환 네트워크에는 약 29채널 규모의 동시 압력이 있으므로 RTL에서
채널 응답을 하나의 blocking FIFO로 단순 직렬화하면 HOL blocking이 커질 수 있다.

## 6. 설계 판단

현재 MobileNetV4 UIB 조건에서는 2-entry 출력 버퍼와 `4-cycle, 8 bursts/cycle` 배출 모델의
critical-path 추가 비용이 105 cycles로 작다. 출력 배출 자체는 현재 성능의 주 병목이 아니지만,
포화 시 약 29개 채널이 동시에 대기하므로 채널별 응답 queue와 공정한 arbitration은 필요하다.
로직 PIM 설계의 다음 성능 우선순위는 bank/logic 실행 overlap과 source-scoped execution context다.

단, `2 entries`, `latency 4`, `BW 8`은 RTL 확정값이 아니다. 면적·배선·SRAM/레지스터 구현 결과와
다른 모델의 출력 shape를 반영해 연구자가 최종 결정해야 한다.

## 7. 다음 단계

1. 출력 버퍼 entry `1/2/4/8`, bandwidth `1/2/4/8/16` sweep으로 민감도를 측정한다.
2. wall-cycle 포화와 channel-cycle 반환 재시도를 분리한다.
3. bank-side와 logic-side의 PC, repeat/jump, mode 상태를 분리하여 source queue를 다시 활성화한다.
