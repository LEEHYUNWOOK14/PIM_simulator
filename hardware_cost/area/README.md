# Area 파이프라인

## 목적

로직 다이, DRAM 적층, PIM 블록, SRAM/버퍼, PHY/컨트롤러, TSV keep-out zone(KOZ)이 소비하는 면적을 분리한다. “패키지에서 보이는 면적”과 “모든 다이의 누적 실리콘 면적”을 혼동하지 않는다.

## 근거

- CACTI는 캐시/메모리의 접근시간·전력·주기·면적을 함께 추정하며 multi-bank 및 3D DRAM 모델을 지원한다. 따라서 공개되지 않은 DRAM 매크로 면적의 절대값을 주장하는 대신 향후 SRAM/버퍼 adapter의 교차검증 도구로 사용한다.
- McPAT은 아키텍처 수준 power/area/timing 통합 모델의 선례다. 본 파이프라인도 RTL-derived 값과 아키텍처 추정값을 구분한다.
- OpenROAD/Yosys 결과가 있으면 logic/PIM 면적의 우선 입력으로 사용한다. 없으면 `estimated` 범위를 사용한다.

## 계산

```text
footprint_area_mm2 = max(base_or_logic_die_area, dram_die_area)
cumulative_silicon_mm2 = base_die_area + N_die × dram_die_area
PIM_area_overhead = added_PIM_area / baseline_logic_and_peripheral_area
TSV_KOZ_area = N_TSV × effective_KOZ_area_per_TSV
usable_logic_area = logic_die_area - TSV_KOZ_area - reserved_PHY_area
utilization = placed_standard_cell_area / usable_logic_area
```

KOZ가 겹치는 경우 단순 합보다 작으므로 `independent_sum`은 상한, 실제 geometry union은 우선값이다. 기본 구현은 상세 좌표가 없으면 상한으로 분류한다.

## 입력 우선순위

1. 배치 완료 OpenROAD `design area` 및 macro report
2. 합성 Yosys cell count × 라이브러리 cell area
3. CACTI/OpenRAM과 같은 공개 모델
4. 프로젝트 파라미터
5. 추정 범위

서로 다른 공정 노드의 면적은 무근거 선형 스케일링하지 않는다. 비교가 필요하면 원 면적과 스케일 가정을 함께 보고한다.

## 출력

- `area_metrics.json`
- `area_breakdown.csv`
- `area_provenance.json`
- `area_report.md`

필수 항목은 footprint, cumulative silicon, logic usable area, TSV KOZ 상한, PIM overhead, 입력 출처와 신뢰도다.

## 검증

- 모든 면적과 개수가 0 이상
- block 면적 합이 할당 die 면적을 초과하면 실패
- 물리 채널 8개와 논리 파티션 64개를 구분
- 4Hi < 8Hi < 12Hi 누적 실리콘 면적
- 합성 입력 누락 시 자동으로 `rtl_derived`라고 표기하지 않음
