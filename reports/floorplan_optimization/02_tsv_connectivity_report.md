# Phase 1–2 — 공통 좌표 계약과 TSV 연결 구조

## 결과

기존 `hbm2_package.json`의 단일 `logic_block_x_um/y_um` 표현을 보존하면서, 8개 logic block, 48개 TSV bundle, 48개 대응 micro-bump bundle, 4개 reserved region 및 8개 routing corridor를 공통 좌표 manifest로 확장했다.

- 원점: logic die 좌하단
- +x: 오른쪽
- +y: 위쪽
- 길이 단위: µm
- bundle anchor: 배열 좌하단 element 중심

모든 객체는 classification, confidence와 source provenance를 가진다. 현재 block 좌표와 TSV/범프 세부 배열은 공개 제조 floorplan이 아니므로 `illustrative` 또는 `estimated`이며 low confidence다.

## 산출물

- `design/floorplan/logic_die_floorplan.schema.json`
- `design/floorplan/logic_die_floorplan.json`
- `design/floorplan/tsv_connectivity.csv`
- `design/floorplan/placement_objectives.json`
- `tools/generate_logic_die_floorplan_manifest.py`
- `tools/validate_logic_die_floorplan.py`
- `tools/export_logic_die_floorplan_gds.py`
- `verification/floorplan_optimization/test_floorplan_manifest.py`

기존 package 좌표는 `legacy_compatibility`에 남기고 adapter 입력으로 사용한다. placement CSV와 normalized physical input을 주면 block별 placement·power provenance로 승격할 수 있지만, 현재 기본 manifest는 RTL 구조가 확정되지 않은 상태를 반영해 illustrative placement다.

## TSV 및 micro-bump 구조

각 물리 channel에 다음 6개 signal-class bundle을 둔다.

| Signal class | Bundle 수 | 표시 element 수 | 의미 |
|---|---:|---:|---|
| data | 8 | 128 | channel-level bidirectional data representation |
| command_address | 8 | 32 | command/address representation |
| clock | 8 | 16 | clock representation |
| power | 8 | 64 | power delivery representation |
| ground | 8 | 64 | ground return representation |
| spare | 8 | 16 | illustrative redundancy |
| 합계 | 48 | 320 | bit-accurate manufacturer pin count가 아님 |

각 TSV bundle은 동일 signal class의 micro-bump bundle 하나와 ID로 연결되며, 해당 micro-bump는 `top.logic_die_link_arbiter`로 연결된다. 48/48 TSV bundle의 대응 micro-bump 연결을 검증했다. `bandwidth_bits`는 논리적 channel-level 폭이며 화면의 element 수와 동일한 물리 pin 수를 뜻하지 않는다.

TSV diameter, pitch와 keep-out은 uncertainty range를 포함한다. exact pin map과 foundry rule이 없기 때문에 모든 bundle의 `connectivity_source`는 bit-level 정확성을 명시적으로 부정한다.

## 검증

다음 검사가 모두 PASS했다.

- JSON Schema Draft 2020-12
- 좌표계와 µm 단위 고정
- block/bundle/region ID 중복 거부
- die boundary 및 block halo
- block overlap
- allowed region
- PHY/PDN/clock reserved-region 충돌
- TSV diameter/pitch/keep-out 및 block 침범
- dangling source/destination
- manifest↔TSV CSV round-trip
- 기존 package 단일 좌표 backward compatibility
- placement CSV 및 normalized power adapter

10개 unittest가 valid case와 wrong unit, overlap, out-of-die, TSV keep-out, duplicate bundle, dangling endpoint, reserved-region collision 및 CSV mismatch rejection을 검증한다.

## KLayout 추적성

manifest에서 직접 GDS/LYP를 생성한다. logic block, TSV signal class, micro-bump signal class, TSV keep-out, PHY/PDN/clock 예약 영역, routing corridor, connectivity 및 object label을 분리된 layer로 출력한다.

KLayout headless 결과:

```text
KLAYOUT_FLOORPLAN_GDS PASS
top=STOB_LOGIC_DIE_FLOORPLAN_NOT_SIGNOFF
tsv=320
bumps=320
bbox=(0,0;8000000,12000000)
```

따라서 화면의 TSV/micro-bump shape 수는 manifest 배열의 확장 결과와 일치한다. label에는 bundle ID, signal class와 shape count가 포함된다. 이 일치는 시각화 추적성 증거이지 DRC/LVS 또는 제조 pin-map 검증이 아니다.

## 재현 명령

```powershell
.\.venv\Scripts\python.exe tools\generate_logic_die_floorplan_manifest.py
.\.venv\Scripts\python.exe tools\validate_logic_die_floorplan.py --output reports\floorplan_optimization\results\floorplan_manifest_validation.json
.\.venv\Scripts\python.exe -m unittest verification.floorplan_optimization.test_floorplan_manifest -v
.\.venv\Scripts\python.exe tools\export_logic_die_floorplan_gds.py
```

## 다음 단계

현재 좌표는 contract와 시각화 검증을 위한 deterministic baseline이다. Phase 3에서 fixed seed candidate generator가 block orientation/좌표를 변화시키고 hard constraint를 통과한 후보만 analytical wirelength, TSV distance, power-density, KOZ/corridor area proxy로 평가한다.
