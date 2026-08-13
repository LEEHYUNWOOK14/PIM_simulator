# 하드웨어 비용 파이프라인 첨삭 제안서 — Lightweight Physical Feasibility Gate 반영본

## 0. 현재 단계에 대한 재정의

현재 프로젝트는 더 이상 단순한 **RTL functional verification 단계**에만 머물러 있지 않다.

이미 다음 범위까지는 증명되었다.

- 어댑터 RTL 기능 검증 완료
- timing / credit protocol 검증 완료
- Yosys generic synthesis 완료
- `check` 결과 `0 problems`
- 1,644 generic cells로 논리 구조 변환 성공
- 명백한 combinational loop 없음
- 명백한 unintended latch 없음

따라서 현재 판정은 다음과 같다.

| 항목 | 현재 판정 |
|---|---|
| RTL 구현 가능성 | **PASS** |
| 논리 합성 가능성 | **PASS** |
| 어댑터 단독 물리 가능성 | **미증명** |
| PCU + adapter 통합 물리 가능성 | **미증명** |
| production 수준 물리 구현 가능성 | **미증명** |

현재 가장 중요한 다음 단계는 RTL을 다시 뜯어고치는 것이 아니라:

> **“현재 RTL이 실제 standard-cell network로 매핑되고, logic-die 내에 coarse placement 및 global routing 수준에서 무리 없이 배치·연결될 수 있는가?”**

를 확인하는 것이다.

즉 지금 필요한 것은 **lightweight physical feasibility gate**다.

---

# 1. 현재 증명된 범위와 증명되지 않은 범위를 명확히 분리

## 1.1 현재 증명된 것

### A. RTL functional correctness

어댑터가 의도된 functional behavior를 수행한다는 RTL-level evidence가 존재한다.

---

### B. Timing / credit protocol correctness

credit 기반 흐름 제어와 RTL protocol timing 관계가 검증되었다.

단, 반드시 다음을 구분한다.

> **Protocol timing verification ≠ physical STA timing**

즉 현재의 timing 검증은 표준 셀 delay, placement delay, routing RC를 포함하지 않는다.

---

### C. Generic synthesizability

Yosys generic synthesis를 통해 RTL이 논리 네트워크로 정상 변환되었다.

현재 evidence:

```text
Generic cells: 1,644
Yosys check: 0 problems
```

---

### D. 명백한 RTL 구조 오류 부재

현재 범위 내에서 다음과 같은 명백한 structural issue는 발견되지 않았다.

- combinational loop
- unintended latch

---

# 2. 현재 아직 증명되지 않은 핵심 위험

현재 가장 큰 위험은 **“논리적으로 맞는 RTL”이 “실제로 놓고 연결 가능한 물리 구조”인지 아직 모른다는 것**이다.

다음 위험을 보고서와 pipeline 모두에 명시해야 한다.

---

## 2.1 12,288-bit buffer의 register-array 구현 위험

현재 어댑터의 12,288-bit buffer가 memory macro나 SRAM 구조로 추론되지 않고:

> **standard-cell register array**

로 풀리고 있다.

이 경우 물리 구현에서는:

- flip-flop 수 증가
- local routing 증가
- clock tree load 증가
- bank-wide mux 입력 증가
- area overhead 증가

가능성이 있다.

따라서 generic synthesis가 성공했다고 해서 이 buffer가 물리적으로 효율적이라는 뜻은 아니다.

---

## 2.2 145,852 wire bits의 routing pressure

현재 Yosys 구조에서 약:

```text
145,852 wire bits
```

수준의 논리 연결이 존재한다.

이 수치는 직접적인 routing congestion 지표는 아니지만:

> **wide datapath / large fanout / multiplexing 구조가 실제 placement/routing에서 혼잡을 일으킬 가능성**

을 시사하는 structural warning으로 기록할 수 있다.

단 다음처럼 표현해야 한다.

> 145,852 wire bits는 routing congestion의 직접 측정치가 아니다.

---

## 2.3 16-bank wide mux / shift 구조

특히 현재 구조의:

- 16-bank wide selection
- mux
- shift
- redistribution

경로는 다음 위험이 있다.

