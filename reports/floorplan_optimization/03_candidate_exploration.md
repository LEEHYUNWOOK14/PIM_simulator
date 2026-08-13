# Phase 3 — 좌표 후보 생성과 빠른 비용 평가

## 결과

공통 floorplan manifest와 seed 235를 입력으로 400개 random permutation/jitter 시도를 수행했다. manual baseline을 포함해 283개 unique feasible 후보를 평가했고 118개를 hard constraint 위반으로 탈락시켰다. 45개 후보가 analytical proxy 기준 Pareto frontier에 남았다.

- 입력 logic power: 4.0 W `estimated`
- block geometry: `illustrative/provisional`
- temperature, congestion, timing, IR-drop: Phase 3 analytical proxy
- OpenROAD/thermal solver 결과가 아니며 signoff 수치가 아님

## 선택 후보

| 전략 | Candidate | Temp proxy (°C) | Baseline 대비 | Traffic-weighted Manhattan (µm) | Baseline 대비 | Congestion proxy | Pareto |
|---|---|---:|---:|---:|---:|---:|---|
| manual_baseline | `cand_deb1a75ad74b` | 39.191 | 기준 | 7,207.4 | 기준 | 2.221 | no |
| wirelength_first | `cand_79bdf2d4412e` | 42.356 | +8.08% | 5,047.4 | -29.97% | 2.691 | yes |
| thermal_first | `cand_40d1fe3576c0` | 36.314 | -7.34% | 6,750.1 | -6.35% | 1.760 | yes |
| balanced | `cand_47f1b95e9a56` | 37.685 | -3.84% | 5,552.0 | -22.97% | 2.145 | yes |
| cost_first | `cand_47f1b95e9a56` | 37.685 | -3.84% | 5,552.0 | -22.97% | 2.145 | yes |

`cost_first`와 `balanced`가 같은 좌표를 선택했다. 이를 억지로 서로 다른 후보로 바꾸지 않았다. 현재 proxy와 정규화 범위에서는 해당 후보가 두 profile의 최소 score이며, Phase 4~6의 실제 placement/route/thermal/cost 결과가 들어오면 분리될 수 있다.

## 평가 방식

평가된 metric은 다음과 같다.

- coarse Gaussian power field의 peak temperature proxy
- power-weighted hotspot proximity
- block traffic endpoint와 class별 TSV bundle 간 Manhattan distance
- channel distance coefficient of variation
- coarse Manhattan route-demand congestion proxy
- timing-criticality weighted distance proxy
- power-TSV distance 기반 IR-drop proxy
- TSV KOZ 및 routing corridor 면적
- wire/repeater·congestion을 포함한 normalized cost proxy

min/max normalization 범위와 profile weight는 `optimization_summary.json`에 그대로 기록했다. 가중합과 별개로 6개 최소화 metric에 대한 Pareto dominance를 계산했다.

## Hard constraint와 탈락 추적

후보는 평가 전에 다음을 검사한다.

- die boundary와 halo
- block overlap
- allowed region
- PHY/PDN/clock reserved region
- TSV keep-out

이번 탐색의 탈락 118개는 jitter로 block이 TSV keep-out에 진입한 사례다. `rejected_candidates.csv`에는 candidate ID와 침범한 block/bundle ID가 보존된다. 합법 slot permutation은 geometry 평가에 들어갔으며 탈락 후보는 score나 Pareto 계산에 포함되지 않았다.

## Weight sensitivity

각 profile에서 6개 weight를 각각 -20%, 0%, +20% 변화시키고 합이 1이 되도록 다시 정규화했다.

- balanced: 18/18에서 `cand_47f1b95e9a56`
- cost_first: 15/18에서 balanced 후보, 3/18에서 wirelength 후보
- thermal_first: 13/18에서 `cand_40d1fe3576c0`, 5/18에서 balanced 후보

따라서 balanced 선택은 현재 proxy weight perturbation에 안정적이다. cost/thermal profile은 일부 경계 조건에서 후보가 바뀌므로 단일 확정안이 아니라 공동 검증 대상으로 Phase 4~6에 전달한다.

## 재현성

동일 seed 235와 동일 manifest로 두 번 수행한 80-sample 회귀에서 selected candidate ID와 feasible candidate 수가 동일했다. exported 5개 후보는 전체 schema/geometry validator를 다시 통과했다.

```powershell
.\.venv\Scripts\python.exe tools\optimize_logic_die_floorplan.py --seed 235 --samples 400
.\.venv\Scripts\python.exe -m unittest verification.floorplan_optimization.test_floorplan_optimizer -v
```

주요 산출물:

- `output/floorplan_optimization/exploration/placement_candidates.csv`
- `output/floorplan_optimization/exploration/rejected_candidates.csv`
- `output/floorplan_optimization/exploration/pareto_frontier.csv`
- `output/floorplan_optimization/exploration/selected_candidates.csv`
- `output/floorplan_optimization/exploration/weight_sensitivity.csv`
- `output/floorplan_optimization/exploration/candidates/*.json`

Phase 3 수치는 후보 압축용이다. Phase 4에서는 baseline과 상위 후보를 동일 OpenROAD 조건으로 비교하고, Phase 5에서는 동일 총전력으로 reference solver·HotSpot·3D-ICE를 교차검증한다.
