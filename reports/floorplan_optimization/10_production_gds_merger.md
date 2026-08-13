# Production GDS merge/coordinate-transform 도구

## 구현 상태

최종 routed RTL GDS/OASIS와 canonical TSV·micro-bump overlay를 계층 보존 상태로 병합하는 도구 구현 및 synthetic/대형 stress 검증을 완료했다. 이 도구의 `production` 의미는 입력 거부·재현성·좌표/계층 검증을 갖춘 반복 가능한 병합기라는 뜻이며, 병합 결과 자체가 foundry signoff라는 뜻은 아니다.

## 구성

| 파일 | 역할 |
|---|---|
| `design/floorplan/final_gds_merge_recipe.schema.json` | 엄격한 입력·layer map·placement·verification 계약 |
| `tools/prepare_final_gds_merge_recipe.py` | GDS layer inventory, SHA-256 고정 및 draft recipe 생성 |
| `tools/merge_final_rtl_gds.py` | DBU/orientation/layer/cell/anchor 정규화와 계층형 병합 |
| `tools/run_final_rtl_gds_merge.ps1` | 로컬 전용 환경 실행 및 선택적 KLayout 열기 |
| `verification/floorplan_optimization/test_final_gds_merge.py` | 8방향·DBU·layer·namespace·anchor·실패 조건 회귀 |

## 구현된 안전 조건

- 입력 RTL/overlay/manifest 존재 및 선택 top-cell 검사
- 선택적인 입력 SHA-256 pinning
- KLayout cross-layout `copy_tree` 기반 DBU 정규화와 실제 output polygon bbox 재검사
- `R0`, `R90`, `R180`, `R270`, `MX`, `MY`, `MXR90`, `MYR90` 지원
- 비단위 물리 확대 기본 거부; DBU 변환과 physical scale을 분리
- source layer 누락·unmapped layer·overlay layer 충돌 거부
- 모든 RTL/overlay cell namespace 분리 및 output top 충돌 거부
- 최소 2개 anchor 기본 요구, manifest TSV/micro-bump/block/region 참조 지원
- anchor translation의 output DBU quantization 및 residual tolerance 검사
- transformed RTL bbox의 canonical die boundary 검사
- 기존 입력 덮어쓰기 금지와 output 재생성 시 명시적 `--force` 요구
- 독립 KLayout readback, hierarchy/layer/shape/hash report 생성
- overlay LYP에 RTL layer를 추가한 통합 LYP 생성

## Final GDS 사용 절차

먼저 최종 RTL의 서로 다른 PHY landing point 두 개와 해당 TSV 또는 micro-bump target을 확정한다. 좌표를 직접 지정하는 예시는 다음과 같다.

```powershell
. .\tools\enter_gds_merge_environment.ps1

python tools\prepare_final_gds_merge_recipe.py `
  --rtl-gds D:\final_rtl\full_pim_system_top.gds `
  --rtl-top full_pim_system_top `
  --overlay-gds output\floorplan_optimization\visualization\thermal_first\logic_die_floorplan.gds `
  --overlay-top STOB_LOGIC_DIE_FLOORPLAN_NOT_SIGNOFF `
  --manifest output\floorplan_optimization\exploration\candidates\thermal_first.json `
  --overlay-lyp output\floorplan_optimization\visualization\thermal_first\logic_die_floorplan.lyp `
  --recipe design\floorplan\final_rtl_gds_merge_recipe.json `
  --output-root D:\final_rtl\merged `
  --orientation R0 `
  --anchor phy_west:120.0:80.0:425.0:1000.0 `
  --anchor phy_east:1500.0:80.0:7425.0:1000.0

.\tools\run_final_rtl_gds_merge.ps1 `
  -Recipe design\floorplan\final_rtl_gds_merge_recipe.json `
  -Force -OpenKLayout
```

Manifest 객체를 직접 참조하려면 다음 형식을 사용할 수 있다.

```text
--manifest-anchor name:source_x_um:source_y_um:tsv_bundle:TSV_CH0_DATA:centroid
--manifest-anchor name:source_x_um:source_y_um:micro_bump_bundle:MBUMP_CH7_DATA:centroid
```

자동 recipe는 exact layer/datatype collision만 안전한 빈 layer로 옮기고 이름에 `AUTO_REMAP_REVIEW`를 붙인다. 최종 foundry layer semantics는 PDK stream-out map과 대조하여 사람이 승인해야 하며, 이름만 보고 metal/via 의미를 추정하지 않는다.

기존 전체 분석과 함께 실행할 수도 있다.

```powershell
.\tools\run_logic_die_floorplan_analysis.ps1 `
  -FinalGdsMergeRecipe design\floorplan\final_rtl_gds_merge_recipe.json
```

## 검증 결과

Synthetic 회귀는 서로 다른 입력 DBU `0.005 µm`와 `0.002 µm`를 output `0.001 µm`로 정규화하고, 8개 orientation 모두 실제 metal polygon bbox와 두 anchor가 일치함을 확인한다. inconsistent anchor, unmapped/colliding layer, 비허용 scale, output overwrite, 동일 namespace를 거부한다.

대형 stress에서는 현재 최종 RTL로 오해하지 않도록 historical/stale로 분류된 `output/output.gds`를 사용했다.

| 항목 | 결과 |
|---|---:|
| RTL hierarchy + overlay output cells | 392 |
| RTL used layer/datatype pairs | 39 |
| Overlay used layer/datatype pairs | 51 |
| Anchor 수 | 2 |
| 최대 anchor residual | 0.000707107 µm |
| Transformed RTL die 내부 | PASS |
| 병합 GDS 크기 | 124.86 MiB |
| KLayout 독립 readback | PASS |

대형 병합 GDS는 OneDrive가 아닌 다음 로컬 경로에 저장했다.

```text
C:\Users\Admin\AppData\Local\STOB_EDA\gds-merge\historical-routed-stress\merged_final_physical.gds
```

이 stress 결과는 병합 확장성만 입증하며 stale RTL, 약 274,099 DRC 및 미완료 timing을 개선하거나 signoff로 바꾸지 않는다. 최종 GDS가 확보되면 input hash, top, layer map과 anchor만 교체하여 같은 gate를 실행한다.
