# Phase 5 — 후보별 열해석 연동 및 solver 교차검증

## 공통 조건

다섯 후보의 8개 block rectangle과 `dynamic_W + leakage_W`를 기존 mapped-power IR로 변환했다. 모든 후보의 총전력은 `4.0 W`이며 rasterization 후 손실은 `0.0 W`다. 전력은 workload 측정값이 아니라 `estimated_4W_logic_die_allocation_for_relative_candidate_comparison`이므로 절대 안전온도 결론은 내리지 않는다.

기존 reference finite-volume solver의 검증은 PASS다. steady equation residual은 `2.84217e-13 W`, symmetry·zero-power·grid/timestep convergence 및 TSV effective comparison도 통과했다. CPU SciPy sparse solve이며 GPU solver가 아니다.

## 결과

| 후보 | Reference 3D peak (°C) | Max logic gradient (K/mm) | 3D-ICE peak (°C) | HotSpot 2D peak (°C) |
|---|---:|---:|---:|---:|
| thermal_first | 37.8080 | 2.1519 | 39.513 | 30.470 |
| manual_baseline | 38.5522 | 1.9601 | 40.917 | 31.930 |
| balanced | 39.0961 | 2.2918 | 42.047 | 30.340 |
| cost_first | 39.0961 | 2.2918 | 42.047 | 30.340 |
| wirelength_first | 40.5850 | 2.0363 | 44.906 | 175.130 |

Reference 3D와 3D-ICE full-stack 모델은 `thermal_first < manual < balanced/cost < wirelength_first`로 동일한 peak-temperature 순위를 냈다. HotSpot은 generic 2D block/package model이므로 balanced와 thermal의 순서가 뒤집혔고 wirelength 후보에 매우 큰 hotspot을 예측했다. 따라서 HotSpot 절대값은 calibration 근거로 쓰지 않고 topology 민감도 경고로만 사용한다.

3D-ICE adapter는 100 µm logic die, 8 × 32 µm DRAM die, 8 × 15 µm effective bump layer, 32×16 grid와 top convection boundary를 사용한다. 3D-ICE `4.0` commit `4953952...`에서 후보 5개가 모두 정상 종료했고 logic temperature map을 생성했다. reference model과 재료/경계 구현이 완전히 같지 않으므로 두 solver 간 °C 차이는 model uncertainty다.

## 산출물과 분류

- `output/floorplan_optimization/thermal_results.csv`: modeled reference finite-volume, estimated power
- `output/floorplan_optimization/3dice_results.csv`: modeled full-stack 3D-ICE, estimated power
- `output/floorplan_optimization/hotspot_results.csv`: modeled HotSpot 2D, estimated power
- 후보별 NPZ/VTK/GDS heatmap, 3D-ICE map, HotSpot steady file는 각 solver 하위 폴더에 보존한다.
- 모든 결과의 signoff 필드는 `NO`다.

## 재현 명령

```powershell
.\tools\run_floorplan_thermal_candidates.ps1
.\tools\run_floorplan_hotspot_candidates.ps1
.\tools\run_floorplan_3dice_candidates.ps1
```
