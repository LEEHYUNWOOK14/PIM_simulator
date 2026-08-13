# Phase 5 raw-vector-to-scalar Hierarchical streaming top 보고서

## 판정

**END-TO-END REDUCTION PASS** — raw FP16 bank vectors부터 local SUM/SUMSQ, bank skew barrier, parallel global reduction, mean/variance/epsilon 및 RSQRT scalar response까지 하나의 synthesizable top으로 연결됐다.

이 결과로 Hierarchical normalization의 reduction/scalar 절반은 production 후보 구조 기준으로 닫혔다. scalar broadcast와 Bank-PCU affine apply는 아직 같은 top에 연결되지 않았으므로 전체 normalization output end-to-end 완료는 아니다.

## 통합 계층

```text
16 × 4-lane Bank vector input
→ 16 × multi-row Bank SUM/SUMSQ reducer
→ per-bank result FIFO
→ row tag/mask barrier
→ 16-bank parallel SUM/SUMSQ tree
→ 8 × scalar normalization engine
→ tagged mean/inv-std 또는 inv-RMS response
```

config는 다음 블록에 원자적으로 전달된다.

- expected active Bank reducer
- Logic barrier
- row tag, mode, vector count, inv-hidden, epsilon

모든 활성 bank와 barrier가 ready일 때만 config handshake가 발생하므로 일부 bank만 새 row를 시작하는 split-context 상태를 방지한다.

## 기능 검증

축소 BANKS=4, LANES=4, scalar engines=8 구성에서 두 RMSNorm row를 처리했다.

- 각 bank에 raw FP16 1.0 vector 입력
- bank별 vector acceptance를 0/1/2/3 cycle로 어긋나게 구성
- 각 bank local SUM=4, SUMSQ=4
- global SUMSQ=16
- inv-hidden=1/16
- mean-square=1
- LUT RSQRT 결과 `0x3bfa`
- 두 row tag 순서/중복/누락 확인
- 최종 response stall 확인

```text
HIERARCHICAL_NORMALIZATION_STREAMING_TOP_TB PASS rows=2 raw_vectors=8 skew_span=3 cycles=24
```

bank protocol, tag mismatch, unexpected bank, invalid config 및 scalar allocation error는 모두 발생하지 않았다.

## 전체 top 합성

조건:

- BANKS=16
- LANES=4
- scalar engines=8
- Bank result FIFO depth=4
- FP16 SUM/SUMSQ 및 LUT256 RSQRT
- Yosys generic synthesis

```text
HIERARCHICAL_NORMALIZATION_STREAMING_TOP_SYNTHESIS PASS banks=16 lanes=4 engines=8
Found and reported 0 problems.
```

| 항목 | 결과 |
|---|---:|
| generic cells | 953,623 |
| wires | 944,688 |
| wire bits | 1,024,828 |
| DFFE/DFF 계열 | 8,550 |
| top-level port bits | 21,729 |

이전 독립 블록 합계 proxy는 953,549 cells였고 실제 통합 합성은 953,623 cells로 74 cells만 차이 난다. 따라서 지금까지 사용한 additive generic-area proxy가 이 구성에서는 일관적이었다.

## 의미

- Bank reducer 16개가 실제 top hierarchy에 존재한다.
- Bank별 FIFO와 tag barrier가 실제 ready/valid 경로로 연결됐다.
- Logic tree는 16 bank partial을 병렬로 받는다.
- 8 scalar engines가 tree output을 interleave한다.
- 16 complete reduction engine 복제는 필요하지 않다.
- raw input에서 RSQRT scalar까지의 데이터·context 경로가 더 이상 분석 모델만의 가정이 아니다.

## 면적 해석

953,623 generic cells는 큰 구조다. 기존 Bank-PCU/DRAM/PHY 면적을 포함하지 않은 normalization incremental top만의 값이며 technology area가 아니다.

주요 증가 원인은:

- 16개 Bank vector multiplier/add tree 복제
- Bank별 result FIFO register array
- 16-bank parallel Logic adder tree
- 8개 scalar FP16/RSQRT engine

따라서 경진대회에서는 “RSQRT 하나의 작은 추가 비용”으로 표현하면 안 된다. 실제 고처리량 Hierarchical 후보는 약 0.95M generic cells 규모의 reduction/scalar 계층이다.

## 남은 경로

아직 연결되지 않은 항목:

1. Logic scalar response를 16 Bank-PCU SRF로 broadcast
2. row tag와 activation 재읽기/apply 시점 정합
3. 기존 Bank-PCU ADD/MUL affine microprogram 발행
4. gamma/beta GRF 공급 및 reuse
5. normalized vector output 수집
6. random multi-row skew/backpressure stress
7. BF16 또는 BF16-equivalent 정확도
8. technology timing/power

## 현재 결론

기능 구현 가능성은 증명됐다. 그러나 다음 두 조건은 여전히 최종 권고 게이트다.

- 평균 bank skew가 약 1.28 cycles/row 미만인지
- 약 953,623 generic-cell reduction/scalar 구조의 physical area/power를 감수할 가치가 있는지

이 조건 중 하나라도 실패하면 GPU/host offload 또는 Bank-only 구조가 더 적합할 수 있다.

## 재현

```bash
bash verification/groot_normalization/run_hierarchical_normalization_streaming_top_test.sh
bash verification/groot_normalization/run_hierarchical_normalization_streaming_top_synthesis.sh
```

산출물:

- `rtl/hierarchical_normalization_streaming_top.sv`
- `results/hierarchical_normalization_streaming_top_yosys.log`
