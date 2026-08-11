# Phase 5 진행 보고서: Hierarchical Normalization End-to-End Datapath

- 수행일: 2026-08-11
- RTL: `rtl/hierarchical_normalization_datapath.sv`
- 판정: **FUNCTIONAL E2E PASS — 4-bank reduce→Logic RSQRT→Bank apply 완료, dedicated 복제 면적 과다**

## 1. 연결된 전체 경로

다음 datapath를 하나의 synthesizable hierarchy로 연결했다.

```text
Bank 0..3 activation stream
→ bank_normalization_local_reducer ×4
→ partial SUM/SUMSQ arbitration
→ logic_normalization_reduction_engine
→ global SUM/SUMSQ
→ mean/variance 또는 mean-square
→ epsilon
→ LUT256 RSQRT
→ scalar broadcast barrier
→ bank_normalization_apply ×4
→ normalized output stream
```

row begin 시 mode, tag, expected bank mask, bank별 element count, inv-hidden 및 epsilon을 설정한다. 모든 expected bank의 partial이 도착해야 scalar broadcast가 발생하며, 모든 Bank apply engine이 config를 받을 준비가 되어야 response가 소비된다.

## 2. 동기화 계약

- 모든 expected Bank reducer와 Logic reducer가 ready일 때만 row begin 수락
- local reducer 결과는 고정 우선순위 arbiter로 Logic engine에 전달
- row tag와 bank mask로 partial context 검증
- Logic scalar 결과는 모든 active Bank apply engine에 동시에 config
- 이전 row의 apply `last`가 모두 끝나기 전에는 다음 begin 차단
- Bank output은 개별 ready/valid backpressure 지원

따라서 mean/inv가 준비되기 전에 element-wise apply가 시작되는 race를 방지한다.

## 3. End-to-end 검증

4개 bank, bank당 4개 element로 두 transaction을 수행했다.

### RMSNorm row

- 모든 input: +1
- total elements: 16
- global mean-square: 1
- LUT256 inv-RMS: `0x3bfa`
- expected output 16개: `0x3bfa`

### LayerNorm row

- 각 bank input: `[-1,+1,-1,+1]`
- global mean: 0
- global variance: 1
- LUT256 inv-std: `0x3bfa`
- expected output: `-0x3bfa/+0x3bfa` 부호 교대

결과:

```text
HIERARCHICAL_NORMALIZATION_DATAPATH_TB PASS rows=2 banks=4 outputs=32
```

- scalar mean/inv mismatch: 0
- normalized output mismatch: 0
- tag/last mismatch: 0
- protocol error: 0

초기 병렬 stimulus에서 packed valid vector의 dynamic bit-select read-modify-write race가 발생했으나, 결정적인 bank-interleaved stimulus로 수정했다. RTL protocol error를 무시하거나 mask하지 않았다.

## 4. Yosys generic synthesis

4-bank dedicated hierarchy 결과:

| 항목 | 결과 |
|---|---:|
| wires | 52,343 |
| generic cells | 183,082 |
| AND | 49,674 |
| MUX | 67,415 |
| OR | 29,389 |
| DFF | 1,099 |

합성 log: `results/hierarchical_normalization_datapath_yosys.log`

이 hierarchy에는 다음이 포함된다.

- local reducer 4개
- Bank apply engine 4개
- Logic global reducer 1개
- scalar finalize engine 1개
- RSQRT 1개
- arbitration/barrier control

## 5. 면적 관점의 핵심 판정

4-bank 전용 복제 구조가 183,082 generic cells이므로 이를 HBM2의 16-bank 및 다수 channel/PIM block에 그대로 확장하는 것은 비현실적일 가능성이 높다.

특히 비용의 중심은 Logic RSQRT가 아니다.

- RSQRT primitive: 2,885 generic cells
- Bank local reducer: bank당 15,307 generic cells
- Bank apply: bank당 20,777 generic cells

즉, 팀원이 우려한 “Logic PCU에 RSQRT를 넣는 비용”보다 Bank마다 전용 reduction/apply arithmetic을 복제하는 비용이 훨씬 크다.

## 6. 권장 구조 수정

기능적으로 검증된 전용 datapath는 correctness reference로 유지하되 최종 production 구조는 다음 순서로 최적화한다.

1. 기존 Bank-PCU ADD/MUL/GRF를 normalization apply microprogram으로 재사용
2. local reducer는 bank당 전용보다 channel 또는 PIM-block 공유 pipeline 검토
3. Logic RSQRT는 공유 scalar engine으로 유지
4. row queue/tag context를 추가해 shared engine utilization 향상
5. dedicated와 shared/microprogram 구조를 같은 workload에서 cycle/area 비교

Logic-PCU RSQRT를 제거해도 전체 면적 절감은 제한적이며, Bank 전용 arithmetic 복제 여부가 더 큰 설계 변수다.

## 7. 성능 한계

- local element stream II 1
- partial arbiter는 cycle당 bank 하나
- scalar engine은 한 row context, 약 5-cycle finalize
- apply engine은 II 1이나 긴 combinational FP16 chain
- 다음 row는 이전 row의 모든 Bank `last` 이후 시작

현재 구조는 기능적 barrier를 보장하지만 high-throughput multi-row pipeline은 아니다. `[8960,64]` Q/K RMSNorm에는 row-level double buffering 또는 context queue가 필요하다.

## 8. 정확도 한계

- FP16 sequential SUM/SUMSQ
- FP16 mean/variance
- LUT256 RSQRT
- 테스트 row는 16 elements
- 실제 GR00T BF16/activation이 아님
- affine parameter는 gamma=1, beta=0인 E2E test

Phase 4의 random/edge 정확도 결과와 함께 해석해야 하며, 실제 GR00T 모델 품질을 증명하는 결과는 아니다.

## 9. 재현 명령

```powershell
wsl bash -lc "cd '/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2' && bash verification/groot_normalization/run_hierarchical_normalization_test.sh"
```

## 10. 다음 단계

1. dedicated E2E 경로를 correctness reference로 고정
2. 기존 Bank-PCU microprogram 기반 apply 경로 구현
3. shared local reduction 구조 구현
4. dedicated/shared/microprogram cycle 및 generic/technology area 비교
5. GR00T 대표 shape를 row trace로 재생
6. measured latency/II를 Phase 3 모델에 반영
7. production top의 normalization sideband를 internal Bank path로 대체/병합

## 11. 판정

Bank activation stream부터 normalized output까지의 계층형 RTL 기능 경로는 최초로 end-to-end 완료됐다. 그러나 dedicated Bank engine 복제 면적이 커 최종 production architecture로 확정할 수 없다. Phase 5는 area-aware shared/microprogram 구조와 실제 top internal 연결을 위해 계속 진행한다.
