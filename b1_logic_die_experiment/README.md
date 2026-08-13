# B1 Logic-die Baseline Experiment Workspace

이 폴더는 `reports/baseline_b1_logic_die_experiment_plan.html`의 G0–G9 실험에
사용한 입력, 스크립트, 로그, 산출물 및 최종 보고서를 격리해 보관한다.

- 최종 보고서: `b1_logic_die_experiment_report.html`
- 기계 판독 manifest: `b1_baseline_manifest.json`
- 결과 표와 SHA-256: `metrics/`
- 기능/STA/power/route 로그: `logs/`
- netlist/VCD: `artifacts/`
- OpenROAD-flow-scripts 결과: `orfs/`

```sh
wsl -e bash b1_logic_die_experiment/run_functional.sh
wsl -e bash b1_logic_die_experiment/run_orfs.sh
wsl -e python3 b1_logic_die_experiment/collect_results.py
wsl -e python3 b1_logic_die_experiment/generate_report.py
```

정확 계획 구성은 `BANKS=1`, `DATA_WIDTH=16`이라 RTL 계약을 위반한다.
기능 경로는 유효한 최소 구성 `BANKS=2`, `DATA_WIDTH=32`에서 별도 검증했다.
상세 배선은 본 환경에서 OOM으로 중단됐으며 보고서는 이를 실패로 판정한다.
