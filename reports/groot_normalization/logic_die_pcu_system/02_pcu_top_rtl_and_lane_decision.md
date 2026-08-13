# Logic-die PCU top RTL 구현 및 4/8/16-lane 재판정

## 구현 결과

`rtl/logic_die_normalization_pcu_top.sv`가 기존 `mixed_precision_multirow_datapath`를 다음 시스템 경로에 연결한다.

```text
external invocation descriptor
          ↓
bank activation reduction read
          ↓
cross-bank global reduction + scalar PCU
          ↓
backpressure-safe replay request
          ↓
bank activation/gamma/beta replay → apply pipeline
          ↓
final result bank write-back
```

추가된 top-level contract:

- invocation과 row job의 분리
- full 16-bank job mask 검증
- scalar 완료 후 replay request 유지
- 16-entry write-back lifetime context
- bank별 final-last completion tracking
- activation read, affine read, write-back, bank→logic partial, logic→bank scalar, external descriptor byte counter
- 모든 데이터 경로의 ready/valid backpressure

## 검증 결과

### Interface regression

4/8/16-lane 모두 다음을 통과했다.

- replay request 5-cycle backpressure hold
- reduction → scalar → replay → apply → write-back
- expected zero normalization output
- context leak 없음
- 여섯 traffic counter의 exact byte 검사

### 실제 trace RTL replay

| Lanes | Profiles | Weighted elements | Mixed-model mismatch | Weighted RTL cycles | Elements/cycle | Cost units |
|---:|---:|---:|---:|---:|---:|---:|
| 4 | 6/6 | 21,534,720 | 0 | 412,945 | 52.149 | 848.75 |
| 8 | 6/6 | 21,534,720 | 0 | 263,048 | 81.866 | 1,504.75 |
| 16 | 6/6 | 21,534,720 | 0 | 241,282 | 89.251 | 2,816.75 |

PyTorch BF16 sample-row mismatch는 lane별 37/39/37개이며 기존 mixed-precision contract의 최대 오차 범위 안이다. RTL과 mixed-precision golden 간 mismatch는 세 lane 모두 0이다.

## Hardware cost 정의

공정 면적 대신 구조적 자원으로 계산했다.

```text
relative cost = FP32 adders
              + 2 × FP32 multipliers
              + 8 × rsqrt units
              + state bits / 1024
```

이 값은 절대 면적 또는 전력이 아니라 동일 RTL family 내 상대 비교용이다.

| 변화 | RTL cycle 감소 | Relative cost 증가 |
|---|---:|---:|
| 4 → 8 lane | 36.30% | 77.29% |
| 8 → 16 lane | 8.27% | 87.19% |

모든 lane은 외부 descriptor 8,608 B로 동일하며, 외부 I/O 제거율도 동일하다. 따라서 16-lane은 프로젝트의 1차 목표를 더 개선하지 않고, 8-lane 대비 cycle을 8.27%만 줄이는 대신 hardware cost를 87.19% 늘린다.

## 최종 재판정

**`LANES=8, SCALAR_ENGINES=4, CONTEXTS=16`을 RTL freeze 대상으로 선정한다.**

- 4-lane은 최소 비용 fallback이며 shared-port bank scheduler가 매우 제한적일 때 유효하다.
- 8-lane은 4-lane 대비 유의미한 1.57× cycle speedup을 얻는 knee다.
- 16-lane은 최대 throughput 선택지지만 marginal gain이 작아 기본 구조에서 제외한다.
- bank scheduler가 reduction/replay/write-back을 serialize해도 기능은 유지되며, 실제 bandwidth에 따른 성능 범위는 cycle model의 세 port mode로 공개한다.

## 근거 산출물

- `reports/groot_normalization/results/logic_die_pcu_system/rtl_profile_results.csv`
- `reports/groot_normalization/results/logic_die_pcu_system/rtl_lane_decision.csv`
- `reports/groot_normalization/results/logic_die_pcu_system/rtl_candidate_decision.json`
- `reports/groot_normalization/results/logic_die_pcu_l4_e4_results/rtl_runs.log`
- `reports/groot_normalization/results/logic_die_pcu_l8_e4_results/rtl_runs.log`
- `reports/groot_normalization/results/logic_die_pcu_l16_e4_results/rtl_runs.log`

