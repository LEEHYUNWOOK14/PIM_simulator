# B0/B1 Artifact Integrity and Reproducibility Audit

이 도구는 실행 중인 ORFS 결과를 읽지 않는다. 각 producer가 종료된 뒤 별도로
작성한 completion token이 있을 때만 파일 안정성 검사를 거쳐 snapshot을 만든다.
비교 및 HTML/CSV 생성은 live 결과가 아니라 snapshot JSON만 입력으로 사용한다.

## 1. Completion token

각 실험이 완전히 종료되고 결과 수집까지 끝난 뒤 다음 파일을 작성한다.

- `reports/b0_b1_artifact_audit/completion/b0.json`
- `reports/b0_b1_artifact_audit/completion/b1.json`

예시:

```json
{
  "status": "COMPLETE",
  "experiment_id": "b0",
  "producer_exit_code": 0,
  "completed_at": "2026-08-13T01:00:00+09:00",
  "comparison_context": {
    "workload_id": "bank-logic-common-workload-v1",
    "clock_period_ns": 10.0,
    "technology": "sky130hd",
    "library_id": "sky130_fd_sc_hd__tt_025C_1v80",
    "physical_options_id": "util30-ar1-margin2-density035"
  }
}
```

토큰은 실행 스크립트의 성공 exit 이후에만 기록해야 한다. 토큰보다 새 파일,
너무 최근에 수정된 파일, 안정성 확인 시간 동안 바뀐 파일이 하나라도 있으면
snapshot capture는 파일 내용을 읽지 않고 `PENDING` 처리한다.

## 2. 필요한 입력

프로필은 `design/b0_b1_artifact_audit_profile.json`에 있다. 각 case에 대해 다음을
요구한다.

- 공통 RTL source
- Yosys/OpenROAD version identity file
- Liberty/library SHA-256 identity file
- SDC
- workload/stimulus
- configuration
- functional, synthesis, physical, power artifact
- canonical metric CSV

`library_sha256.txt`에는 사용한 Liberty와 LEF의 SHA-256을 기록한다. tool identity
파일과 함께 B0/B1 digest가 다르면 비교는 자동으로 차단된다.

Metric CSV 형식은 다음과 같다.

```csv
metric,value,unit,evidence
area_um2,12345.6,um2,PLACED
critical_path_ns,12.3,ns,MEASURED
power_mw,4.5,mW,MEASURED
energy_pj_per_work,90.0,pJ/work,DERIVED
congestion_overflow,0,count,ROUTED
utilization_pct,30.0,%,PLACED
```

필수 metric, 단위, 유효 범위와 gate 기준은
`design/b0_b1_metric_schema.json`에서 관리한다. 필수 값이 없거나 범위를 벗어나거나
global-route overflow가 0이 아니면 완료된 case의 감사 결과는 `FAIL`이다. 프로필은
기능 CSV/log/VCD, 합성 netlist/STA, 최종 DEF/GDS/ODB와 power metric까지 명시적으로
검사한다.

## 3. 실행

실행 중에는 completion token이 없으므로 다음 명령은 live output을 열지 않고
`PENDING` snapshot만 생성한다.

```powershell
python tools/b0_b1_artifact_audit.py capture b0
python tools/b0_b1_artifact_audit.py capture b1
```

두 snapshot으로 JSON, CSV, HTML 보고서를 만든다.

```powershell
python tools/b0_b1_artifact_audit.py compare
```

출력:

- `reports/b0_b1_artifact_audit/snapshots/b0.json`
- `reports/b0_b1_artifact_audit/snapshots/b1.json`
- `reports/b0_b1_artifact_audit/comparison.json`
- `reports/b0_b1_artifact_audit/comparison.csv`
- `reports/b0_b1_artifact_audit/comparison.html`

두 snapshot 중 하나가 없거나 아직 실행 중이면 보고서는 `PENDING`이다. 모든
필수 metric이 있어도 workload, clock, technology/library, physical option 또는
source/tool/library/SDC/stimulus digest가 다르면 `NOT_COMPARABLE`이며 delta를
계산하지 않는다.

## 4. 검증

```powershell
python -m unittest verification.experiment_artifact_audit.test_b0_b1_artifact_audit -v
```

테스트는 임시 fixture만 사용하며 B0/B1 또는 공용 RTL/ORFS 산출물을 수정하지
않는다.