- high fan-in
- high fanout
- deep combinational cone
- long physical route
- placement fragmentation

따라서 반드시:

- maximum fanout
- longest combinational path
- critical mux cone

을 확인해야 한다.

---

## 2.4 Adapter standalone technology mapping 부재

현재 adapter는 generic synthesis까지는 성공했지만:

> **Sky130 등 실제 characterized standard-cell library에 mapping된 standalone 결과가 없음**

따라서 현재 1,644 generic cells는 물리 area와 직접 연결할 수 없다.

---

## 2.5 PCU + adapter integrated top mapping 부재

가장 중요한 미증명 항목이다.

실제 프로젝트 구조에서는 adapter 단독이 아니라:

```text
PCU
 +
Memory-bound Adapter
```

가 통합되어 동작한다.

따라서 단독 adapter만 mapping 성공해도:

> **통합 top의 실제 combinational cone / fanout / routing 구조**

가 문제가 될 수 있다.

---

## 2.6 Full-top synthesis timeout history

기존 8-lane PCU full-top은 pre-ABC 기준 약:

```text
301,301 flip-flops
```

규모에서 15분 timeout되어:

- final mapped netlist
- full-top STA

가 생성되지 않았다.

따라서 현재 pipeline에서는:

> **full-top synthesis completion 자체를 physical feasibility gate의 prerequisite**

로 두어야 한다.

다만 timeout이 곧 physical impossibility를 의미하는 것은 아니다.

이것은:

- tool runtime
- design size
- synthesis strategy
- register-heavy implementation

문제가 섞인 evidence이므로:

> **“현재 tool flow에서 full-top mapping evidence가 확보되지 않았다”**

정도로 해석한다.

---

## 2.7 기존 산술 block Sky130 mapping의 한계

기존 arithmetic component별 Sky130 mapping 성공은 유용한 evidence다.

하지만 이는 다음만 증명한다.

> 각 arithmetic sub-block이 standalone standard-cell mapping 가능한 구조라는 것.

이를 다음으로 과장하면 안 된다.

> PCU + adapter integrated top이 실제 배치·배선 가능한 구조라는 증거.

따라서 기존 PPA DSE는 **supporting evidence**로 남기고, integrated feasibility evidence와 분리한다.

---

# 3. 현재 파이프라인의 핵심 목표를 수정

기존 목표:

> “hardware cost를 측정한다.”

현재 목표는 다음처럼 더 좁고 명확하게 바꿔야 한다.

> **“현재 RTL이 standard-cell mapping과 coarse physical implementation까지 무리 없이 진행 가능한 구조인지 확인한다.”**

이 단계에서는 아직:

- 최적 PPA
- sign-off timing
- production routing
- final power

를 목표로 하지 않는다.

---

# 4. 새로 정의할 Lightweight Physical Feasibility Gate

## Gate PF-0 — RTL feasibility

### 통과 조건

- functional verification PASS
- credit protocol PASS
- protocol timing PASS
- Yosys generic synthesis PASS
- Yosys `check` = 0 problems
- no obvious combinational loop
- no obvious unintended latch

### 현재 상태

> **PASS**

---

## Gate PF-1 — Adapter standalone technology mapping

### 목적

어댑터 자체가 실제 standard-cell library로 변환 가능한지 확인.

### 최소 통과 조건

- adapter standalone top synthesis 완료
- technology mapping 완료
- unmapped cell = 0
- synthesis error = 0
- combinational loop = 0
- unintended latch = 0
- mapped cell area 산출 가능
- critical path 산출 가능

### 주의

여기서 timing closure를 요구하지 않는다.

목표는:

> **“library cell로 구현 가능한가?”**

이지:

> **“최종 target frequency를 만족하는가?”**

가 아니다.

---

## Gate PF-2 — PCU + adapter integrated technology mapping

### 목적

실제 제안 구조 전체가 논리적으로 통합된 상태에서 standard-cell mapping 가능한지 확인.

### 최소 통과 조건

- integrated top synthesis 완료
- technology mapping 완료
- unmapped cell = 0
- unresolved blackbox = 0
- latch = 0
- combinational loop = 0
- mapped area report 생성
- critical path report 생성
- unconstrained path report 확인

