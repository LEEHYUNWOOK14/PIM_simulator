# PIMSimulator

## 프로젝트 소개

### HBM2 PIM 아키텍처 시각화

진행 중인 RTL 수정과 독립적으로, 출처 추적 가능한 HBM2 8Hi 아키텍처 모델을 생성하고 검증할 수 있다.

```powershell
.\tools\generate_hbm2_architecture.ps1
```

결과는 `output/hbm2_arch/`에 분리된다. 출처, 검증, KLayout/OpenSCAD 사용법과 non-signoff 한계는 `design/hbm2_architecture_model.md`를 참고한다.

이 프로젝트는 **STOB리그 반도체 분야 6번 문제(PIM)**를 해결하기 위해 개발한 HBM2 기반 프로세서-인-메모리(PIM) 시뮬레이터다.

PIM은 메모리 내부 또는 메모리 가까이에 연산 기능을 배치해 메모리와 프로세서 사이의 데이터 이동을 줄이는 기술이다. 이 저장소는 DRAMSim2를 기반으로 메모리 시스템과 PIM 블록을 통합하고, PIM 연산의 실행 사이클·메모리 트래픽·지연시간·대역폭·전력을 시뮬레이션한다.

출제 문제 6번은 다음을 요구한다.

- 엣지 서버와 온디바이스 환경에서 PIM을 제품 수준으로 적용할 때의 기술적 장벽 분석
- 특정 애플리케이션에 한정되지 않는 범용 PIM 구조 제안
- 신규 메모리, PIM, 메모리 컨트롤러 및 인터페이스 구조 설계
- 성능·전력·면적(PPA) 분석과 개선된 AI 워크로드의 시뮬레이션 검증

이 프로젝트는 위 요구사항 중 메모리/PIM 아키텍처와 메모리 컨트롤러의 동작을 정량적으로 비교·검증하기 위한 실험 기반이다.

## 주요 기능

- HBM2 메모리 시스템의 사이클 정확도 시뮬레이션
- 다중 채널과 뱅크 수준 병렬성 모델링
- PIM 명령 레지스터 파일(CRF), 벡터 레지스터(GRF), 스칼라 레지스터(SRF) 모델링
- PIM 산술 명령: `ADD`, `MUL`, `MAC`, `MAD`
- 데이터 이동 명령: `MOV`, `FILL`
- 제어 명령: `NOP`, `JUMP`, `EXIT`
- GEMV(행렬-벡터 곱) 및 element-wise `ADD`, `MUL`, `RELU` 검증
- 메모리 대역폭, 지연시간, 뱅크 사용량 및 PIM 전력 통계 수집
- PIM 커널 메모리 trace를 재생하는 Emulator API

## 구조

```text
호스트
  ↓ 메모리 트랜잭션
다중 채널 메모리 시스템
  ↓ 채널별 분배
메모리 컨트롤러
  ↓ DRAM 명령 및 버스 처리
랭크 / PIM 랭크
  ↓ PIM 모드 제어와 CRF 실행
PIM 블록
  ↓ 벡터 산술 및 데이터 이동
PIM 결과
```

PIM 실행은 일반적으로 다음 순서로 진행된다.

1. 입력 데이터를 DRAM에 저장한다.
2. 일반 메모리 모드에서 HAB 모드로 전환한다.
3. PIM 명령을 CRF에 기록한다.
4. PIM 모드를 활성화한다.
5. 메모리 트랜잭션으로 PIM 연산을 실행한다.
6. PIM 모드를 비활성화하고 일반 메모리 모드로 돌아온다.
7. 결과를 읽고 기능 및 성능을 검증한다.

## 디렉터리 안내

| 경로 | 설명 |
|---|---|
| `src/` | 메모리 시스템, 컨트롤러, DRAM, PIM 구현 |
| `src/tests/` | PIM 커널, 명령 생성기, 기능·성능 테스트 |
| `tools/emulator_api/` | PIM 메모리 trace 재생 API |
| `ini/` | HBM2 장치 타이밍 및 구조 설정 |
| `system_*.ini` | 채널 수, 주소 매핑, 디버그 및 출력 설정 |
| `data/` | GEMV, ADD, MUL, RELU 테스트 데이터 |
| `dump/` | 예시 trace 및 바이너리 데이터 |
| `PIMSimulator_GUIDE.md` | 프로젝트 구조와 사용법 상세 설명 |

## 빌드

Ubuntu 환경에서는 SCons와 GoogleTest 개발 패키지를 설치한다.

```bash
sudo apt install scons libgtest-dev
scons
```

빌드 결과는 다음과 같다.

- 실행 파일: `sim`
- 빌드 중간 파일: `bin/`
- 라이브러리: `libdramsim/dramsim2`

선택 사항:

```bash
scons NO_STORAGE=1  # 데이터 저장 및 기능 검증을 생략하는 모드
scons NO_EMUL=1     # Emulator API 제외
scons NO_LIBRARY=1  # 라이브러리 생성 제외
```

## 테스트 실행

```bash
./sim --gtest_list_tests
```

대표적인 기능 및 성능 테스트:

```bash
./sim --gtest_filter=PIMKernelFixture.gemv
./sim --gtest_filter=PIMKernelFixture.mul
./sim --gtest_filter=PIMKernelFixture.add
./sim --gtest_filter=PIMKernelFixture.relu

./sim --gtest_filter=PIMBenchFixture.gemv
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=MemBandwidthFixture.hbm_read_bandwidth
```

## 설정

- `system_hbm.ini`: 16채널 기본 구성
- `system_hbm_1ch.ini`: 단일 채널 실험
- `system_hbm_64ch.ini`: 64채널 실험
- `ini/HBM2_samsung_2M_16B_x64.ini`: HBM2 장치 파라미터

PIM 기능에는 `ADDRESS_MAPPING_SCHEME=Scheme8`을 권장한다. `PIM_PRECISION`으로 `FP16`, `INT8`, `FP32` 정밀도를 선택할 수 있으며, `DEBUG_*`, `PRINT_CHAN_STAT`, `PRINT_MEM_TRACE` 항목으로 디버그 및 통계 출력을 조절한다.

## 상세 문서

전체 하드웨어 모델, PIM 명령어 구조, 메모리 트랜잭션 API, Emulator API, 성능 통계 및 새로운 PIM 연산 추가 방법은 [PIMSimulator 프로젝트 설명서](PIMSimulator_GUIDE.md)를 참고한다.

## 원본 및 라이선스

이 프로젝트는 [DRAMSim2](https://github.com/umd-memsys/DRAMSim2)를 기반으로 확장되었다. 자세한 라이선스 조건은 `LICENSE-PIMSimulator`와 `LICENSE-DRAMSIM2`를 확인한다.


# HBM2 thermal analysis

The RTL-independent HBM2 PIM power-to-temperature workflow is documented in [docs/HBM2_THERMAL_ANALYSIS.md](docs/HBM2_THERMAL_ANALYSIS.md).

The source-traceable area/package/yield/power-performance cost workflow is documented in [hardware_cost/README.md](hardware_cost/README.md).
