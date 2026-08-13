# 실험 재현성 매니페스트 및 전체 회귀 게이트 보고서

## 1. 목적

현재 작업 트리의 핵심 RTL·normalization·하드웨어 비용·RTL-to-3D 검증을 동일한 명령 목록으로 다시 실행하고, 실행 시점의 소스·환경·결과 파일을 추적 가능하게 만드는 것이 목적이다.

이 보고서는 시각화 파이프라인과 mixed-precision 탐색의 설계 결론을 확정하지 않는다. 두 작업에서 생성된 현재 파일을 회귀 입력으로 소비했으며, 기존 사용자 변경은 되돌리지 않았다.

## 2. 추가된 산출물

| 산출물 | 역할 |
|---|---|
| `verification/reproducibility/regression_manifest.json` | 전체 게이트의 필수 명령과 분류를 정의 |
| `tools/run_full_regression_gate.py` | 명령 실행, timeout, exit code, stdout, PASS/FAIL 기록 |
| `tools/collect_reproducibility_manifest.py` | Git 상태, Python/OS 환경, 핵심 파일 SHA-256 기록 |
| `reports/reproducibility/regression_gate_20260811T123956Z.json` | 이번 실행의 상세 결과 |
| `reports/reproducibility/regression_gate_20260811T123956Z.csv` | 결과 요약표 |
| `reports/reproducibility/reproducibility_manifest_20260811T1240Z.json` | 이번 실행과 입력 파일의 재현성 메타데이터 |

## 3. 재현 명령

저장소 루트에서 다음을 실행한다.

```powershell
python tools/run_full_regression_gate.py --timeout 180
python tools/collect_reproducibility_manifest.py `
  --output reports/reproducibility/reproducibility_manifest_<timestamp>.json `
  --run-results reports/reproducibility/regression_gate_<run_id>.json
```

게이트는 필수 명령이 모두 `PASS`일 때만 `FULL_REGRESSION_GATE PASS`를 반환한다. 도구 미설치나 의존성 오류는 성공으로 간주하지 않는다.

## 4. 실제 실행 결과

실행 ID: `20260811T123956Z`

| 항목 | 분류 | 결과 |
|---|---|---|
| `rtl_to_3d_unit` | Python unit test | **FAIL** |
| `hardware_cost_unit` | Python unit test | PASS |
| `normalization_foundation_tests` | RTL test 및 foundation tests | PASS |
| `rtl_audit_regression` | RTL audit regression | PASS |
| 전체 게이트 | 필수 항목 종합 | **FAIL** |

### 실패 원인

`rtl_to_3d_unit`은 테스트 로더까지 도달했으나 `tools/run_hbm2_thermal.py` import 중 다음 의존성이 없어 실행되지 않았다.

```text
ModuleNotFoundError: No module named 'scipy'
```

따라서 이는 현재 RTL 기능 실패로 판정하지 않고, `scipy`가 없는 Python 환경에서 발생한 재현성 환경 실패로 기록한다. 다만 전체 게이트 기준에서는 필수 검증이 완료되지 않았으므로 FAIL이 맞다.

## 5. 매니페스트가 보존하는 정보

- 현재 branch와 `HEAD` commit
- 실행 당시 `git status --short`
- Python 버전, 실행 파일, OS 정보
- 게이트 결과 JSON의 SHA-256
- 게이트 도구와 회귀 매니페스트의 SHA-256
- 실행 명령, 시작 시각, 소요 시간, exit code, 전체 출력

Git 작업 트리가 dirty인 상태도 숨기지 않고 기록한다. 따라서 이 결과는 “clean checkout에서의 최종 sign-off”가 아니라, 현재 작업 트리 snapshot에 대한 재현 결과다.

## 6. 판정 및 후속 조치

- 정상 통과로 확인된 영역: hardware-cost unit, normalization foundation, RTL audit.
- 전체 통과를 막는 항목: `rtl_to_3d_unit`의 `scipy` 의존성.
- 다음 조치: 프로젝트의 승인된 Python 환경에 `requirements.txt`의 과학계산 의존성을 설치하거나 해당 환경을 선택한 뒤, 동일한 게이트 명령을 재실행한다.
- `rtl_to_3d_unit`이 PASS하기 전까지 전체 회귀 게이트와 논문용 최종 회귀 상태를 PASS로 표시하지 않는다.

이번 작업에서는 의존성 설치나 기존 결과 삭제를 수행하지 않았다.

## 7. scipy 설치 후 재실행 결과

`requirements.txt`에 지정된 `scipy==1.16.1`을 현재 사용자 Python 환경에 설치한 뒤 게이트를 재실행했다.

최종 실행 ID: `20260811T130307Z`

| 항목 | 결과 |
|---|---|
| `rtl_to_3d_unit` | PASS |
| `hardware_cost_unit` | PASS |
| `normalization_foundation_tests` | FAIL_SEMANTIC_MARKER |
| `rtl_audit_regression` | PASS |
| 전체 게이트 | **FAIL** |

이번에는 환경 의존성 문제는 해소되었다. normalization foundation의 개별 RTL 테스트와 mixed-precision trace 케이스는 실행되었고, 대부분 `PASS`를 출력했다. 그러나 `run_groot_actual_trace_bf16_test.sh`가 다음을 출력했다.

```text
GROOT_RTL_ACCURACY_ANALYSIS result=FAIL passed=1 failed=5 threshold=0.025
```

기존 스크립트가 이후 `GROOT_ACTUAL_TRACE_BF16_REGRESSION PASS`를 출력하고 종료 코드 0을 반환했지만, 게이트 실행기는 명시적인 `result=FAIL`을 의미적 실패로 감지하도록 보강했다. 따라서 이 결과를 전체 PASS로 기록하지 않았다.

최종 증거 파일:

- `reports/reproducibility/regression_gate_20260811T130307Z.json`
- `reports/reproducibility/regression_gate_20260811T130307Z.csv`
- `reports/reproducibility/reproducibility_manifest_20260811T1310Z.json`

결론적으로 `scipy` 설치 작업은 완료되었고 RTL-to-3D 회귀는 복구되었지만, 실제 BF16 trace 정확도 분석에서 5개 profile이 기준 `0.025`를 충족하지 못해 전체 회귀 게이트는 아직 PASS가 아니다.

## 8. BF16 actual-trace 정확도 해결 후 최종 상태

legacy all-BF16 내부 datapath의 반복 반올림이 정확도 실패 원인임을 확인했다. 외부 BF16 형식을 유지하면서 내부 reduction, scalar 및 fused affine을 FP32로 수행하고 최종 BF16 RNE를 한 번 적용하는 C11 경로를 canonical actual-trace gate로 연결했다.

최종 정확도:

- 6/6 profile PASS
- 1,909,248 elements
- C11 model 대비 RTL mismatch 0
- PyTorch BF16 bit mismatch 37
- overall max abs 0.015625
- 기준 0.025

최종 전체 게이트 실행 ID는 `20260811T145903Z`이며 네 필수 항목이 모두 PASS했다.

| 항목 | 최종 결과 |
|---|---|
| `rtl_to_3d_unit` | PASS |
| `hardware_cost_unit` | PASS |
| `normalization_foundation_tests` | PASS |
| `rtl_audit_regression` | PASS |
| 전체 게이트 | **PASS** |

최종 증거는 `regression_gate_20260811T145903Z.json`과 `reproducibility_manifest_20260812T0018KST.json`에 기록했다.
