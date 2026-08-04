# 현재 PIM 라우팅 상태

이 문서는 현재 시뮬레이터가 `bank-side PIM`, `logic-die PIM`, `HYBRID`를 어떤 조건에서 나누는지
한눈에 보기 위한 상태 기록이다.

핵심은 아직 설계 전체가 완성된 것은 아니라는 점이다.
지금은 `bank-side` 경로는 실제 검증이 가능하고, `logic-die`는 분리된 라우팅 골격을 넣는 단계다.

## 1. 현재 구조 요약

현재 코드는 크게 다음 세 층으로 나뉜다.

1. `PIMKernel`
   - 테스트/벤치마크 레벨에서 bank-side 사용 여부와 logic-die 사용 여부를 판단한다.
   - 어떤 테스트가 어떤 경로로 흘러갈지 정한다.
2. `PIMRank`
   - 실제 PIM 명령을 받아 bank-side 경로 또는 logic-die 경로로 보낸다.
   - logic-die 후보 명령이면 별도 분기한다.
3. `PIMCmdGen`
   - `ADD`, `MUL`, `MAC`, `MAD`, `RELU`, `GEMV`, `GEMV_TREE` 같은 테스트용 명령을 만든다.

즉, 현재 상태는 `설정값 -> 실행 모드 -> 명령 생성 -> rank 라우팅`으로 분리된 구조다.

## 2. 설정값과 현재 역할

| 설정값 | 의미 | 현재 코드에서 하는 일 |
|---|---|---|
| `ENABLE_BANK_SIDE_PIM` | bank-side PIM을 사용할지 여부 | `PIMKernel`, `PIMRank`에서 bank-side 경로를 허용할지 판단 |
| `ENABLE_LOGIC_DIE_PIM` | logic-die PIM을 사용할지 여부 | logic-die 후보 명령을 따로 떼어낼지 판단 |
| `NUM_LOGIC_PIM_UNITS` | logic-die 유닛 수 | 현재는 선언만 있고 실제 스케줄링에는 아직 미반영 |
| `LOGIC_PIM_LATENCY` | logic-die 지연시간 | 현재는 선언만 있고 실행 지연 모델에는 아직 미반영 |
| `LOGIC_PIM_BW` | logic-die 대역폭 | 현재는 선언만 있고 데이터 이동 모델에는 아직 미반영 |
| `PIM_TARGET` | 최종 타겟 모드 | `bank_side`, `logic_die`, `hybrid`, `host` 중 선택 |

## 3. 현재 라우팅 모드

`PIMRank`은 내부적으로 아래 3가지 모드로 동작한다.

| 모드 | 조건 | 의미 |
|---|---|---|
| `BANK_ONLY` | bank-side만 켜져 있거나, logic-die가 꺼져 있을 때 | 기존 bank-side 경로만 실행 |
| `LOGIC_ONLY` | logic-die만 켜져 있고 bank-side가 꺼져 있을 때 | logic-die 후보 명령이 logic-die 경로로 분기됨 |
| `HYBRID` | bank-side와 logic-die가 모두 켜져 있을 때 | 명령 종류에 따라 bank-side 또는 logic-die로 분리 |

중요한 점은, 지금은 `HYBRID`가 단순한 분기 골격이라는 것이다.
실제 스케줄링 정책이나 자원 경쟁 해소는 아직 더 넣어야 한다.

## 4. 명령별 현재 의미

`PIMCmdGen` 기준으로 명령은 아래처럼 해석된다.

| 명령 | 현재 의미 | logic-die 후보 여부 |
|---|---|---|
| `ADD` | bank-side 엘리먼트와이즈 연산 | 아니오 |
| `MUL` | bank-side 엘리먼트와이즈 연산 | 아니오 |
| `MAC` | GEMV용 누산 연산 | 예 |
| `MAD` | 3항 누산 계열 | 예 |
| `RELU` | bank-side activation 경로 | 아니오 |
| `FILL`, `MOV`, `NOP`, `JUMP`, `EXIT` | 제어/이동 명령 | 아니오 |

여기서 가장 중요한 기준은,
`MAC`/`MAD`만 logic-die 후보로 취급하고 `MUL`은 bank-side에 남겨두는 현재 정책이다.

즉, 지금의 의도는 다음과 같다.

- `ADD`, `RELU`, `MUL`은 bank-side에서 안정적으로 검증
- `MAC`, `MAD`는 logic-die 라우팅 후보로 분리
- `GEMV`, `GEMV_TREE`는 내부적으로 위 명령들을 조합한 상위 테스트

## 5. 현재 실험 해석

### 5.1 bank-side only

1. `ENABLE_BANK_SIDE_PIM = true`
2. `ENABLE_LOGIC_DIE_PIM = false`
3. `PIMKernel`은 bank-side 사용 경로를 선택
4. `PIMRank`는 bank-side 명령을 그대로 실행

이 상태는 기존 시뮬레이터가 잘 도는지 확인하는 기준선이다.

### 5.2 logic-die only

1. `ENABLE_BANK_SIDE_PIM = false`
2. `ENABLE_LOGIC_DIE_PIM = true`
3. `PIMKernel`은 logic-die 사용 경로를 인식
4. `PIMRank`에서 logic-die 후보 명령은 별도 경로로 분기

이 단계의 목적은 logic-die 분기 자체가 생겼는지 확인하는 것이다.
아직 실제 logic-die 하드웨어 모델은 완성형이 아니므로,
초기에는 경로 분리와 명령 해석이 주 목적이다.

### 5.3 hybrid

1. `ENABLE_BANK_SIDE_PIM = true`
2. `ENABLE_LOGIC_DIE_PIM = true`
3. `PIM_TARGET = hybrid`
4. `MAC`, `MAD`는 logic-die 후보로 인식
5. 나머지 연산은 bank-side 경로로 처리

이 모드는 나중에 실제 계층형 PIM 설계를 붙이기 위한 발판이다.

## 6. 아직 없는 것

아직 아래 항목은 구현 완료가 아니다.

- `NUM_LOGIC_PIM_UNITS`를 실제 스케줄링에 반영
- `LOGIC_PIM_LATENCY`를 실행 시간 모델로 반영
- `LOGIC_PIM_BW`를 데이터 이동 제약으로 반영
- logic-die 전용 연산기 구조 분리
- `HYBRID`에서 bank-side와 logic-die를 동시에 운영하는 상세 정책

따라서 현재 상태는
`bank-side는 검증 가능`, `logic-die는 분리 골격 확보`, `hybrid는 라우팅 골격 확보`
정도로 이해하면 된다.

## 7. 다음 실험 방향

지금 바로 할 수 있는 다음 실험은 아래 순서가 자연스럽다.

1. bank-side only 상태에서 `ADD`, `RELU`, `MUL`, `GEMV`, `GEMV_TREE`가 계속 잘 도는지 재확인
2. `ENABLE_LOGIC_DIE_PIM`를 켠 뒤, `MAC`와 `MAD`가 logic-die 경로로 들어가는지 확인
3. `HYBRID`로 바꿔서 bank-side와 logic-die가 분리 인식되는지 확인
4. 이후에 `MUL`의 위치나 fused op 확장 여부를 다시 판단

## 8. 결론

현재 시뮬레이터는 bank-side PIM 검증은 가능한 상태이고,
logic-die PIM은 실제 계층으로 확장하기 위한 분리 작업이 들어간 상태다.

즉, 지금 단계의 핵심은
`MUL`은 bank-side에 두고,
`MAC`/`MAD`만 logic-die 후보로 분리해서
시뮬레이터가 두 경로를 구분할 준비를 갖추는 것이다.
