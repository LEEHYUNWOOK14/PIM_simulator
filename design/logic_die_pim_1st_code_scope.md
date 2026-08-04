# logic-die PIM 1차 코드 수정 범위

## 1. 목적

이 문서는 기존 bank-side PIM 시뮬레이터에 logic-die PIM을 추가하기 위한 1차 코드 수정 범위를 정리한 작업표다.

목표는 단순 기능 추가가 아니라, 다음 두 경로를 분리해서 검증할 수 있게 만드는 것이다.

- bank-side PIM
- logic-die PIM

이 문서는 실제 수정 전에 어디부터 손댈지 정하는 기준 문서로 쓴다.

## 2. 현재 확인된 구조

### 2.1 64채널 전제 지점

- `src/tests/PIMBenchTestCases.h`
  - 벤치마크 테스트가 `system_hbm_64ch.ini`를 직접 사용한다.
  - `PIMKernel`도 `64, 1`로 생성된다.
- `src/tests/KernelTestCases.h`
  - 정확도 테스트도 `system_hbm_64ch.ini`를 고정으로 쓴다.

즉, 테스트 경로는 현재 64채널 전제를 강하게 가진다.

### 2.2 일반화되어 있는 지점

- `src/Configuration.h`
  - `NUM_CHANS`를 설정 파일에서 읽는다.
- `src/MultiChannelMemorySystem.cpp`
  - 채널 배열과 루프를 `configuration->NUM_CHANS` 기준으로 돌린다.

즉, 시뮬레이터 코어는 원칙적으로 채널 수를 일반화해서 받아들인다.

### 2.3 bank-side PIM 중심 지점

- `src/PIMRank.cpp`
- `src/tests/PIMKernel.h/.cpp`
- `src/tests/PIMCmdGen.h/.cpp`

이 부분이 실제 bank-side PIM 경로의 중심이다.

## 3. 1차 수정 목표

1차 수정에서는 다음을 먼저 만든다.

1. bank-side PIM과 logic-die PIM을 구분할 수 있는 설정값
2. 명령이 어느 PIM으로 가는지 표시할 수 있는 타겟
3. 실행 계층을 분리할 발판
4. 기존 bank-side 기능을 깨지 않는 검증 경로

## 4. 파일별 1차 수정 항목

### 4.1 설정 계층

#### 대상 파일

- `src/ConfigurationData.h`
- `src/Configuration.h`
- `src/SystemConfiguration.h`
- `system_hbm.ini`

#### 수정 내용

- `ENABLE_BANK_SIDE_PIM`
- `ENABLE_LOGIC_DIE_PIM`
- `NUM_LOGIC_PIM_UNITS`
- `LOGIC_PIM_LATENCY`
- `LOGIC_PIM_BW`
- `PIM_TARGET` 또는 유사한 위치 enum

#### 목적

- bank-side와 logic-die를 설정 단계에서부터 분리하기 위함
- 나중에 한쪽만 켜서 비교할 수 있게 하기 위함

#### 검증 기준

- 설정 파일을 바꿨을 때 파서가 정상 동작해야 한다.
- 새 항목이 `Configuration` 객체로 읽혀야 한다.

### 4.2 명령 타겟 계층

#### 대상 파일

- `src/PIMCmd.h`
- `src/PIMCmd.cpp`
- `src/tests/PIMCmdGen.h`
- `src/tests/PIMCmdGen.cpp`

#### 수정 내용

- PIM 명령에 target 필드 추가
- `BANK_SIDE`, `LOGIC_DIE`, `HOST` 구분 추가
- MobileNetV4 블록별 명령 생성기 확장

#### 목적

- 같은 연산이라도 어느 계층에서 수행되는지 표시하기 위함
- logic-die로 올릴 연산과 bank-side에 남길 연산을 나누기 위함

#### 검증 기준

- 명령이 생성될 때 target이 빠지지 않아야 한다.
- 기존 bank-side 명령은 기존처럼 동작해야 한다.

### 4.3 실행 계층 분리

#### 대상 파일

