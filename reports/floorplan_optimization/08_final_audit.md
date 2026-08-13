# Phase 8 최종 감사

## 결론

공통 floorplan IR을 중심으로 기존 HBM2 architecture → RTL-to-3D → thermal → hardware-cost 파이프라인을 연결하고, OpenROAD/KLayout/ParaView/HotSpot/3D-ICE 근거를 추가했다. 현재 권고는 단일 승자가 아니라 다음 3개 provisional shortlist이다.

- `thermal_first`: reference FVM 37.808 °C와 3D-ICE 39.513 °C로 가장 낮지만 macro proxy overflow 합 225이다.
- `wirelength_first`: overflow 0, global-route WL 56.297 mm, cost proxy 0.991로 배선/비용 우선안이지만 reference FVM 40.585 °C로 가장 뜨겁다.
- `manual_baseline`: overflow 0과 중간 열성능 38.552 °C의 보수적 fallback이다.

`balanced`와 `cost_first`는 같은 candidate ID이며 WL 55.828 mm로 최소지만 overflow 합 358이다. 따라서 최종 RTL·PHY·power가 확정되기 전에는 하나를 production floorplan으로 고정하지 않는다.

## 재사용과 강화

| 구분 | 내용 |
|---|---|
| 그대로 재사용 | `generate_hbm2_architecture.py`, `collect_rtl_physical_inputs.py`, `rtl_to_3d_power_map.py`, reference thermal solver/validator, HotSpot exporter, hardware-cost model/validator, ORFS sky130hd flow |
| 연결·강화 | canonical schema/manifest와 adapters, TSV/bump connectivity, geometry validator, deterministic optimizer, OpenROAD macro proxy, mapped-power candidate runner, 3D-ICE adapter, 비용 통합 비교 |
| 시각화 강화 | 계층형 KLayout GDS/LYP, 512 thermal bins, fixed camera, ParaView VTU 및 RTX 4060 렌더, 6개 논문 figure |
| 재현성 강화 | 통합 entrypoint, 단계별 로그, generation manifest SHA-256, requirement matrix, RTL refresh handoff |

RTL과 프로토콜 파일은 이 작업에서 수정하지 않았다. `flow/run_flow.ps1`과 `flow/designs/sky130hd/stob_pim2/config.mk`는 현재 dirty RTL을 읽는 경로·단계 실행 호환성만 강화했으며 사용자 변경을 되돌리거나 삭제하지 않았다.

## 핵심 변경 파일과 이유

| 파일군 | 변경 이유 |
|---|---|
| `design/floorplan/logic_die_floorplan.schema.json`, `logic_die_floorplan.json`, `tsv_connectivity.csv`, `placement_objectives.json` | 공통 좌표·연결·목적함수 계약 고정 |
| `tools/generate_logic_die_floorplan_manifest.py`, `validate_logic_die_floorplan.py` | 기존 architecture/package/RTL snapshot adapter와 geometry/connectivity 거부 검사 |
| `tools/optimize_logic_die_floorplan.py` | seed 기반 legal candidate와 Pareto/weight sensitivity 생성 |
| `tools/export_floorplan_openroad_proxy.py`, `run_floorplan_openroad_proxies.ps1`, `collect_floorplan_openroad_proxy_metrics.py` | 후보를 동일한 conceptual macro route 조건에서 비교 |
| `tools/floorplan_manifest_to_mapped_power.py`, thermal/HotSpot/3D-ICE runner·exporter·collector | 동일 4 W 보존과 세 solver 교차검증 |
| `tools/compare_floorplan_candidates.py` | thermal·routing·cost evidence 통합 및 uncertainty-sensitive shortlist |
| GDS/KLayout/ParaView exporter·renderer와 `generate_floorplan_paper_figures.py` | 계층형 2D/3D 및 논문 figure 생성 |
| `tools/run_logic_die_floorplan_analysis.ps1`, `collect_floorplan_generation_manifest.py` | 기존 래퍼 통합 회귀·단계 로그·SHA-256 재현성 |
| `verification/floorplan_optimization/test_*.py` | invalid input·결정성·solver/GDS/figure/evidence package 검증 |
| `reports/floorplan_optimization/00_*.md`~`08_final_audit.md`와 CSV/index/handoff | 단계별 주장·근거·한계 추적 |

## 공통 구조와 검증

- 좌표: logic die 좌하단 원점, +x 오른쪽, +y 위쪽, 단위 µm, 8,000 x 12,000 µm.
- 구조: 8 blocks, 48 TSV bundles/320 TSV shapes, 48 bump bundles/320 bump shapes, 4 reserved regions, 8 routing corridors.
- 연결성: bundle-level illustrative/low-confidence이며 exact bit-level PHY pin map으로 주장하지 않는다.
- 후보 탐색: seed 235, 400 attempts, 283 feasible, 118 rejected, 45 Pareto candidates.
- 검증: schema/geometry/connectivity/provenance invalid fixture 거부, 후보 결정성, solver/evidence alignment, GDS 계층 count 및 figure 존재 검증.

