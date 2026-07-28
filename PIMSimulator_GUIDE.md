# PIMSimulator 프로젝트 설명서

> 이 프로젝트는 **STOB리그 반도체 분야 6번 문제(PIM)**를 해결하기 위한 시뮬레이션 기반 프로젝트다.

## 1. 프로젝트 개요

`PIMSimulator`는 HBM2 기반 **프로세서-인-메모리(Processing-in-Memory, PIM)** 시스템을 사이클 단위로 모델링하는 C++ 시뮬레이터다. 호스트가 발행하는 일반 메모리 트랜잭션과 DRAM 내부에서 수행되는 PIM 연산을 하나의 메모리 시스템 안에서 함께 시뮬레이션하며, 채널·랭크·뱅크·뱅크 상태·버스·명령 큐·전력 및 지연 통계를 모델링한다.

이 저장소의 출발점은 [DRAMSim2](https://github.com/umd-memsys/DRAMSim2)이며, 여기에 PIM 블록과 PIM 커널 생성 로직이 확장되어 있다.

주요 목적은 다음과 같다.

- HBM2의 채널 및 뱅크 병렬성을 이용한 PIM 실행 평가
- PIM 명령어와 메모리 명령어 사이의 사이클 수준 동작 검증
- GEMV(행렬-벡터 곱), element-wise ADD/MUL/RELU 기능 검증
- 처리량, 지연시간, 뱅크 사용량, 전력 등의 성능 분석
- 실제 PIM 커널이 생성한 메모리 트레이스를 시뮬레이터에서 재생

## 2. 출제 문제 6번과 프로젝트의 관계

### 문제 요약

출제 문제 6번의 문제명은 **PIM**이다. AI 추론을 위한 차세대 메모리로 PIM을 활용하는 것을 전제로 다음 과제를 요구한다.

- 실제 엣지 서버 및 온디바이스 환경에서 PIM을 제품 수준으로 적용할 때의 기술적 장벽과 난제를 정의한다.
- 특정 소수의 애플리케이션에만 유리한 구조가 아니라, 일반적인 서버·엣지 장치에서 다양한 AI 워크로드를 처리할 수 있는 범용 PIM 아이디어를 제안한다.
- 신규 메모리 구조, 신규 PIM 구조, 메모리 컨트롤러 및 인터페이스 구조를 설계한다.
- 제안 구조의 아키텍처, 설계 데이터베이스, PPA(성능·전력·면적) 분석 모델을 제시한다.
- 개선된 애플리케이션·워크로드와 소프트웨어/펌웨어를 구현하고 시뮬레이션으로 효과를 증명한다.

### 이 저장소가 담당하는 부분

이 저장소는 위 과제의 하드웨어 및 메모리 시스템 검증을 위한 **사이클 정확도 PIM 시뮬레이터**다. HBM2 메모리 컨트롤러, 주소 매핑, 뱅크 병렬성, PIM 명령 실행, 메모리 트랜잭션을 통합적으로 모델링하므로 다음과 같은 비교 실험의 기반으로 사용할 수 있다.

1. 일반 DRAM 접근과 PIM 연산의 실행 사이클 및 메모리 트래픽 비교
2. 채널 수와 뱅크 병렬성 변화에 따른 처리량 및 지연시간 비교
3. GEMV와 element-wise 연산을 통한 AI 워크로드의 PIM 가속 효과 측정
4. PIM 연산의 ALU 에너지와 메모리 동작 전력을 포함한 전력 분석
5. 메모리 컨트롤러 스케줄링, 주소 매핑, 큐 구조 및 PIM 인터페이스 개선안의 검증

따라서 이 프로젝트 자체가 최종 신규 PIM 제품 구조 전체를 의미하는 것은 아니며, 문제 6번에서 제안할 아키텍처와 개선 아이디어를 정량적으로 비교·검증하기 위한 모델 및 실험 기반으로 이해할 수 있다.

## 3. 하드웨어 및 실행 모델

기본 데이터 경로는 다음과 같다.

```text
HOST
  │ 일반 Read/Write 또는 PIM용 Write/Read
  ▼
MultiChannelMemorySystem
  │ 주소의 채널 필드로 분배
  ▼
MemoryController × NUM_CHANS
  │ 트랜잭션 큐 → DRAM 명령 큐 → 버스
  ▼
Rank / PIMRank
  │ HBM2 DRAM 동작과 PIM 모드 제어
  ▼
PIMBlock × NUM_PIM_BLOCKS
  │ CRF, GRF, SRF 및 ALU
  ▼
ADD / MUL / MAC / MAD / MOV / FILL / 제어 명령
```

각 채널은 독립적인 메모리 컨트롤러를 가지며, 시뮬레이터는 HBM2의 pseudo-channel 독립성을 가정한다. 기본 HBM2 모델은 16개 논리 채널, 64-bit 데이터 버스, 16개 뱅크와 8개 PIM 블록을 사용한다. PIM 블록 배치는 `NUM_BANKS / NUM_PIM_BLOCKS` 관계로 결정되며, 기본 설정에서는 PIM 블록 하나가 두 뱅크에 대응한다.

### 주소 매핑

PIM 기능은 `Scheme8` 주소 매핑을 전제로 한다.

```text
| rank | row | column high | bank group | bank | channel | column low | offset |
```

주소의 채널·랭크·뱅크·행·열 필드는 `AddressMapping`이 분해한다. PIM 트랜잭션에서는 뱅크 주소가 어떤 뱅크 그룹의 데이터를 읽거나 어떤 PIM 블록이 partial sum을 반환할지 결정하는 데 사용된다.

## 4. PIM 명령어 구조

PIM 명령은 32-bit RISC 스타일로 인코딩되며 `PIMCmd`가 정수형 명령과 구조화된 명령 사이의 변환 및 유효성 검사를 담당한다.

| 분류 | 명령 | 역할 |
|---|---|---|
| 산술 | `ADD` | 두 피연산자의 덧셈 |
| 산술 | `MUL` | 곱셈 |
| 산술 | `MAC` | 곱셈 후 누산 |
| 산술 | `MAD` | 곱셈 후 덧셈 |
| 데이터 이동 | `MOV` | 레지스터와 뱅크 사이 데이터 이동 |
| 데이터 이동 | `FILL` | 뱅크 데이터를 레지스터로 채움/자동 이동 |
| 제어 | `NOP` | 아무 동작도 수행하지 않음 |
| 제어 | `JUMP` | 미리 정해진 반복을 위한 정적 분기 |
| 제어 | `EXIT` | PIM 명령 시퀀스 종료 |

피연산자는 GRF-A, GRF-B 벡터 레지스터, SRF 스칼라 레지스터, 뱅크 행 버퍼를 사용할 수 있다. `PIMRank`는 Command Register File(CRF)의 PC를 관리하고, DRAM 명령이 PIM 실행을 트리거할 때 명령을 읽어 각 `PIMBlock`에 전달한다. `PIMBlock`은 설정된 `PIM_PRECISION`에 따라 FP16, INT8 또는 FP32 산술을 수행한다.

## 5. DRAM/PIM 동작 모드

PIM 커널은 일반적으로 다음 순서로 실행된다.

1. 입력 데이터를 DRAM에 배치한다.
2. 일반 메모리 모드 `SB`에서 HAB 모드로 전환한다.
3. `programCrf()`로 PIM 명령을 CRF에 기록한다.
4. `HAB_PIM` 모드로 전환해 PIM을 활성화한다.
5. PIM용 트랜잭션으로 연산을 실행한다.
6. `HAB`로 돌아가 PIM을 비활성화한다.
7. 다시 `SB`로 전환하고 결과를 읽는다.

개념적으로 메모리 API는 다음과 같이 사용한다.

```cpp
mem->addTransaction(false, address, tag, &buffer); // read
mem->addTransaction(true,  address, tag, &buffer); // write 또는 PIM write
```

PIM 실행에 사용하는 write 데이터는 채널의 여러 PIM 블록으로 브로드캐스트될 수 있으며, `read_pim` 동작은 PIM 블록에 누적된 partial sum을 호스트 방향으로 반환한다.

## 6. 주요 소스 디렉터리

| 경로 | 설명 |
|---|---|
| `src/MemorySystem.*` | 단일 메모리 시스템과 트랜잭션 진입점 |
| `src/MultiChannelMemorySystem.*` | 여러 채널의 생성, 분배, 전체 통계 집계 |
| `src/MemoryController.*` | 트랜잭션 큐, 명령 스케줄링, refresh, 버스 및 통계 |
| `src/Rank.*`, `src/Bank.*`, `src/BankState.*` | DRAM 랭크·뱅크 상태 및 명령 처리 |
| `src/PIMRank.*` | PIM 모드 전환, CRF 실행, PIM 블록 연결 |
| `src/PIMBlock.*` | 벡터 산술 및 레지스터 동작 |
| `src/PIMCmd.*` | PIM 명령 인코딩, 디코딩, 검증 |
| `src/AddressMapping.*` | 호스트 주소의 채널/랭크/뱅크/행/열 분해 |
| `src/tests/PIMKernel.*` | GEMV 및 element-wise PIM 커널 절차 |
| `src/tests/PIMCmdGen.*` | PIM ISA 명령 생성 |
| `src/tests/KernelTestCases.cpp` | 기능 검증용 테스트 케이스 |
| `src/tests/PIMBenchTestCases.cpp` | 성능 측정용 테스트 케이스 |
| `tools/emulator_api/` | 외부 PIM SDK/호스트에서 발생한 trace 재생 API |
| `ini/` | HBM2 장치 타이밍 및 구조 설정 |
| `system_*.ini` | 채널 수, 주소 매핑, 디버그 및 출력 설정 |
| `data/` | GEMV, ADD, MUL, RELU의 입력·정답 NPY 데이터 |
| `dump/` | 트레이스/바이너리 데이터 예시 |

## 7. 빌드

필요 도구는 SCons, C++14 컴파일러, GoogleTest 개발 패키지다. Ubuntu 기준:

```bash
sudo apt install scons libgtest-dev
scons
```

`Sconstruct`는 기본적으로 `-g -O2 -std=c++14 -Wall` 옵션을 사용하고, 빌드 결과를 다음 위치에 만든다.

- 실행 파일: `sim`
- 변형 빌드 소스/오브젝트: `bin/`
- 정적·공유 라이브러리: `libdramsim/dramsim2`

기본 빌드는 테스트와 emulator API 소스를 함께 포함한다. 다음 옵션을 사용할 수 있다.

```bash
scons NO_STORAGE=1  # 메모리 데이터 저장/검증을 생략하는 no-data 빌드
scons NO_EMUL=1     # emulator API 소스 제외
scons NO_LIBRARY=1  # 라이브러리 생성 제외
```

## 8. 테스트 및 벤치마크

테스트 목록은 다음 명령으로 확인한다.

```bash
./sim --gtest_list_tests
```

대표 테스트:

```bash
./sim --gtest_filter=PIMKernelFixture.gemv  # GEMV 기능 검증
./sim --gtest_filter=PIMKernelFixture.mul   # MUL 기능 검증
./sim --gtest_filter=PIMKernelFixture.add   # ADD 기능 검증
./sim --gtest_filter=PIMKernelFixture.relu  # RELU 기능 검증

./sim --gtest_filter=PIMBenchFixture.gemv  # GEMV 성능 측정
./sim --gtest_filter=PIMBenchFixture.add   # ADD 성능 측정
./sim --gtest_filter=MemBandwidthFixture.hbm_read_bandwidth
```

기능 테스트는 `data/`의 NPY 입력 및 기대 결과를 사용해 결과를 검증한다. 다른 텐서 크기를 시험하려면 각 `data/*/gen_*.py` 생성기를 수정·실행하고, 생성된 크기를 `src/tests/KernelTestCases.cpp`에 반영해야 한다.

## 9. 설정 파일

실행 시 사용할 시스템 설정과 HBM 장치 설정을 구분한다.

- `system_hbm.ini`: 16채널 기본 구성
- `system_hbm_1ch.ini`: 단일 채널 실험
- `system_hbm_64ch.ini`: 64채널 실험
- `ini/HBM2_samsung_2M_16B_x64.ini`: HBM2 장치 타이밍·용량·뱅크 구성

자주 조정하는 항목은 다음과 같다.

| 항목 | 의미 |
|---|---|
| `NUM_CHANS` | 논리적으로 독립된 메모리 채널 수 |
| `JEDEC_DATA_BUS_BITS` | 데이터 버스 폭 |
| `TRANS_QUEUE_DEPTH`, `CMD_QUEUE_DEPTH` | 호스트 트랜잭션 및 DRAM 명령 큐 깊이 |
| `ADDRESS_MAPPING_SCHEME` | 주소 디코딩 방식; PIM은 `Scheme8` 권장 |
| `ROW_BUFFER_POLICY` | open-page 또는 close-page 정책 |
| `SCHEDULING_POLICY` | 랭크/뱅크 명령 스케줄링 정책 |
| `QUEUING_STRUCTURE` | 큐를 랭크 단위 또는 뱅크 단위로 구성하는 방식 |
| `PIM_PRECISION` | `FP16`, `INT8`, `FP32` |
| `DEBUG_PIM_TIME`, `DEBUG_CMD_TRACE`, `DEBUG_PIM_BLOCK` | PIM 디버그 출력 |
| `PRINT_CHAN_STAT`, `PRINT_MEM_TRACE` | 채널 통계 및 메모리 trace 출력 |
| `SIM_TRACE_FILE` | trace 출력 파일명 |

## 10. 통계와 검증

`MemoryController`와 `MultiChannelMemorySystem`은 트랜잭션 수, 전송 바이트, 채널/랭크/뱅크별 대역폭, 평균 지연시간, refresh 횟수, 행 활성화, 뱅크 접근량을 집계한다. 또한 burst, activate/precharge, refresh, ALU-PIM 에너지 및 평균 전력을 계산한다.

`VERIFICATION_OUTPUT`과 `DEBUG_*` 설정은 개발 및 디버깅 시 유용하지만 출력량이 크게 늘 수 있다. 성능 비교 실험에서는 설정 파일, 채널 수, precision, 입력 크기, 빌드 옵션을 고정하고 trace 및 통계 출력 여부도 함께 기록하는 것이 좋다.

## 11. Emulator API

`tools/emulator_api`는 실제 머신에서 PIM 커널을 실행하는 대신 커널의 메모리 trace를 기록하고, 그 trace를 PIMSimulator에 입력해 시뮬레이션하는 경로를 제공한다. `PimSimulator`는 메모리 시스템과 `PIMKernel`을 초기화하고, trace 입력을 트랜잭션으로 변환하며, PIM 출력 버스트를 수집한다.

이 경로를 사용하면 호스트 애플리케이션의 커널 호출 순서와 메모리 접근을 시뮬레이터의 cycle-accurate DRAM/PIM 모델로 연결할 수 있다.

## 12. 작업을 시작할 때 참고할 파일

새 PIM 연산이나 실험을 추가할 때는 다음 순서로 읽는 것이 효율적이다.

1. `src/tests/PIMKernel.cpp`: 전체 PIM 실행 순서와 주소 계산
2. `src/tests/PIMCmdGen.h/.cpp`: 명령어 생성 방식
3. `src/PIMCmd.h/.cpp`: 명령 인코딩과 피연산자 제약
4. `src/PIMRank.cpp`: CRF 실행 및 DRAM/PIM 데이터 이동
5. `src/PIMBlock.cpp`: 실제 산술 의미
6. `src/tests/PIMBenchTestCases.cpp`: 성능 측정 방식
7. `system_hbm*.ini` 및 `ini/HBM2_samsung_2M_16B_x64.ini`: 실험 조건

새 동작은 먼저 작은 단일 채널 기능 테스트로 검증한 뒤, 16/64채널 설정에서 성능과 병렬성을 비교하는 방식이 안전하다.

## 13. 라이선스 및 원본

저장소에는 `LICENSE-PIMSimulator`와 `LICENSE-DRAMSIM2`가 함께 포함되어 있다. PIMSimulator 확장 코드와 DRAMSim2 기반 코드의 사용·배포 시 각 라이선스 조건을 확인해야 한다.
