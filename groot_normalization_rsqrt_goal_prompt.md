# 목표: GR00T 정규화 연산의 계층형 HBM2-PIM 매핑 및 RSQRT 배치 비교

## 참조 경로

- 현재 RTL 및 물리 구현: `C:\Users\Chandler\OneDrive\2026-하계\STOB 반도체 경진대회\STOB_PIM2`
- 기존 GR00T 시뮬레이션: `C:\Users\Chandler\OneDrive\2026-하계\STOB 반도체 경진대회\STOB_PIM_pure_layornorm`
- 단계별 로드맵: `C:\Users\Chandler\Downloads\STOB_PIM_phase_roadmap_easy.html`

## 최종 목표

NVIDIA GR00T N1.7의 LayerNorm/RMSNorm을 대상으로 다음 네 구조를 동일한 workload와 시스템 가정에서 비교한다.

1. GPU baseline
2. Bank-only PIM
3. Logic-only PIM
4. Bank-PCU + Logic-PCU Hierarchical PIM

특히 reduction 이후 필요한 RSQRT를 Logic-PCU 내부에서 처리하는 경우와 GPU/host에서 처리하고 결과를 다시 HBM으로 가져오는 경우를 비교하여 다음 질문에 정량적으로 답한다.

> GR00T 정규화에서 RSQRT와 전역 reduction을 Logic-PCU에 넣는 것이 GPU 왕복보다 실제로 효율적인가? 유리하다면 어떤 tensor shape, bank 수, PCU 수 및 통신 지연 조건에서 유리한가?

Logic-PCU가 항상 유리하다고 가정하지 않는다. 측정 결과에 따라 GPU/host offload가 더 적합하다는 결론도 허용한다.

## 현재 기준선

작업 시작 시 다음 사실을 코드와 보고서에서 재확인하고 baseline으로 고정한다.

- 현재 RTL ISA는 ADD, MUL, MAC, MAD, MOV, FILL, NOP, JUMP, EXIT 중심이다.
- 현재 RTL에는 native RSQRT 명령과 완전한 LayerNorm/RMSNorm 엔진이 없다.
- reduction 관련 RTL 블록이 GR00T normalization 전체 경로와 연결되었는지는 별도로 확인한다.
- C++ PIMSimulator의 BatchNorm 지원을 RTL의 BatchNorm 지원으로 간주하지 않는다.
- 기존 GR00T 실험은 LayerNorm 269회와 RMSNorm 64회를 대상으로 한다.
- 기존 실험은 Bank-PIM element-wise 단계만 측정했다.
- host reduction, RSQRT, 왕복 및 동기화 비용은 기존 cycle에 포함되지 않았다.
- 기존 입력은 실제 pretrained activation이 아닌 deterministic synthetic FP16이다.
- 실제 GR00T dtype은 BF16이지만 기존 simulator는 FP16이다.
- 현재 GDS는 physical-flow integration 증거이며 DRC-clean 또는 tape-out-ready 결과가 아니다.

기존 RTL 감사에서 완료한 항목은 회귀가 발견되지 않는 한 처음부터 반복하지 않는다.

## 핵심 비교 원칙

RSQRT는 일반적으로 normalization row의 reduction 결과에 한 번 적용되는 scalar 연산이다. RSQRT 연산기만 비교하지 말고 다음 전체 경로를 비교한다.

```text
Bank 데이터 읽기
→ local SUM/SUMSQ
→ cross-bank partial-result 전송
→ global reduction
→ mean/variance 또는 mean-square 계산
→ epsilon 적용
→ RSQRT
→ normalization scalar broadcast
→ Bank element-wise normalize/scale/bias
```

GPU baseline에는 데이터 준비, interconnect 전송, queue, kernel launch, reduction, RSQRT, 동기화, 결과 반환 및 Bank 연산 재개 비용을 모두 포함한다. 전체 tensor를 GPU에 보내는 방식과 partial statistics만 보내는 방식도 구분한다.

## Phase 0: 재현 가능한 baseline 고정

1. 두 저장소의 Git 상태와 기존 사용자 변경을 확인하고 보존한다.
2. 기존 테스트와 문서를 실행 가능한 범위에서 재검증한다.
3. RTL, C++ simulator, analytical model의 지원 연산을 별도 표로 작성한다.
4. 기존 GR00T cycle 값에 포함된 비용과 빠진 비용을 구분한다.
5. baseline 결과와 재현 명령을 문서화한다.

## Phase 1: GR00T normalization workload 확정

다음 항목을 profile manifest로 작성한다.

- LayerNorm/RMSNorm 종류
- tensor shape, rows, hidden dimension
- epsilon과 affine 여부
- 호출 횟수
- FP16/BF16 dtype
- invocation별 read/write byte
- reduction scalar 수
- 동적 sequence length 범위
- 전체 inference 중 latency와 traffic 비중

