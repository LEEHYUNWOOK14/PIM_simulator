# GDS merge 및 좌표 변환 환경 설정

## 상태

`PASS` — 전용 환경은 OneDrive가 아닌 데스크톱 로컬 경로에 설치했다.

```text
C:\Users\Admin\AppData\Local\STOB_EDA\gds-merge
```

최종 RTL route/GDS 병합기를 구현하기 위한 실행 기반만 설정한 단계이며, production GDS 자동 병합기 자체를 완료했다는 의미는 아니다.

## 설치 구성

| 구성 | 버전/위치 | 역할 |
|---|---|---|
| Python | 3.11.9, local venv | 병합 orchestration |
| KLayout GUI | 0.30.10 | GDS/OASIS 계층·레이어 확인 및 렌더 |
| KLayout Python DB API | 0.30.10 | headless GDS read/write·DBU·hierarchy 검증 |
| gdstk | 0.9.61 | 빠른 GDS 생성·reference transform·merge |
| NumPy | 2.3.2 | affine matrix 및 수치 검증 |
| Shapely | 2.1.1 | polygon overlap·clearance·boundary 검사 |
| jsonschema | 4.25.0 | merge/transform 입력 계약 검증 기반 |
| PyYAML | 6.0.2 | layer-map/merge recipe 입력 기반 |
| Pillow | 11.3.0 | 검증 이미지 후처리 기반 |
| OpenROAD | 26Q3-1080, WSL | 최종 ODB/DEF 및 routed physical snapshot 공급 |

고정 버전 목록은 `tools/gds_merge_requirements.txt`에 있다.

## 영구 사용자 환경 변수

```text
STOB_GDS_MERGE_HOME=C:\Users\Admin\AppData\Local\STOB_EDA\gds-merge
STOB_GDS_MERGE_PYTHON=C:\Users\Admin\AppData\Local\STOB_EDA\gds-merge\venv\Scripts\python.exe
STOB_KLAYOUT_EXE=C:\Users\Admin\AppData\Roaming\KLayout\klayout_app.exe
STOB_OPENROAD_WSL=/home/chandler/.local/stob-eda/openroad/bin/openroad
```

새 PowerShell에서 다음을 실행하면 전용 venv를 현재 세션 PATH 앞에 추가한다.

```powershell
. .\tools\enter_gds_merge_environment.ps1
```

재설치·복구 명령은 다음과 같다.

```powershell
.\tools\setup_gds_merge_environment.ps1
```

## Smoke 검증

`tools/check_gds_merge_environment.py`가 다음을 실제 수행했다.

1. 독립 RTL fixture GDS와 TSV overlay fixture GDS 생성
2. 두 GDS를 별도 파일에서 재로딩
3. RTL cell에 90° 회전과 `(1000, 2000) µm` 이동 적용
4. TSV cell에 `(1025, 2050) µm` 이동 적용
5. hierarchy를 유지한 `GDS_MERGE_TRANSFORM_SMOKE_TOP` 생성
6. KLayout DB API로 metal layer 10과 TSV layer 120 shape count 확인
7. 최종 bbox와 Shapely polygon clearance 20 µm 확인

결과:

```text
status: PASS
bbox_dbu: [950000, 2000000, 1030000, 2100000]
metal shapes: 1
TSV shapes: 1
clearance: 20.0 um
```

병합 smoke GDS는 로컬의 `C:\Users\Admin\AppData\Local\STOB_EDA\gds-merge\smoke\merged_transform_smoke.gds`에 있으며, SHA-256과 패키지 버전은 `reports/floorplan_optimization/results/gds_merge_environment_smoke.json`에 기록했다.

## 다음 구현 경계

환경은 준비됐지만 실제 자동 병합을 위해서는 final-physical input schema, foundry layer map, DBU/origin/orientation normalization, top-cell 충돌 처리, PHY/TSV anchor 정렬 및 병합 후 검증 도구가 추가로 필요하다. 최종 RTL을 기다리지 않고 synthetic fixture로 구현할 수 있다.
