# Phase 7 — KLayout 및 고급 3D 시각화

## KLayout

후보별 GDS는 동일한 8×12 mm 좌표계와 layer map을 사용한다.

- block: layer 110, classification datatype
- TSV: signal class별 120–126
- TSV keep-out: 130
- micro-bump: signal class별 140–146
- PHY/PDN/clock/decap/routing reserved region: 150–158
- connectivity: 170
- labels: 199
- modeled temperature low→high: 200–215

각 GDS에는 8개 block child cell, 48개 TSV bundle child cell, 48개 micro-bump bundle child cell이 있어 ID를 hierarchy와 label로 역추적할 수 있다. 후보당 TSV 320 shapes, bump 320 shapes, thermal bins 512개다. KLayout batch 검증에서 다섯 후보 모두 top bbox `(0,0;8000000,12000000)`과 shape count가 일치했다.

고정 camera/scale raw 렌더는 `output/floorplan_optimization/visualization/<strategy>/klayout_fixed_camera.png`다. 색상은 mask material이나 실제 온도 물성을 뜻하지 않으며 LYP의 display convention이다. thermal layer만 reference solver의 modeled field를 16단계로 양자화한다.

## ParaView 3D

후보별로 두 VTU를 제공한다.

- `stack_temperature_physical_z.vtu`: x/y/z 모두 µm의 실제 modeled aspect ratio
- `stack_temperature_z20_exaggerated.vtu`: z만 20배 과장한 논문 가시화

각 VTU는 21-layer 32×16 thermal grid, 8개 conceptual logic block overlay와 320개 TSV centerline을 포함하고 cell data로 `temperature_K`, `object_type`, `signal_class`, `diameter_um`을 제공한다. TSV는 ParaView Tube filter에서 `diameter_um`을 사용할 수 있다. 후보당 11,080 cells다.

ParaView 6.1.1 offscreen 렌더는 RTX 4060을 실제로 인식했다. thermal solve와 VTU export는 CPU이며 GPU solver로 표현하지 않는다.

## 논문 그림

1. `figure_01_hbm_stack_3d.png`: ParaView stack/TSV/block/temperature, z 20× 강조
2. `figure_02_logic_die_tsv_coordinates.{png,svg}`: block·reserved·corridor·signal-class TSV 좌표
3. `figure_03_candidate_placement_comparison.{png,svg}`: 동일 0–8 mm × 0–12 mm 축의 4개 대표 후보
4. `figure_04_openroad_routing_congestion.{png,svg}`: 후보 macro global-route layer WL 및 overflow
5. `figure_05_power_temperature_heatmaps.{png,svg}`: thermal-first의 4 W power raster와 reference temperature
6. `figure_06_cost_wire_temperature_pareto.{png,svg}`: normalized cost/route/temperature trade-off

각 그림의 주장 범위와 generator는 `output/floorplan_optimization/visualization/paper_figures/figure_manifest.json`에 있다. PNG는 300 dpi 생성이고, 2D 도표는 편집 가능한 SVG도 제공한다.

## 재현 명령

```powershell
.\.venv\Scripts\python.exe tools\export_logic_die_floorplan_gds.py --manifest <candidate.json> --thermal-field <temperature_field.npz> --output <dir>
.\.venv\Scripts\python.exe tools\export_floorplan_paraview.py --manifest <candidate.json> --thermal-field <temperature_field.npz> --output <dir>
klayout_app.exe -b -zz -r tools\render_floorplan_klayout.py
pvpython.exe tools\render_floorplan_paraview.py --input <z20.vtu> --output <figure.png>
.\.venv\Scripts\python.exe tools\generate_floorplan_paper_figures.py
```
