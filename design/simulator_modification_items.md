# 시뮬레이터 수정 항목표

## 1. 목적

이 문서는 기존 HBM2 bank-side PIM 시뮬레이터를 기준으로, 여기에 logic-die PIM을 추가하기 위해 어디를 어떻게 수정해야 하는지 정리한 작업표다.

전제:

- 기존 구조는 bank-side PIM 중심이다.
- 목표는 `bank-side PIM + logic-die PIM` 하이브리드 구조다.
- 1차 타깃 모델은 MobileNetV4다.
- 이후 다른 모델을 추가할 수 있도록 공통 구조를 남겨둔다.

## 2. 근거가 되는 현재 구조

| 파일 | 현재 역할 |
|---|---|
| `src/PIMBlock.h/.cpp` | bank-side PIM 연산 블록 |
| `src/PIMRank.h/.cpp` | PIM 모드 전환, CRF 실행, PIM block dispatch |
| `src/Rank.h/.cpp` | rank 상태, bank 상태, PIM rank 연결 |
| `src/ConfigurationData.h` | 설정 항목 목록 |
| `src/SystemConfiguration.h` | PIM mode / precision / address mapping 해석 |
| `src/tests/PIMKernel.h/.cpp` | 테스트용 PIM 실행 흐름 |
| `src/tests/KernelTestCases.cpp` | 기능 테스트 진입점 |
| `src/tests/PIMCmdGen.h/.cpp` | PIM 명령 생성 |

## 3. 목표 아키텍처

| 계층 | 기존 | 목표 |
|---|---|---|
| 연산 위치 | bank-side PIM 중심 | bank-side PIM + logic-die PIM 분리 |
| 명령 타겟 | 사실상 단일 PIM 경로 | `BANK_SIDE`, `LOGIC_DIE`, `HOST` 타겟 분리 |
| 설정 | `NUM_PIM_BLOCKS`, `PIM_MODE`, `PIM_PRECISION` | 위치별 enable, latency, bandwidth, unit count 추가 |
| 실행 제어 | `PIMRank` 내부 집중 | `PIM controller / scheduler` 분리 가능 |
| 테스트 | GEMV, ADD, MUL, RELU 중심 | MobileNetV4 연산 블록별 테스트 추가 |

## 4. 수정 항목표

### 4.1 설정 파일과 파라미터 추가

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | logic-die PIM enable 플래그 | `system_hbm.ini`, `ConfigurationData.h` | `ENABLE_LOGIC_DIE_PIM` 추가 | 기능 on/off 제어 필요 |
| 1 | bank-side PIM enable 플래그 | `system_hbm.ini`, `ConfigurationData.h` | `ENABLE_BANK_SIDE_PIM` 추가 | 하이브리드 비교 필요 |
| 1 | logic-die 유닛 수 | `system_hbm.ini`, `ConfigurationData.h` | `NUM_LOGIC_PIM_UNITS` 추가 | RTL 구조와 맞춰야 함 |
| 1 | logic-die latency | `system_hbm.ini`, `ConfigurationData.h` | `LOGIC_PIM_LATENCY` 또는 유사 항목 추가 | 성능 비교용 핵심 파라미터 |
| 1 | logic-die bandwidth | `system_hbm.ini`, `ConfigurationData.h` | `LOGIC_PIM_BW` 또는 유사 항목 추가 | bank-side와 차별화 필요 |
| 1 | logic-die clock ratio | `system_hbm.ini`, `ConfigurationData.h` | `LOGIC_PIM_CLOCK_RATIO` 추가 | 별도 클럭 도메인 고려 |
| 2 | PIM target type | `ConfigurationData.h`, `SystemConfiguration.h` | `PIM_TARGET` 또는 placement enum 추가 | 명령 라우팅 기준 |

### 4.2 열거형과 공통 타입 정리

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | PIM 위치 enum 추가 | `src/SystemConfiguration.h` | `BANK_SIDE_PIM`, `LOGIC_DIE_PIM`, `HYBRID` 등 정의 | 위치 분리 필요 |
| 1 | PIM mode 확장 | `src/SystemConfiguration.h` | 기존 `SB`, `HAB`, `HAB_PIM` 외 제어 상태 정리 | hybrid 경로 지원 |
| 2 | 연산 타겟 enum 추가 | `src/PIMCmd.h` 또는 별도 공통 헤더 | 명령이 어느 PIM으로 갈지 표현 | instruction dispatch 필요 |

### 4.3 명령어와 디스패치 구조 수정

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | PIM 명령 타겟 추가 | `src/PIMCmd.h/.cpp` | 명령별 위치 정보 및 target field 추가 | bank-side와 logic-die 구분 |
| 1 | 명령 생성기 확장 | `src/tests/PIMCmdGen.h/.cpp` | MobileNetV4 블록별 명령 생성 가능하도록 확장 | 모델 연산 분해에 필요 |
| 2 | FUSE 명령 고려 | `src/PIMCmd.h/.cpp` | `CONV+ACT`, `ADD+ACT` 같은 fused op 지원 | 데이터 이동 감소 |
| 2 | host fallback 표시 | `src/PIMCmd.h/.cpp` | host 실행 필요 연산 표시 | 초기 범위 관리 |

