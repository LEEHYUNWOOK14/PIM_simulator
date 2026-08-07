# Package 파이프라인

## 목적

HBM2 적층을 만드는 TSV, micro-bump, interposer, substrate, 배선 및 접합 단계의 물리량과 상대 복잡도를 계산한다. 실제 OSAT/파운드리 견적은 공개되지 않으므로 기본 출력은 비용지수다.

## 논리적 근거

- HBM2는 1,024-bit 폭과 짧은 interposer 연결로 높은 대역폭을 얻으므로 interposer 면적과 라우팅, I/O/범프 수가 핵심 패키지 자원이다.
- 삼성 공개 HBM2E 자료는 8개 DRAM 다이와 40,000개 이상의 TSV microbump 접합을 설명한다. 이는 정확한 HBM2 좌표가 아니라 연결 규모의 공개 교차검증점으로만 사용한다.
- 3D IC 연구는 TSV 결함과 bonding 단계가 수율 및 비용에 영향을 준다고 보고한다. 따라서 TSV 수, 접합 인터페이스 수, 적층 수를 독립 항목으로 유지한다.

## 물리 지표

```text
microbump_count = bump_rows × bump_columns × interfaces × stack_count
signal_TSV_count = physical_channels × TSV_groups_per_channel × TSVs_per_group × dies × stacks
bond_interfaces = dies_per_stack × stack_count
interposer_area = interposer_width × interposer_height
package_footprint = package_width × package_height
stack_height = base + N×dram + N×gap + TIM + lid
```

## 상대 복잡도

```text
package_metric =
  w_interposer × normalized_interposer_area
+ w_bump       × normalized_microbump_count
+ w_tsv        × normalized_TSV_count
+ w_bond       × normalized_bond_interfaces
+ w_routing    × normalized_routing_demand
```

이는 가격식이 아니라 제조자원 proxy다. 가중치는 config에 노출하고, 동일 가중치와 각 성분을 함께 출력한다. microbump와 TSV가 동일 개념이 아니므로 중복 계수 여부를 보고한다.

## 출력과 검증

- `package_metrics.json`, `package_breakdown.csv`, `package_report.md`
- 범프/TSV/인터페이스/면적/높이의 단위 검사
- stack 수와 die 수 증가에 대한 단조성
- manufacturer count와 model count가 다르면 오류가 아니라 차이와 정의를 보고
- 상세 pin map 부재를 명시