## 물리·열·비용 비교

| 후보 | reference peak (°C) | 3D-ICE peak (°C) | OpenROAD proxy WL (mm) | overflow 합 | normalized structural cost |
|---|---:|---:|---:|---:|---:|
| manual | 38.552 | 40.917 | 59.782 | 0 | 1.000 |
| wirelength first | 40.585 | 44.906 | 56.297 | 0 | 0.991 |
| thermal first | 37.808 | 39.513 | 58.567 | 225 | 1.028 |
| balanced / cost first | 39.096 | 42.047 | 55.828 | 358 | 1.040 |

모든 후보는 동일한 estimated 4.0 W를 사용했고 reference solver power residual은 최대 `2.842e-13 W`였다. reference FVM과 3D-ICE의 순위는 같았다. HotSpot은 `wirelength_first`에서 175.13 °C를 산출하고 순위도 달라, 설정 민감도가 큰 정성적 교차검증으로만 남긴다. 비용은 제조사 가격이 아닌 기존 HBM fixed revision과 route/overflow를 결합한 normalized proxy다.

## OpenROAD 증거 경계

후보 5개는 16 fixed conceptual macros를 DEF로 round-trip하고 global route까지 실행했다. candidate-level Liberty/STA, PDN/IR 및 detailed route는 없으므로 `modeled/global-routed-proxy`다.

현재 dirty RTL 스냅샷은 Yosys 75,925 cells/836,200.733 µm², legal placement, CTS 14,459 sinks/1,696 buffers, global route 102,932 nets/7,914,921 µm/823,025 vias/44.77% resource usage까지 완료했다. 그러나 10 ns constraint에 reported period 53.060 ns, slack -45.853 ns이고 I/O delay 누락 및 13,481 unconstrained endpoints가 있다. 상세배선은 90%, 45,913 violations에서 WSL resource interruption으로 끝났고 output ODB가 없다. 따라서 routed, timing-closed, DRC-clean, IR-signoff를 주장하지 않는다.

## 실행·도구·근거

권장 재현 명령은 다음 하나다.

```powershell
.\tools\run_logic_die_floorplan_analysis.ps1
```

기본 실행은 architecture, RTL-to-3D, hardware cost, manifest, candidate search, OpenROAD proxies, reference thermal, HotSpot, 3D-ICE, candidate comparison, KLayout/ParaView render와 테스트를 단계별 로그로 남긴다. OpenROAD 26Q3-1080, Yosys 0.68+48, KLayout 0.30.10, ParaView 6.1.1, OpenSCAD 2021.01, Blender 5.2 LTS를 사용했다. ParaView 렌더는 RTX 4060 VisRTX를 사용했지만 thermal solve는 CPU이다.

최종 통합 실행은 architecture/4Hi·12Hi variant, RTL-to-3D 7 tests, hardware-cost 6 tests, reference thermal validator, 5개 후보의 OpenROAD proxy·reference/HotSpot/3D-ICE를 PASS했다. 이후 production GDS merger 회귀 6개가 추가되어 floorplan suite는 총 26 tests를 PASS한다. 단계별 상태·시간은 `orchestration_results.json`, 원문은 `orchestration_logs/`에 있다.

## 증거 분류와 논문 주장 범위

- `synthesized/placed/global_routed`: 현재 dirty RTL의 ORFS 스냅샷. timing·detailed route 미완료.
- `modeled/estimated`: 후보 geometry, 4 W power, reference/HotSpot/3D-ICE, 비용 proxy.
- `illustrative`: TSV bit-level 연결, package/PHY 예약 geometry, KLayout/ParaView 도식.
- `measured`: 없음. Silicon·실험·제조사 측정값으로 주장할 수 없다.

논문에서는 “동일한 estimated-power 조건에서 후보 간 상대 열·배선·비용 trade-off가 재현된다”와 “공통 manifest에서 GDS/VTU/OpenROAD proxy가 추적된다”까지 주장할 수 있다. production HBM PHY pin map, SI/PI, static IR, foundry DRC/LVS, calibrated junction temperature, yield/cost 견적, silicon signoff는 주장할 수 없다.

## 완료 근거

- 요구사항 R01~R16: `reports/floorplan_optimization/requirement_to_evidence.csv`
- 논문 그림 및 caption 경계: `reports/floorplan_optimization/paper_figure_index.md`
- 최종 RTL 교체 입력: `reports/floorplan_optimization/rtl_refresh_handoff.md`
- 해시·도구·dirty snapshot: `output/floorplan_optimization/generation_manifest.json`
- 통합 회귀 단계와 로그: `reports/floorplan_optimization/results/orchestration_results.json`

최종 recommendation은 **provisional**이며, RTL/PHY/package/power가 확정되면 handoff 절차로 동일 분석을 재실행해야 한다.
