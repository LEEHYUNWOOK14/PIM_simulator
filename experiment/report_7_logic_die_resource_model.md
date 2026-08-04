# 7차 실험 보고서: logic-die 자원 모델 연결 검증

## 1. 목적

`NUM_LOGIC_PIM_UNITS`, `LOGIC_PIM_LATENCY`, `LOGIC_PIM_BW`가 설정 파일에만 존재하지 않고 실제 시뮬레이션 cycle에 영향을 주는지 확인한다.

이 실험은 최적 아키텍처 값을 결정하는 연구 실험이 아니다. 세 파라미터와 시뮬레이터 실행시간의 연결을 검증하는 기술 실험이다.

## 2. 구현된 파라미터 의미

| 변수 | 현재 기능 모델에서의 의미 |
|---|---|
| `NUM_LOGIC_PIM_UNITS` | 한 wave에서 동시에 처리할 수 있는 PIM block 수 |
| `LOGIC_PIM_LATENCY` | logic-die 연산 wave당 compute cycle |
| `LOGIC_PIM_BW` | logic-die 데이터 경로의 byte/cycle. `0`은 대역폭 무제한 |

PIM block 수가 `B`, logic PCU 수가 `U`이면 wave 수는 `ceil(B/U)`이다. compute cycle은 `wave × LOGIC_PIM_LATENCY`, transfer cycle은 `ceil(transfer_bytes/LOGIC_PIM_BW)`로 계산한다. 현재 서비스 시간은 compute와 transfer가 겹칠 수 있다고 가정하여 두 값 중 큰 값으로 계산한다.

## 3. 재실행 명령

WSL에서 프로젝트 루트로 이동한 다음 실행한다.

```bash
bash experiment/run_logic_model_sensitivity.sh
```

스크립트는 세 설정 파일을 임시 수정하고 실험 종료 시 원래 내용으로 자동 복원한다.

## 4. 실험 조건

| 조건 | Unit | Latency | BW |
|---|---:|---:|---:|
| compatibility | 8 | 0 cycle | 무제한 |
| constrained | 2 | 4 cycle/wave | 32 byte/cycle |

두 조건 모두 `logic_die` target으로 `PIMBenchFixture.gemv`를 실행했다.

## 5. 실행 결과

| 조건 | non-PIM cycle | logic-die PIM cycle | Speed-up |
|---|---:|---:|---:|
| compatibility | 36,082 | 13,166 | 2.74054 |
| constrained | 36,082 | 44,771 | 0.805923 |

채널 0의 누적 계측값은 다음과 같다.

| 조건 | Logic 명령 | Compute cycle | Transfer byte | Transfer cycle | Service cycle |
|---|---:|---:|---:|---:|---:|
| compatibility | 2,048 | 0 | 524,288 | 0 | 0 |
| constrained | 2,048 | 32,768 | 524,288 | 16,384 | 32,768 |

constrained 조건의 명령 trace 예시는 다음과 같다.

```text
LOGIC_DIE_RESERVE cmd[MAC ...] units[2] waves[4]
compute_cycles[16] transfer_bytes[256] transfer_cycles[8]
```

- `units[2]`, `waves[4]`: 8개 PIM block을 2개 unit으로 처리하므로 4 wave가 필요하다.
- `compute_cycles[16]`: `4 wave × 4 cycle`이다.
- `transfer_cycles[8]`: `256 byte ÷ 32 byte/cycle`이다.
- 서비스 시간은 `max(16, 8) = 16 cycle`로 예약된다.

## 6. 결과 해석

PIM cycle이 `13,166`에서 `44,771`로 `31,605 cycle` 증가했다. 따라서 unit 수, latency, bandwidth가 단순 파싱값이 아니라 command 발행 제한과 read 반환 지연에 실제로 연결되었다.

constrained 조건에서 Google Test가 실패하는 것은 현재 benchmark가 speed-up이 2배를 초과해야 한다고 고정했기 때문이다. 이 실험에서는 자원 제약에 따라 cycle이 증가하는지가 판정 대상이므로, 해당 실패는 기능 오류를 뜻하지 않는다.

## 7. 정확도 회귀 결과

기능 정확도는 별도로 확인했다.

| 모드 | 테스트 | 결과 |
|---|---|---|
| bank-side | `add`, `relu`, `mul`, `gemv`, `gemv_tree` | 5개 모두 통과 |
| logic-only | `gemv` | 4096/4096 통과 |
| logic-only | `gemv_tree` | 4096/4096 통과 |

## 8. 현재 가정과 다음 과제

현재 transfer byte는 logic-die 명령 한 번에 각 PIM block에서 burst 하나가 전달되는 것으로 계산한다. compute와 transfer는 겹친다고 가정한다. 이 두 항목은 기능 모델을 실행하기 위한 명시적 기본 가정이며, 최종 아키텍처가 정해지면 연구자의 protocol 정의에 맞춰 수정해야 한다.

다음 기술 작업은 누적 명령 수, compute cycle, transfer byte, stall cycle을 실험 결과 파일에 직접 출력하는 통계 인터페이스를 추가하는 것이다.