우선 기존에 검증된 다음 profile을 사용한다.

- LayerNorm `[280, 2048]`
- LayerNorm `[41, 1536]`
- RMSNorm `[280, 2048]`
- RMSNorm `[8960, 64]`

가능한 범위에서 실제 GR00T activation, BF16, 동적 sequence length, 제외된 vision LayerNorm shape 및 실제 호출 횟수를 보완한다. 확인할 수 없는 항목은 추정하지 말고 `측정`, `가정`, `미검증`으로 구분한다.

## Phase 2: 비교 구조 정의

### Case A: GPU baseline

- normalization 전체를 GPU에서 수행한다.
- tensor read/write와 kernel launch 비용을 포함한다.
- 가능하면 실제 GPU profiling을 사용한다.
- 측정이 불가능하면 명시적인 parameter 기반 분석 모델을 만들고 실측처럼 표현하지 않는다.

### Case B: Bank-only PIM

- Bank-PCU에서 element-wise 및 local reduction을 수행한다.
- global reduction과 RSQRT는 host/GPU에서 수행한다.
- partial statistic 전송, 왕복 지연 및 broadcast 비용을 포함한다.

### Case C: Logic-only PIM

- 원본 데이터를 Logic-PCU로 이동하여 reduction, RSQRT, normalization을 수행한다.
- Logic die 데이터 traffic과 queue delay를 포함한다.

### Case D: Hierarchical PIM

- Bank-PCU: partial SUM/SUMSQ 및 element-wise normalization
- Logic-PCU: global reduction, mean/variance, epsilon 및 RSQRT
- Logic-PCU의 mean/inv-std 또는 inv-RMS를 Bank-PCU로 broadcast
- cross-bank contention, FIFO, backpressure 및 broadcast 비용 포함

필요하면 다음 보조 case도 추가한다.

- Logic-PCU reduction + host/GPU RSQRT
- Logic-PCU reduction + LUT RSQRT
- Logic-PCU reduction + LUT seed/Newton-Raphson RSQRT
- exact 또는 vendor-IP 상당 RSQRT

## Phase 3: 모델링과 break-even 분석

RSQRT RTL을 바로 추가하지 말고 parameterized analytical/cycle model을 먼저 만든다.

최소 sweep parameter:

- hidden size: 64, 256, 512, 1024, 1536, 2048, 4096, 8192
- row 수: 실제 GR00T shape와 소형/대형 범위
- bank 수: 2, 4, 8, 16
- Bank-PCU 및 Logic-PCU 수: 1, 2, 4, 8, 16
- interconnect bandwidth와 one-way latency
- queue 및 synchronization latency
- reduction tree latency
- RSQRT latency와 initiation interval
- broadcast latency
- FP16/BF16 변환 비용
- clock frequency
- Logic-PCU area/power overhead

각 case의 latency를 local reduction, cross-bank transfer, global reduction, mean/variance, RSQRT, broadcast, element-wise apply, queue/synchronization, mode switching 및 GPU/host transfer로 분해한다.

다음 break-even 조건을 계산한다.

- Logic-PCU RSQRT가 GPU/host offload보다 빨라지는 최소 interconnect latency
- 전체 tensor offload와 partial-statistic offload의 교차점
- RSQRT latency/area 변화에 따른 민감도
- bank와 PCU 수 증가에 따른 병목 이동
- RSQRT보다 reduction 또는 broadcast가 지배적인 구간

## Phase 4: 정확도와 RSQRT 후보 검증

PyTorch FP32 결과를 canonical golden reference로 사용한다.

검증 입력:

- random activation
- all-zero와 constant vector
- 양수/음수 혼합
- 작은 variance
- 큰 offset과 작은 variance
- epsilon 근처 입력
- overflow/underflow 가능 입력
- 확보할 수 있다면 실제 GR00T activation

기록 항목:

- maximum/mean absolute error
- relative error
- RMSE 또는 NRMSE
- FP16/BF16 차이
- RSQRT approximation error
- NaN/Inf 발생 여부
- staged RTL-equivalent reference mismatch
- 가능하면 Welford와 SUM/SUMSQ의 차이

RSQRT 후보로 LUT-only, LUT+Newton-Raphson 1회/2회, 정확한 software reference 및 합성 가능한 기존 IP 상당 구조를 비교한다. 정확도 허용치는 사전에 명시하고 사후에 임의로 넓히지 않는다.

## Phase 5: RTL 구현

분석과 정확도 결과에서 Logic-PCU 내장 방식의 가능성이 확인된 경우에만 RTL을 확장한다.

Bank-PCU 후보 기능:

