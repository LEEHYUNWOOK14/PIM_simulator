# Phase 5 — 실제 Bank-PCU를 포함한 raw-to-affine 축소 E2E

## 구현

`hierarchical_normalization_bank_core_top.sv`에서 다음 경로를 하나로 연결했다.

```text
동일 activation의 4-lane 통계 stream
  → bank reduction
  → Logic PCU tree + FP16 RSQRT
  → tag/mask context + scalar broadcast
  → bank SRF write + normalization microprogram
  → 실제 bank_pim_core vector ALU
  → 최종 M_OUT result
```

각 256-bit activation은 16 FP16 lane이며, 통계 reducer에는 동일 데이터를 4-lane vector 네 개로 분할 입력했다. 따라서 reduction과 affine apply가 같은 activation을 사용한다.

## 기능 검증

```text
HIERARCHICAL_NORMALIZATION_BANK_CORE_TOP_TB PASS rows=2 active_banks=4 results=12 replay_vectors=64 stalls=1 cycles=54
```

| Row | Mode | Mask | Input / parameters | 최종 결과 |
|---|---|---:|---|---|
| `0xb000` | RMSNorm | `0101` | x=1, gamma=2 | 모든 lane `0x3ffa` |
| `0xb001` | LayerNorm | `1010` | x=1, epsilon=1, gamma=2, beta=0.5 | 모든 lane `0x3800` |

검증 범위:

- 활성 bank별 동일 activation 통계 16개 element 반영
- raw-vector bank skew
- RSQRT LUT 결과를 이용한 실제 FP16 vector 연산
- gamma/beta GRF_B preload
- 한 Bank-PCU result stall 및 command backpressure
- RMSNorm 4 results, LayerNorm 8 results, 총 12 result handshake
- row tag, target mask, 최종 `M_OUT`, 전체 16 lane
- protocol/config/context/command 오류 없음

## generic synthesis

| Banks | Generic cells | Wire bits | Port bits | 상태 |
|---:|---:|---:|---:|:---:|
| 4 | 1,144,779 | 1,224,019 | 33,916 | PASS |
| 16 | 4,088,425 | 4,363,917 | 120,400 | PASS |

16-bank command-issue top 961,299 cells 대비 실제 16개 Bank-PCU 포함 증가는 3,127,126 cells, 즉 약 195,445 cells/Bank-PCU다.

이 증가는 Yosys가 각 Bank-PCU의 256-bit FP16 ALU뿐 아니라 `GRF_A/B` 배열을 generic register와 mux로 전개한 결과다. 실제 macro/register-file 구현 면적과 같지 않으며, 기술 매핑 PPA 주장에 사용할 수 없다. 반대로 Bank-PCU 본체를 제외한 수치로 전체 PIM 비용을 주장해서도 안 된다는 점을 보여준다.

## 달성 판정

- **RTL_MEASURED:** 축소 4-bank 환경에서 raw activation 통계 입력부터 실제 Bank-PCU의 affine normalized vector 결과까지 기능 E2E가 연결됐다.
- **RTL_MEASURED_GENERIC_SYNTHESIS:** 같은 구조를 16-bank로 elaborate/synthesize하고 strict structural check를 통과했다.

## 아직 남은 구조적 제한

- activation replay는 외부 입력 포트로 제공되며 내부 replay buffer/DRAM read scheduler가 없다.
- 명령은 `EVEN_BANK` operand에 고정되어 odd-bank/address 순회를 하지 않는다.
- gamma/beta preload는 외부 제어이며 weight reuse policy가 없다.
- 최종 result를 row 완료로 합치는 collector/barrier와 DRAM write-back이 없다.
- FP16 기능 검증이며 공식 GR00T BF16 activation 정확도 검증이 아니다.
- 실제 GR00T tensor trace와 GPU baseline, technology-mapped timing/power/energy는 여전히 미측정이다.

## 다음 작업

Bank-PCU 최종 `M_OUT`을 tag/mask 기준으로 수집하는 result barrier를 구현해 row 완료를 정확히 정의한다. 이후 activation replay/odd-bank 순회 및 write-back 경계를 명시적으로 모델링한다.
