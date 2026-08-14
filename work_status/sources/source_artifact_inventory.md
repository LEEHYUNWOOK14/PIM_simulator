# Source artifact inventory

수집 시점: 2026-08-14 UTC

이 표는 `archive/` 수집본과 기존 canonical source/provenance 파일의 대응을 기록합니다. 같은 hash는 내용이 동일한 snapshot임을 의미합니다.

| 수집본 | 원본 경로 | 원본 SHA-256 | 크기(byte) |
|---|---|---:|---:|
| `archive/hbm2_sources.json` | `references/hbm2/SOURCES.json` | `e65772775175703fab646343e7ee336b628f653a35d8b05290ba65c60964d293` | 1,129 |
| `archive/thermal_sources.md` | `references/thermal/SOURCES.md` | `237155c80d27e5dda0c5e870f61d5ce9e12bfce08e7af1244cc26e31678be15e` | 1,013 |
| `archive/hardware_cost_sources.json` | `hardware_cost/sources.json` | `fea957d7ec71a7bb7dc2535389a5c4acfb5e6f830ab927fa32aaf174a50f4185` | 8,199 |
| `archive/groot_placement_sources.json` | `experiment/gr00t_placement/sources.json` | `6e83c853ac0d60b5390142d31179b20dbabb731d9fe10abf17dba4ffc33487b1` | 8,072 |
| `archive/normalization_source_evidence.csv` | `reports/groot_normalization/results/full_normalization_inventory/source_evidence.csv` | `6d605d2204892ad66b4d1e469919d74114626ab2db5a22c32a9acb90481d9438` | 1,445 |
| `archive/normalization_reference_architecture_comparison.csv` | `reports/groot_normalization/results/reference_architecture_comparison.csv` | `9f95aba94b53489d4ff4006be854d6418ea9de43f08ae38aff44331b262e36dc` | 7,770 |
| `archive/rtl_to_3d_source_log.log` | `reports/floorplan_optimization/results/orchestration_logs/02_rtl_to_3d.log` | `b16b73979b09ae813983ebd4e9898200261b75027fa70197ecafb3d269921b02` | 5,507 |
| `archive/reference_thermal_source_log.log` | `reports/floorplan_optimization/results/orchestration_logs/07_reference_thermal.log` | `dfa1e96dfb3b7d20a7c79246208a7190c5ded6a800a5dca99b538111e29b6720` | 22,448 |

## 추가 canonical provenance

다음 파일은 생성 결과별 provenance이므로 중복 복사하지 않고 원본을 직접 참조합니다.

| 원본 경로 | SHA-256 | 역할 |
|---|---|---|
| `output/hbm2_arch/parameter_provenance.json` | `e8a2b39c2395844b59442cec32fae7ec8c22316baf179ae2869795a85cf7c121` | HBM2 architecture parameter별 출처·분류 |
| `output/hbm2_hardware_cost/parameter_provenance.json` | `f387e92bd452c6fc55077c92fa4a39e16933809ac47add5cd8ce76d2cab4cd72` | hardware-cost 입력 provenance |
| `output/hbm2_hardware_cost/source_traceability.md` | `a857b0934d8276f0911325a74aa10f84333d6bdbfc0c7946ce131a4f8847f879` | 공개 근거·모델 사용·한계 대응표 |
| `output/hbm2_hardware_cost/rtl_mapped/parameter_provenance.json` | `1f3d7bfd115b65b91b330de7cabb52260758d058d63631b8ba9ea1a069bf03a7` | RTL-mapped 비용 분석 provenance |
| `output/floorplan_optimization/baseline/cost/parameter_provenance.json` | `ccf03ceb1aad4136755cf0be5000bcdef79335d00611a0332a23d123de95942f` | floorplan baseline 비용 provenance |

## 로그 분류

- `rtl_to_3d_source_log.log`: HotSpot과 3D-ICE reference가 어떤 RTL-to-3D 입력에 연결됐는지 남긴 실행 로그입니다.
- `reference_thermal_source_log.log`: reference thermal 반복 실행에서 사용한 외부 thermal source와 입력 provenance를 남긴 로그입니다.
- Yosys의 ABC 홈페이지나 Verilator warning 도움말처럼 도구가 자동 출력한 URL은 연구 데이터의 출처가 아니므로 archive 대상에서 제외했습니다.
- 원본 로그가 이후 재실행으로 바뀌어도 이 snapshot과 위 hash로 수집 당시 내용을 식별할 수 있습니다.
