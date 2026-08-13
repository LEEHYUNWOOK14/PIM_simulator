# B0 Bank-only baseline experiment

**최종 상태 (2026-08-13):** 10/10 Gate 실행 완료 —
`COMPLETE_WITH_FEASIBILITY_VIOLATIONS`. 기능과 GDS 생성은 완료됐지만 10 ns setup
timing 및 route DRC는 미달했다. 상세 결과는
[`report/b0_experiment_report.html`](report/b0_experiment_report.html)에 있다.

이 디렉터리는 `full_pim_system_top`의 B0 구성을 독립적으로 검증하는 전용
workspace다. 저장소의 공용 `rtl/`과 EDA 설치는 입력으로만 참조하고, B0 실험에서
생성하는 설정, testbench, 로그, netlist, physical artifact, power 결과와 최종
보고서는 모두 이 디렉터리에 보존한다.

## B0 architecture

```text
ENABLE_LOGIC_DIE_PCU=0
ENABLE_NORMALIZATION_ENGINE=0

DRAM bank -> Bank-side PCU -> local result arbiter -> direct TSV/host path
```

## Directory contract

| 경로 | 용도 |
|---|---|
| `plan/` | 실행 계획과 진행 상태의 authoritative copy |
| `config/` | 동결 parameter, source/tool manifest, SDC, ORFS configuration |
| `tb/` | B0 전용 self-checking testbench와 workload stimulus |
| `scripts/` | 기능, 합성, STA, physical, power 및 audit 실행기 |
| `results/functional/` | 기능 회귀 로그, CSV, VCD |
| `results/synthesis/` | generic 및 Sky130 mapped netlist/report |
| `results/physical/` | floorplan, placement, CTS, route, DEF/GDS 및 metrics |
| `results/power/` | activity와 power/energy 결과 |
| `manifest/` | 입력·출력 hash, tool version, gate 상태 |
| `report/` | 최종 HTML 실험 보고서 |

## Isolation rule

- 공용 `rtl/`, `flow/`, 기존 `experiment/results/`의 결과를 덮어쓰지 않는다.
- B0 출력은 반드시 `b0_baseline_experiment/results/` 아래에 둔다.
- ORFS를 사용할 때도 별도 `DESIGN_NICKNAME`을 사용하고 결과를 이 디렉터리로
  복사하여 hash와 함께 동결한다.
- B1과 비교하기 전 source/tool/library/SDC/stimulus manifest의 동일성을 감사한다.

## Progress rule

각 Gate가 끝날 때 `plan/b0_experiment_plan.html`의 상태, 측정값, artifact 경로,
hash, 실패/제한 사항과 Progress Log를 즉시 갱신한다. 모든 Gate가 끝나면
`report/b0_experiment_report.html`을 작성한다.
