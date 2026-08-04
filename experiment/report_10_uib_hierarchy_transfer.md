# 10차 기술 구현 보고서: UIB 계층 연결과 전송 비용

## 1. 실험 목적

MobileNetV4 Conv-S의 `uib14_ib` 블록을 bank-side PCU와 logic-die PCU 사이에 배치하고, 연속된 layer의 tensor shape가 호환되는지 검사한다. 연산 위치가 바뀌는 지점에서는 bank↔logic 전송 byte와 cycle을 시뮬레이터 시간에 반영한다.

## 2. 수정한 workload

기존 manifest에는 IB의 projection 단계가 빠져 있었다. `uib14_ib_project`를 추가해 아래 순서를 완성했다.

| 순서 | 연산 | 입력→출력 channel | 실행 위치 |
|---:|---|---:|---|
| 1 | pointwise expand | 96→192 | logic die |
| 2 | 3x3 depthwise | 192→192 | bank side |
| 3 | pointwise project | 192→96 | logic die |
| 4 | residual add | 96→96 | bank side |
| 5 | ReLU | 96→96 | bank side |

출처가 공식 block specification인 행과 프로젝트에서 정한 mapping 행은 manifest의 `source` 열에서 구분한다. 연산 배치는 공식 MobileNetV4 구조가 아니라 본 프로젝트의 계층형 PIM 가설이다.

## 3. 전송 비용 모델

연속된 두 단계의 실행 위치가 다를 때 다음 식을 적용한다.

```text
transfer_bytes = H × W × C × bytes_per_element
transfer_cycles = ceil(transfer_bytes / interconnect_bytes_per_cycle)
```

이번 기준값은 FP16이므로 element당 2 B, 계층 연결 대역폭은 64 B/cycle이다. 계산 결과는 다음과 같다.

| 전환 | Tensor | Byte | Cycle |
|---|---:|---:|---:|
| bank→logic expand 입력 | 14×14×96 | 37,632 | 588 |
| logic→bank depthwise 입력 | 14×14×192 | 75,264 | 1,176 |
| bank→logic project 입력 | 14×14×192 | 75,264 | 1,176 |
| logic→bank residual 입력 | 14×14×96 | 37,632 | 588 |
| 합계 | 4회 | 225,792 | 3,528 |

ReLU는 residual add와 동일한 bank-side 위치에서 실행되므로 추가 전송이 없다.

## 4. 시뮬레이터 반영 방식

`PIMKernel::accountHierarchyTransfer()`는 다음 값을 누적한다.

- 계층 전환 횟수
- 전송한 전체 byte
- 전송에 사용한 cycle

전송 cycle마다 `MultiChannelMemorySystem::update()`를 호출한다. 따라서 통계만 증가하는 것이 아니라 시뮬레이터의 공통 시간축도 같은 양만큼 진행한다.

이 값은 `LOGIC_DIE_STATS`와 의미가 다르다. `LOGIC_DIE_STATS`는 개별 PIM 명령 실행 중 logic PCU가 처리한 burst를 세며, `MOBILENETV4_HIERARCHY_STATS`는 layer 배치가 바뀌면서 이동하는 전체 중간 tensor를 센다.

## 5. 실행 명령

전체 MobileNetV4 모드 검사는 저장소 루트의 WSL 터미널에서 실행한다.

```bash
bash experiment/run_mobilenetv4_workload_checks.sh
```

UIB 그래프와 계층 전송만 다시 확인하려면 다음 명령을 사용한다.

```bash
./sim --gtest_filter='MobileNetV4WorkloadTest.ConvSmallIbExecutionPlan:MobileNetV4WorkloadTest.HierarchyTransferAccounting'
```

기존 PIM 기본 연산까지 포함한 전체 회귀 명령은 다음과 같다.

```bash
./sim --gtest_filter='PIMKernelFixture.add:PIMKernelFixture.relu:PIMKernelFixture.mul:PIMKernelFixture.gemv:PIMKernelFixture.gemv_tree:MobileNetV4WorkloadTest.*'
```

## 6. 핵심 출력 예시와 해석

```text
MOBILENETV4_HIERARCHY_STATS block[uib14_ib]
transfers[4] bytes[225792] cycles[3528]
bandwidth_bytes_per_cycle[64]
```

- `block`: 분석한 MobileNetV4 block 이름이다.
- `transfers`: bank와 logic die 사이에서 실행 위치가 바뀐 횟수다.
- `bytes`: 네 번의 전환에서 이동한 논리 tensor의 합이다.
- `cycles`: 설정한 연결 대역폭으로 전송할 때 필요한 누적 지연이다.
- `bandwidth_bytes_per_cycle`: 이번 계산에 사용한 계층 연결 대역폭이다.

최종 회귀 결과는 다음과 같다.

```text
[==========] 16 tests from 2 test suites ran.
[  PASSED  ] 16 tests.
```

## 7. 현재 검증 범위

이번 구현으로 검증된 내용:

- UIB 각 단계의 spatial/channel shape가 순서대로 연결된다.
- shape가 맞지 않는 manifest는 실행 전에 오류로 거부된다.
- bank↔logic 전환 위치와 논리 tensor 전송량을 자동 계산한다.
- 전송 지연이 시뮬레이터 시간축에 반영된다.
- bank-only, logic-only, hybrid 기본 연산 테스트가 모두 유지된다.

아직 검증하지 않은 내용:

- expand 출력값을 실제로 depthwise 입력으로 재배치하는 전체 수치 연산 연쇄
- residual skip tensor의 실제 메모리 주소와 수명
- 전체 tensor 대신 partial sum만 전송하는 대안 protocol
- bank↔logic 연결의 queue contention과 양방향 동시 전송
- 전체 UIB cycle과 energy

따라서 `3,528 cycle`은 현재 가정한 전체 tensor 전송 비용이며 최종 제안 구조의 확정 성능값이 아니다.

## 8. 다음 구현 단계

다음에는 작은 축소 UIB를 대상으로 pointwise 출력→depthwise tap layout→projection→residual의 실제 데이터를 연결한다. 기능 정확도를 먼저 CPU golden model과 비교한 후, 동일 실행기에서 MobileNetV4 원래 shape의 cycle 및 이동량을 계측한다.