- `REDUCE_SUM`
- `REDUCE_SUMSQ`
- partial-result packet 생성
- `NORM_APPLY`
- scalar broadcast 수신

Logic-PCU 후보 기능:

- partial-result input FIFO
- cross-bank reduction tree
- mean/variance 또는 mean-square 계산
- epsilon 처리
- RSQRT unit
- normalization scalar register
- Bank-PCU broadcast
- valid/ready backpressure
- tag/epoch 기반 row 정합성

기존 4-bit opcode 공간과 충돌 여부를 확인하고 필요하면 encoding 확장안을 문서화한다.

RSQRT RTL에서는 handshake, pipeline latency, initiation interval, stall/backpressure, 연속 row, corner case, FP16/BF16, NaN/Inf/zero/negative 정책, reset 및 synthesis 가능성을 검증한다. behavioral `real`, DPI 또는 testbench 전용 연산을 synthesizable RTL로 간주하지 않는다.

## Phase 6: RTL 측정값을 simulator에 반영

다음 RTL 측정값을 PIMSimulator 또는 별도 system simulator에 반영한다.

- Bank/Logic reduction cycle
- RSQRT latency와 throughput
- broadcast cycle
- FIFO/queue depth
- clock frequency
- 합성 area
- 합성 power 또는 명시적인 proxy
- mode-switch 비용

Simulator에서는 normalization latency, GR00T projected latency, bank/Logic-PCU utilization, cross-bank 및 GPU/host traffic, queue delay, energy, area overhead와 단계별 병목을 출력한다.

한 번 측정한 profile에 호출 횟수를 곱한 값은 반드시 `projected`로 표시하여 실제 반복 실행과 구분한다.

## Phase 7: 최종 비교 및 의사결정

네 기본 구조를 같은 workload, dtype, clock, bandwidth 및 호출 횟수 조건에서 비교한다.

최종 산출 그래프:

- normalization latency와 단계별 breakdown
- memory/interconnect traffic
- estimated energy
- synthesized area overhead
- RSQRT 정확도 대 area/latency
- hidden size/bank 수/PCU 수 sensitivity
- GR00T normalization speedup
- 가능한 경우 GR00T end-to-end speedup

최종 결론에는 다음을 포함한다.

1. Logic-PCU RSQRT 탑재 권고 여부
2. 권고가 성립하는 workload와 시스템 조건
3. GPU/host offload가 더 유리한 조건
4. RSQRT, reduction, traffic, broadcast 중 실제 지배 병목
5. area/power 증가를 감수할 가치
6. 경진대회에서 주장 가능한 결과와 주장하면 안 되는 결과
7. 다음 RTL 구현 우선순위

## 필수 산출물

- baseline 및 지원 범위 보고서
- GR00T normalization profile manifest CSV/JSON
- 네 구조의 공통 parameter 파일
- cycle/traffic/energy analytical model
- RSQRT 정확도 비교 결과
- RTL testbench와 회귀 결과
- synthesis area/timing 결과
- simulator 통합 결과
- parameter sweep CSV와 그래프
- 최종 architecture decision 문서
- 재현 명령과 알려진 한계

모든 표와 그래프에 단위, workload, dtype, clock, 측정/추정 여부를 표시한다.

## 완료 조건

- 기존 결과에서 빠졌던 reduction, RSQRT, 왕복 및 동기화 비용이 포함된다.
- GPU, Bank-only, Logic-only, Hierarchical 네 case가 같은 조건으로 비교된다.
- 기존 GR00T의 네 대표 shape가 포함된다.
- RSQRT 후보의 정확도와 latency/area trade-off가 제시된다.
- Logic-PCU 내장과 GPU/host offload 사이의 break-even 조건이 제시된다.
- RTL 수정 시 기존 회귀와 신규 normalization 테스트가 통과한다.
- simulator 값과 RTL 측정값의 출처가 추적 가능하다.
- 측정값, 외삽값 및 추정값이 명확히 구분된다.
- 제한 사항이 최종 결론에 반영된다.
- 결과가 Logic-PCU 탑재에 불리해도 그대로 보고한다.

## 작업 규칙

- 사용자 기존 변경을 덮어쓰거나 삭제하지 않는다.
- 작업 전후 `git status`를 확인한다.
- 문서 주장보다 RTL, 테스트, synthesis log를 우선한다.
- 근거 없는 GPU 성능, power 또는 area 값을 만들지 않는다.
- 외부 자료는 공식 NVIDIA, PyTorch, JEDEC 및 도구 공식 문서를 우선한다.
- 각 Phase 종료 시 결과, 한계와 다음 단계 판단을 보고한다.
- 장시간 작업도 안전한 범위에서 완료 조건을 향해 계속 진행한다.