### 가장 중요한 이유

실제 문제는 adapter 단독보다:

```text
PCU
 ↕
adapter
 ↕
bank interface
```

통합 시 발생할 가능성이 높기 때문이다.

---

# 5. Gate PF-3 — Coarse placement

## 목적

standard-cell로 변환된 통합 구조가 실제 floorplan 안에 배치 가능한지 확인.

### 조건

- relaxed utilization
- relaxed clock
- aggressive optimization 금지
- timing closure 목적 아님

### 권장 초기 조건 예

```text
core utilization: 30~50%
relaxed clock period
coarse floorplan
```

실제 값은 tool / library에 따라 조정한다.

---

## PASS 기준

최소한:

- placement 완료
- placement overflow 없음 또는 매우 낮음
- severe density hotspot 없음
- cell legalization 완료
- massive overlap 없음

정도를 확인한다.

---

# 6. Gate PF-4 — Global routing

## 목적

배치된 구조가 실제로 연결 가능한지를 대략적으로 검증.

Detailed routing까지 갈 필요는 없다.

### 확인할 것

- global route completion
- routing overflow
- severe congestion hotspot
- unroutable region
- high-congestion bank interface
- wide mux / buffer 주변 congestion

---

## PASS 판단

다음 상태면 lightweight feasibility PASS로 볼 수 있다.

> global routing이 완료되고, 구조적으로 치명적인 routing overflow 또는 대규모 congestion이 관찰되지 않음.

반대로:

- 특정 bank interface에서 persistent overflow
- buffer register array 주변 severe congestion
- wide mux 주변 집중 congestion

이 발생하면 RTL 또는 floorplan 구조 개선이 필요하다.

---

# 7. 최종 Lightweight Physical Feasibility PASS 조건

최소한 아래까지 통과해야:

> **“물리 구현 가능성이 확인되었다.”**

라고 말하는 것이 적절하다.

---

## 필수 조건

### Adapter standalone

- standard-cell mapping 완료

### Integrated top

- PCU + adapter mapping 완료

### Physical

- coarse placement 완료
- global routing 완료

### Structural

- unmapped cell = 0
- combinational loop = 0
- unintended latch = 0
- unconstrained path 없음 또는 명시적으로 설명 가능

### Routing

- severe placement overflow 없음
- severe global routing congestion 없음

### Physical cost

- mapped cell area
- approximate buffer area
- logic-die available area 대비 utilization

### Datapath risk

- maximum fanout
- longest combinational path
- wide bank interface critical cone

---

# 8. 아직 하지 않아도 되는 것

이번 gate의 목적은 production sign-off가 아니다.

따라서 다음은 필수가 아니다.

---

## 상세 배선

```text
Detailed routing
```

불필요.

---

## DRC / LVS

불필요.

---

## sign-off STA

불필요.

---

## target clock closure

불필요.

---

## IR-drop / EM

불필요.

---

## final CTS

불필요.

---

## silicon-calibrated power

불필요.

---

# 9. Sky130 사용 목적의 claim boundary

Sky130 같은 공개 PDK를 사용하는 목적은 반드시 명확히 써야 한다.

## 잘못된 표현

> Sky130 PPA 분석을 통해 실제 HBM logic-die의 최종 area/timing을 평가하였다.

사용하지 않는다.

---

## 권장 표현

> Sky130 is used only as a public standard-cell proxy to test whether the RTL can be technology-mapped, coarsely placed, and globally routed without obvious structural infeasibility. The results are not treated as production-process PPA.

한국어로는:

> **Sky130은 최종 공정 PPA를 예측하기 위한 것이 아니라, 제안 RTL이 표준 셀로 매핑되고 실제 placement/global-routing flow를 통과할 수 있는지를 확인하기 위한 공개 공정 proxy로만 사용한다.**

라고 명시한다.

---

# 10. 기존 Evidence Contract에서 반드시 남길 것

기존 pipeline의 좋은 구조는 그대로 유지한다.

---

## 10.1 Calibration

반드시 유지.

예:

