# Floorplan optimization environment setup

## 설치 정책

대용량 EDA 바이너리, 빌드 트리, Python 가상환경 및 solver 임시 결과는 원격 데스크톱의 로컬 디스크에 둔다. OneDrive에는 소스, 설정, 작은 재현 로그와 논문 산출물만 둔다. 노트북에는 별도 설치하지 않는다.

- Windows 도구: `C:\Users\Admin\AppData\Local` 및 `C:\Users\Admin\AppData\Roaming\KLayout`
- Linux EDA 도구: WSL2 Ubuntu의 `/home/chandler/.local/stob-eda`
- 프로젝트: 현재 OneDrive 저장소
- GPU: NVIDIA GeForce RTX 4060 8 GB. Blender/ParaView 렌더링에 사용하며 HotSpot과 3D-ICE는 CPU solver로 분류한다.

## 설치된 도구

| 도구 | 버전/리비전 | 설치 위치 | 검증 |
|---|---|---|---|
| KLayout | 0.30.10 | `%APPDATA%\KLayout` | headless 실행 및 `gds3xtrude` Python 의존성 smoke 통과 |
| OpenSCAD | 2021.01 | `%LOCALAPPDATA%\Programs\OpenSCAD` | CLI version 통과 |
| Blender | 5.2.0 LTS | `%LOCALAPPDATA%\Programs\Blender` | background 실행 통과 |
| ParaView | 6.1.1 portable | `%LOCALAPPDATA%\STOB_EDA\ParaView` | `pvpython` 실행 통과 |
| Python | 3.11.9 | `%LOCALAPPDATA%\Programs\Python\Python311` | KLayout 3.11 ABI 의존성 설치에 사용 |
| OpenROAD | 26Q3-1080-gab6fd26351 | `/home/chandler/.local/stob-eda/openroad` | `-no_init -exit`, 공유 라이브러리 검사 통과 |
| Yosys | 0.68+48 | `/home/chandler/.local/oss-cad-suite` | version 실행 통과 |
| HotSpot | commit `f18831e48cef5d62580585cca0d7fab6c71bc3cc` | `/home/chandler/.local/stob-eda/src/HotSpot` | 공식 example1 steady/transient 실행 통과 |
| 3D-ICE | 4.0, commit `4953952a1ef6d38807ff307212a6f15e5b2ef935` | `/home/chandler/.local/stob-eda/src/3d-ice` | 공식 steady 예제 통과 |

3D-ICE Python 도구는 `/home/chandler/.local/stob-eda/venvs/3d-ice`에 격리했다. 검증 버전은 NumPy 2.5.2, Matplotlib 3.11.1, Shapely 2.1.2, Rtree 1.4.1, gdspy 1.6.13이다.

## 호환성 처리

3D-ICE 4.0에 포함되어 배포되는 SuperLU_MT 4.0.0은 Ubuntu 26.04의 GCC 15/C23 기본값과 바로 호환되지 않았다. 로컬 third-party 빌드 트리에 다음 최소 호환 설정을 적용했다.

1. C 언어 모드를 `gnu17`로 고정했다.
2. `sreadmt.c`의 구식 무인자 함수 선언을 명시적 prototype으로 변경했다.
3. 3D-ICE의 `long` 인덱스와 COLAMD long API가 LP64 Linux에서 일치하도록 `DLONG`과 `SuiteSparse_long=long`을 사용했다.
4. SuperLU 정적 라이브러리는 병렬 archive 경쟁을 피하기 위해 직렬 빌드했다.

이는 연구용 로컬 빌드 호환 조치이며 upstream signoff를 의미하지 않는다. 3D-ICE를 다시 내려받아 빌드할 때 동일 조치가 필요하다.

## 재현 및 점검

빠른 점검:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check_floorplan_toolchain.ps1
```

HotSpot과 3D-ICE 공식 예제를 포함한 점검:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check_floorplan_toolchain.ps1 -RunSolverExamples
```

기계 판독 결과는 `reports/floorplan_optimization/results/toolchain_smoke.json`에 기록한다. 이후 Phase 0 기준선 감사에서는 이 파일을 환경 evidence로 사용하되, PDK·설계별 OpenROAD flow 성공 여부는 별도 검증한다.

## 현재 경계

- KLayout은 GDS/overlay 시각화 수단이며 timing, thermal, routability 또는 PI signoff 도구가 아니다.
- OpenROAD는 공개 PDK 기반 연구용 물리 구현에 사용하며 HBM 제조 signoff로 표현하지 않는다.
- HotSpot과 3D-ICE 결과는 입력 전력의 evidence class를 상속한다. estimated power를 사용하면 절대 안전온도 결론을 내리지 않는다.
- 설치 완료는 floorplan 최적화 Phase 0~8 완료를 뜻하지 않는다.