### 4.4 PIM 실행 계층 분리

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | bank-side PIM 전용 계층 유지 | `src/PIMBlock.h/.cpp` | 기존 bank-side 연산 블록 유지 또는 정리 | 기존 기능 보존 |
| 1 | logic-die PIM 새 계층 추가 | 새 파일 후보: `src/LogicDiePIM.*` | logic-die용 연산기와 상태 분리 | 구조 분리 핵심 |
| 1 | 공통 상위 scheduler 추가 | 새 파일 후보: `src/PIMScheduler.*` | 어떤 연산을 어디로 보낼지 결정 | 하이브리드 실행의 핵심 |
| 2 | PIMRank 책임 축소 | `src/PIMRank.h/.cpp` | 현재는 control 중심으로 줄이고 실제 연산은 하위 모듈로 위임 | 유지보수성 향상 |

### 4.5 Rank와 MemoryController 연결 수정

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | rank가 logic-die 상태를 갖도록 확장 | `src/Rank.h/.cpp` | logic-die PIM 존재 여부와 상태 추적 | 모드 분리 필요 |
| 1 | bank-side와 logic-die 데이터 경로 분리 | `src/Rank.cpp`, `src/PIMRank.cpp` | bank-local read/write와 logic-die transfer를 분리 | 실제 하이브리드 핵심 |
| 2 | 큐와 스케줄링 정책 검토 | `src/MemoryController.cpp`, `src/CommandQueue.cpp` | logic-die 요청이 bank command와 충돌하지 않도록 조정 | 병목 방지 |
| 2 | bandwith/latency 통계 추가 | `src/MemoryController.cpp`, `src/MultiChannelMemorySystem.cpp` | logic-die 경로별 통계 기록 | 성능 비교용 |

### 4.6 시뮬레이터 상태와 통계 수정

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | 위치별 활성 상태 추적 | `src/Rank.*`, `src/PIMRank.*` | bank-side active / logic-die active 분리 | 디버깅과 성능 비교 필수 |
| 1 | 연산별 cycle 통계 | `src/tests/PIMKernel.*`, `src/MemoryController.*` | conv/add/relu 등 연산별 cycle 기록 | 모델별 비교 가능 |
| 2 | debug trace 확장 | `src/PrintMacros.*`, `system_hbm.ini` | logic-die 전용 trace 추가 | 동작 검증 지원 |
| 2 | verification output 확장 | `src/BusPacket.*`, `src/PIMRank.*` | RTL 연동 시 검증용 출력 고려 | 추후 Verilog 연동 대비 |

### 4.7 테스트와 벤치마크 추가

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | MobileNetV4 테스트 케이스 추가 | `src/tests/KernelTestCases.cpp` | 연산 블록별 functional test 추가 | 1차 검증 필요 |
| 1 | 하이브리드 경로 테스트 추가 | `src/tests/PIMBenchTestCases.cpp` | bank-side only / logic-die only / hybrid 비교 | 성능 비교 핵심 |
| 2 | 데이터 생성기 추가 | `data/` 및 생성 스크립트 | MobileNetV4 입력/가중치 샘플 추가 | 재현 가능성 확보 |
| 2 | 결과 비교 로직 추가 | `src/tests/TestCases.h` 계열 | 정확도 및 cycle 결과 비교 | regression test 필요 |

### 4.8 문서와 설계 산출물 정리

| 우선순위 | 수정 항목 | 대상 파일 | 내용 | 이유 |
|---|---|---|---|---|
| 1 | 설계 문서 누적 | `design/` | 기능표, 수정 항목표, 블록 매핑표 보관 | 코드와 분리 |
| 1 | 출처 명시 유지 | `design/*.md` | 논문/공식 구현/설계 해석 분리 | 나중에 검증 가능 |
| 2 | 가이드 문서 갱신 | `simulator_guide/` | 사용법, 구조 설명 업데이트 | 신규 인원 온보딩 |

## 5. 권장 수정 순서

1. 설정과 enum부터 추가한다.
2. PIM 명령에 target 정보를 넣는다.
3. logic-die PIM 계층을 새로 분리한다.
4. Rank와 MemoryController의 routing을 분리한다.
5. MobileNetV4 테스트를 추가한다.
6. bank-side only, logic-die only, hybrid 순으로 검증한다.

## 6. 1차 구현 범위 제안

### 6.1 먼저 구현할 것

- `ENABLE_LOGIC_DIE_PIM`
- `NUM_LOGIC_PIM_UNITS`
- `PIM_TARGET`
- `LogicDiePIM` 기본 클래스
- `PIMScheduler`
- `ADD`, `RELU`, `1x1 CONV`, `Depthwise CONV` 테스트

### 6.2 나중에 구현할 것

- fused op 확장
- `H-Swish`
- pooling
- host fallback 고도화
- detailed RTL verification output

## 7. 문서용 결론 문구

> 현재 시뮬레이터는 bank-side PIM 중심 구조이므로, logic-die PIM을 추가하려면 설정 파라미터, 명령 타겟, 실행 계층, rank routing, 테스트 케이스를 함께 분리해야 한다.  
> 단순히 연산 함수만 추가하는 방식으로는 bank-side와 logic-die의 동시 비교가 어렵기 때문에, 위치별 enable/latency/bandwidth를 포함한 구조적 수정이 필요하다.