```text
synthesis_generic
technology_mapped
placed
post_route
measured
```

현재 physical feasibility gate에서는:

```text
technology_mapped
placed
```

까지만 확보하면 충분하다.

---

## 10.2 Claim class

유지.

특히 Sky130 결과는:

> measured silicon result가 아니라 modeled / derived physical proxy

임을 명확히 한다.

---

## 10.3 Source SHA-256

유지.

다음 evidence를 hash freeze한다.

- RTL
- synthesis script
- constraint file
- mapping report
- placement report
- global route report
- congestion report

---

## 10.4 Revision tracking

유지.

현재 lightweight gate에서는 오히려 매우 중요하다.

예:

```text
r0 adapter verified
r1 buffer restructuring
r2 fanout optimization
r3 placement-aware cleanup
```

처럼 physical issue가 발생했을 때 원인을 추적할 수 있다.

---

## 10.5 `null` / `UNAVAILABLE`

유지.

아직 하지 않은:

- power
- thermal
- GR00T
- post-route

은 그대로 null 처리한다.

---

# 11. Pipeline schema에 지금 추가할 항목

현재 가장 중요한 것은 **physical feasibility evidence를 first-class object로 승격**하는 것이다.

---

## 11.1 추천 object

```json
"physical_feasibility": {
  "adapter_mapping": {
    "status": "PENDING",
    "unmapped_cells": null,
    "mapped_area_um2": null,
    "critical_path_ns": null
  },

  "integrated_mapping": {
    "status": "PENDING",
    "unmapped_cells": null,
    "mapped_area_um2": null,
    "critical_path_ns": null,
    "unconstrained_paths": null
  },

  "placement": {
    "status": "PENDING",
    "overflow": null,
    "core_utilization": null
  },

  "global_routing": {
    "status": "PENDING",
    "overflow": null,
    "max_congestion": null
  },

  "structural": {
    "combinational_loop": false,
    "latch": false
  },

  "fanout": {
    "max_fanout": null,
    "max_fanout_net": null
  }
}
```

---

# 12. Buffer를 별도 physical-risk item으로 관리

현재 12,288-bit buffer가 가장 분명한 physical risk 중 하나다.

따라서 일반 `buffer_register` category보다 더 구체적으로 기록하는 것이 좋다.

---

## 추천 field

```json
"buffer_implementation": {
  "logical_bits": 12288,
  "implementation_type": "register_array",
  "mapped_register_count": null,
  "mapped_area_um2": null,
  "share_of_total_area_pct": null,
  "memory_macro_inferred": false
}
```

---

## 활용 목적

technology mapping 이후:

> “전체 adapter area 중 buffer register가 몇 %를 차지하는가?”

를 바로 확인할 수 있다.

만약 buffer가 area/routing 대부분을 차지한다면 그때:

- SRAM inference
- register-file macro
- bank-local buffering
- buffer width 축소
- banking

등의 최적화를 검토하면 된다.

즉 **지금 buffer 구조를 선제적으로 다시 설계하지 말고, mapping evidence를 보고 판단**하는 것이 좋다.

---

# 13. Wide interface 전용 검증 추가

현재 16-bank wide mux / shift 구조는 별도로 관찰해야 한다.

---

## 반드시 수집

```text
maximum fanout
maximum fan-in if available
longest combinational path
logic depth
critical path startpoint
critical path endpoint
critical path cell sequence
```

---

## 특히 보고 싶은 경로

```text
bank input
   ↓
wide mux
   ↓
shift/select
   ↓
buffer / PCU interface
```

이 cone이 critical path인지 확인한다.

---

# 14. Unconstrained path를 반드시 별도로 gate 처리

현재 integrated top에서 아직:

> unconstrained path 확인 없음

이 명확한 gap이다.

따라서 Gate PF-2에 다음 rule을 넣는다.

---

## PASS

```text
unconstrained paths = 0
```

또는:

```text
known async/test paths only
```

이며 모두 명시적으로 exception 처리되어 있음.

---

## FAIL

- 주요 datapath가 unconstrained
- clock definition 누락
- false path가 과도하게 설정됨
- adapter interface timing이 무제약

---

