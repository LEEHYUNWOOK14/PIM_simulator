# 라우팅 검증 실험 체크리스트

이 문서는 현재 시뮬레이터가 `bank-side PIM`, `logic-die PIM`, `HYBRID`로 나뉘는 방식을
실제로 확인하기 위한 실험 순서를 정리한 것이다.

## 1. 준비 조건

실험 전에 아래가 준비되어 있어야 한다.

1. `system_hbm.ini` 또는 `system_hbm_64ch.ini` 수정 가능
2. `./sim` 실행 가능
3. `PIMKernelFixture`와 `PIMBenchFixture` 실행 가능
4. 현재 설정값을 다시 원래대로 되돌릴 수 있는 상태

## 2. bank-side only 실험

### 목적
기존 bank-side PIM 경로가 지금도 정상 동작하는지 다시 확인한다.

### 설정

1. `ENABLE_BANK_SIDE_PIM=true`
2. `ENABLE_LOGIC_DIE_PIM=false`
3. `PIM_TARGET=bank_side`

### 권장 실행

1. `PIMKernelFixture.add`
2. `PIMKernelFixture.relu`
3. `PIMKernelFixture.mul`
4. `PIMKernelFixture.gemv`
5. `PIMKernelFixture.gemv_tree`

### 기대 결과

- 기존 bank-side 경로가 깨지지 않았는지 확인 가능
- 현재 수정이 기존 기능을 망가뜨리지 않았는지 볼 수 있음

### 판단 기준

- 정확도 테스트가 통과하면 bank-side 기능은 유지된 것으로 본다
- benchmark 결과는 speed-up 수치가 이전과 크게 다르지 않은지 확인한다

## 3. logic-die only 실험

### 목적
logic-die 후보 명령이 실제로 분리되어 들어가는지 확인한다.

### 설정

1. `ENABLE_BANK_SIDE_PIM=false`
2. `ENABLE_LOGIC_DIE_PIM=true`
3. `PIM_TARGET=logic_die`

### 권장 실행

1. `PIMKernelFixture.gemv`
2. `PIMKernelFixture.gemv_tree`
3. 필요하면 `PIMKernelFixture.add`도 참고용으로 확인

### 기대 결과

- logic-die 경로로 들어가는 명령이 따로 분리되는지 확인 가능
- 아직 미구현 부분이 있으면 어떤 명령에서 막히는지 바로 드러남

### 판단 기준

- 예상한 명령이 logic-die 경로를 타는지 본다
- 예외가 발생하면 어떤 명령이 아직 bank-side 가정에 묶여 있는지 확인한다

## 4. hybrid 실험

### 목적
bank-side와 logic-die가 동시에 켜졌을 때 명령이 올바르게 분리되는지 확인한다.

### 설정

1. `ENABLE_BANK_SIDE_PIM=true`
2. `ENABLE_LOGIC_DIE_PIM=true`
3. `PIM_TARGET=hybrid`

### 권장 실행

1. `PIMKernelFixture.add`
2. `PIMKernelFixture.relu`
3. `PIMKernelFixture.mul`
4. `PIMKernelFixture.gemv`

### 기대 결과

- 단순 연산은 bank-side로 유지
- 누산 중심 연산은 logic-die 후보로 분리
- 둘이 동시에 켜져도 충돌하지 않아야 함

### 판단 기준

- 명령 분리 규칙이 코드에서 의도대로 작동하는지 확인한다
- 둘 중 하나가 다른 쪽을 잘못 덮어쓰지 않는지 본다

## 5. 다음 실험 순서

이 체크리스트 기준으로 다음 순서는 아래가 좋다.

1. bank-side only 상태에서 안정성 재확인
2. logic-die only 상태에서 후보 명령 분리 확인
3. hybrid 상태에서 분기 정책 확인
4. 그 다음에 MobileNetV4 블록별 매핑을 붙인다

## 6. 결론

이 단계의 실험은 아직 성능 최적화가 아니라,
라우팅과 분리 구조가 맞는지 확인하는 검증 단계다.

즉, 지금은
`bank-side는 계속 돌아가고`,
`logic-die는 분리되고`,
`hybrid는 둘을 구분할 수 있는가`
를 보는 것이 핵심이다.
