# 논문 그림 인덱스

모든 그림은 연구용 provisional floorplan에서 생성되었으며 제조·열·SI/PI signoff가 아니다. PNG는 300 dpi이고 도식 그림은 SVG도 함께 제공한다.

| 그림 | 파일 | 근거와 주장 가능 범위 | 주장 불가 범위 |
|---|---|---|---|
| 1. HBM stack 3D | `output/floorplan_optimization/visualization/paper_figures/figure_01_hbm_stack_3d.png` | ParaView 6.1.1/RTX 4060 렌더; modeled stack·TSV 중심선·block·온도장; Z 20배 과장 | 실제 재료 형상·제조 단면·GPU thermal solve |
| 2. logic die/TSV 좌표 | `figure_02_logic_die_tsv_coordinates.{png,svg}` | canonical 8 x 12 mm 좌표계; signal-class bundle과 예약영역 | 공개되지 않은 bit-level HBM pin map |
| 3. 후보 배치 | `figure_03_candidate_placement_comparison.{png,svg}` | 동일 축척의 manual/wire/thermal/balanced provisional geometry | standard-cell 실제 배치 |
| 4. 배선/혼잡 | `figure_04_openroad_routing_congestion.{png,svg}` | OpenROAD conceptual macro global-route proxy | detailed-route·STA·IR·DRC signoff |
| 5. 전력/온도 | `figure_05_power_temperature_heatmaps.{png,svg}` | 동일 estimated 4 W와 검증된 reference FVM의 상대 비교 | calibration된 절대 junction temperature |
| 6. Pareto trade-off | `figure_06_cost_wire_temperature_pareto.{png,svg}` | normalized cost proxy·global-route WL·modeled temperature의 구조 비교 | 실제 wafer/package 견적 |

공통 figure metadata와 고정 축척은 `output/floorplan_optimization/visualization/paper_figures/figure_manifest.json`에 기록한다. KLayout 원본 fixed-camera 이미지는 `output/floorplan_optimization/visualization/<strategy>/klayout_fixed_camera.png`이다.