# 15. Logic-die 면적과 비교하는 방식

이번 단계에서는 정확한 HBM production area를 주장하지 않는다.

대신:

```text
mapped standard-cell area
```

와

```text
assumed / literature-based available logic-die budget
```

를 분리한다.

---

## 권장 표

| 항목 | 값 | Evidence class |
|---|---:|---|
| Adapter mapped cell area | X | technology-mapped |
| PCU + adapter mapped area | X | technology-mapped |
| Buffer mapped area | X | technology-mapped |
| Assumed available logic region | X | assumed |
| Approx. utilization | X% | derived |

---

## 중요한 claim

> utilization 수치는 feasibility screening용 proxy이며 실제 Samsung HBM2 production floorplan utilization이 아니다.

---

# 16. 기존 PPA DSE 보고서의 역할

기존 arithmetic component별 Sky130 mapping evidence는 삭제하지 않는다.

---

## 남길 것

다음 supporting evidence로 사용한다.

> 주요 산술 연산 블록은 standalone standard-cell mapping이 가능했다.

---

## 하지만 분리할 것

다음 주장과는 분리한다.

> integrated PCU + adapter physical feasibility

즉 보고서 구조:

```text
Prior block-level evidence
        ↓
Arithmetic blocks mapped successfully

Current integrated evidence
        ↓
Adapter mapping
PCU + adapter mapping
Placement
Global routing
```

로 가져간다.

---

# 17. 현재 README 수정 방향

기존 README 맨 위에 아래 section을 추가하는 것을 권장한다.

---

## Current implementation status

```markdown
## Current implementation status

The memory-bound adapter has completed RTL-level functional and structural
validation.

Verified:

- RTL functional behavior;
- timing/credit protocol behavior;
- Yosys generic synthesis;
- `check` with zero reported problems;
- successful lowering to 1,644 generic cells;
- no identified obvious combinational loop or unintended latch.

These results establish RTL and logical synthesizability only.

Physical feasibility remains unproven because:

- the 12,288-bit adapter buffer is currently lowered as registers;
- the design contains 145,852 wire bits and a 16-bank wide mux/shift structure;
- standalone adapter technology mapping is not yet available;
- integrated PCU + adapter mapping and physical implementation are not yet available;
- integrated fanout, combinational depth, and unconstrained paths have not yet
  been bounded.

The next required gate is a lightweight physical-feasibility check using a public
standard-cell proxy such as Sky130.

The purpose of Sky130 is not final-process PPA prediction. It is used only to test
whether the design can be mapped, coarsely placed, and globally routed without
obvious physical infeasibility.
```

---

# 18. 수정된 전체 단계

```text
[PASS]
RTL Architecture
      │
      ▼
Memory-bound Adapter
      │
      ▼
Functional Verification
      │
      ├─ RTL function PASS
      ├─ credit protocol PASS
      ├─ protocol timing PASS
      └─ Yosys check 0 problems
      │
      ▼
Generic Synthesis
      │
      ├─ 1,644 generic cells
      └─ no obvious loop/latch
      │
      ▼
────────────────────────────────
CURRENT PHYSICAL FEASIBILITY GAP
────────────────────────────────
      │
      ▼
Adapter Standalone Mapping
      │
      ▼
PCU + Adapter Integrated Mapping
      │
      ├─ unmapped cells
      ├─ unconstrained paths
      ├─ max fanout
      └─ combinational depth
      │
      ▼
Coarse Placement
      │
      ├─ overflow
      └─ utilization
      │
      ▼
Global Routing
      │
      ├─ congestion
      └─ routing overflow
      │
      ▼
Physical Feasibility PASS
      │
      ▼
RTL Freeze
      │
      ▼
PPA / Workload / GR00T
```

---

# 19. 현재 단계에서 RTL Freeze 조건

현재 RTL을 최종 freeze하기 전에 최소한 다음을 요구한다.

---

## 필수

- adapter standalone standard-cell mapping PASS
- integrated PCU + adapter mapping PASS
- coarse placement PASS
- global routing PASS
- no unmapped cell
- no unexpected latch
- no combinational loop
- no unexplained unconstrained path
- no severe placement overflow
- no severe routing congestion