- `src/PIMRank.h`
- `src/PIMRank.cpp`
- 새 파일 후보: `src/LogicDiePIM.h/.cpp`
- 새 파일 후보: `src/PIMScheduler.h/.cpp`

#### 수정 내용

- bank-side 실행과 logic-die 실행을 분리
- 상위 scheduler가 어느 쪽으로 보낼지 결정
- `PIMRank`는 가능한 한 routing/control 위주로 정리

#### 목적

- 계층형 PIM 구조를 시뮬레이터에서 표현하기 위함
- 연산 함수만 늘리는 방식이 아니라 구조 자체를 분리하기 위함

#### 검증 기준

- bank-side 전용 테스트가 계속 통과해야 한다.
- logic-die 경로가 추가되어도 기존 경로가 깨지면 안 된다.

### 4.4 Rank 및 memory routing

#### 대상 파일

- `src/Rank.h`
- `src/Rank.cpp`
- `src/MemoryController.cpp`
- `src/CommandQueue.cpp`

#### 수정 내용

- logic-die 상태 보관
- bank-local 경로와 logic-die transfer 경로 분리
- 큐 정책이 두 경로를 섞지 않도록 조정

#### 목적

- 여러 bank를 엮는 연산에서 중간 데이터 이동을 줄이기 위함
- bank-side와 logic-die 사이의 역할 경계를 만들기 위함

#### 검증 기준

- bank-side only 실행이 유지되어야 한다.
- hybrid 요청이 들어왔을 때 routing 충돌이 없어야 한다.

### 4.5 테스트와 벤치마크

#### 대상 파일

- `src/tests/KernelTestCases.cpp`
- `src/tests/PIMBenchTestCases.cpp`
- `src/tests/TestCases.h`

#### 수정 내용

- bank-side only 테스트 유지
- logic-die only 테스트 추가
- hybrid 비교 테스트 추가
- MobileNetV4 블록별 functional test 추가

#### 목적

- 수정 결과를 즉시 검증하기 위함
- 설계가 실제로 동작하는지 숫자로 확인하기 위함

#### 검증 기준

- 기존 `add`, `relu`, `mul`, `gemv`, `gemv_tree`가 유지되어야 한다.
- 새 테스트는 위치별 경로를 분리해서 보여줘야 한다.

## 5. 1차 구현 순서

### 5.1 먼저 할 것

1. `ConfigurationData.h`와 `system_hbm.ini`에 logic-die 관련 설정 추가
2. `SystemConfiguration.h`에 target enum 및 해석 함수 추가
3. `PIMCmd` 구조에 target 필드 추가
4. `PIMKernel`에서 bank-side와 logic-die 호출 분리

### 5.2 다음 할 것

1. `PIMRank` routing 분리
2. `Rank`와 `MemoryController`에서 경로 추적 추가
3. 테스트 케이스에 hybrid 비교 추가

### 5.3 나중에 할 것

1. fused op 정리
2. MobileNetV4 블록별 정밀 매핑
3. Verilog 구조와 1:1 대응 점검

## 6. 실험과 코드 수정을 같이 묶는 방식

코드 수정은 아래 순서로 검증한다.

1. 설정 파일을 하나 바꾼다.
2. 관련 테스트를 한 개만 돌린다.
3. 출력이 유지되는지 본다.
4. bank-side 결과와 logic-die 결과를 분리해서 기록한다.
5. 마지막에 hybrid로 합친다.

이 순서를 지키면 어디서 깨졌는지 추적하기 쉽다.

## 7. 현재 시점의 결론

지금 필요한 것은 모든 기능을 한 번에 넣는 것이 아니라, bank-side 경로를 보존하면서 logic-die를 붙일 수 있는 최소 골격을 먼저 만드는 일이다.

즉, 1차 목표는 다음 한 줄로 정리할 수 있다.

> 기존 bank-side PIM을 유지한 채, logic-die PIM을 target과 execution 계층으로 분리해 시뮬레이터가 두 경로를 구분해서 실행하도록 만드는 것.