---

## 확인용

- mapped area
- buffer area fraction
- max fanout
- longest combinational path
- approximate logic-die utilization

---

# 20. Physical Feasibility PASS 이후 할 일

이 gate가 PASS된 이후에야 기존 hardware-cost pipeline을 본격적으로 활성화한다.

---

## 다음 단계

### PPA

- mapped area
- timing
- later activity-based power

### Workload

- memory traffic counters
- GR00T normalization trace
- Host-HBM bytes
- cross-bank bytes

### 최종

- Hardware Cost
vs
- Memory I/O Reduction

---

# 21. 지금은 하지 말아야 할 최적화

현재 stage에서 다음을 미리 최적화하지 않는다.

---

## buffer architecture redesign

mapping 결과를 본 뒤 결정.

---

## lane count sweep

통합 구조 physical feasibility 이후.

---

## PCU count sweep

workload evidence가 붙은 뒤.

---

## target clock aggressive optimization

현재 목적 아님.

---

## DRC-clean / detailed routing

현재 목적 아님.

---

# 22. 현재 pipeline의 핵심 판정 구조

최종적으로 pipeline이 자동 생성해야 하는 상태는 다음과 같다.

```text
RTL_FEASIBILITY          PASS
LOGICAL_SYNTHESIS        PASS
ADAPTER_TECH_MAPPING     PENDING
INTEGRATED_TECH_MAPPING  PENDING
COARSE_PLACEMENT         PENDING
GLOBAL_ROUTING           PENDING
PHYSICAL_FEASIBILITY     PENDING
PRODUCTION_SIGNOFF       NOT_TARGETED
```

Gate를 통과한 뒤:

```text
RTL_FEASIBILITY          PASS
LOGICAL_SYNTHESIS        PASS
ADAPTER_TECH_MAPPING     PASS
INTEGRATED_TECH_MAPPING  PASS
COARSE_PLACEMENT         PASS
GLOBAL_ROUTING           PASS
PHYSICAL_FEASIBILITY     PASS
PRODUCTION_SIGNOFF       NOT_TARGETED
```

형태가 되어야 한다.

---

# 23. 보고서에서 사용할 추천 문장

## 현재

> The proposed memory-bound adapter has been functionally verified at the RTL level and successfully synthesized into a 1,644-cell generic logic network with no Yosys check errors or identified obvious combinational loops or unintended latches. These results demonstrate RTL and logical synthesizability, but do not yet establish physical feasibility.

---

## Lightweight gate 통과 후

> The integrated PCU–adapter design was additionally mapped to a public standard-cell library and successfully completed coarse placement and global routing under relaxed constraints without severe placement overflow or routing congestion. These results are used only as a proxy for physical implementability, not as production-process PPA or sign-off evidence.

---

# 24. 최종 권고

현재 상황에서는 **RTL을 다시 설계하거나 곧바로 GR00T / Cost–Benefit 단계로 넘어가는 것 모두 권장하지 않는다.**

가장 적절한 흐름은:

```text
현재 RTL 유지
   ↓
Standalone adapter mapping
   ↓
Integrated PCU + adapter mapping
   ↓
Coarse placement
   ↓
Global routing
   ↓
Physical feasibility PASS
   ↓
RTL freeze
```

이다.

핵심은:

> **현재 RTL은 이미 “논리적으로 구현 가능” 단계는 통과했다. 이제 최종 RTL freeze 전에 “표준 셀로 실제로 놓고 연결할 수 있는가”를 lightweight physical gate로 한 번 확인하면 된다.**

Sky130은 그 gate를 위한 **physical feasibility proxy**로 쓰고, 최종 공정 PPA나 production sign-off를 주장하는 데 사용하지 않는다.

---

# 25. 한 줄 요약

> **현재 pipeline의 다음 목표는 PPA 최적화가 아니라, 12,288-bit register buffer와 16-bank wide datapath를 포함한 PCU+adapter 통합 구조가 standard-cell mapping → coarse placement → global routing까지 통과하는지를 검증하여 “Physical Feasibility PASS”를 확보하는 것이다.**
