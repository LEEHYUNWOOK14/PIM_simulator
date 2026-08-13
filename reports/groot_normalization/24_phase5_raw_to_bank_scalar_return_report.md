# Phase 5 — raw activation에서 Bank-PCU scalar 반환까지 통합

## 결과

raw bank vector reduction → Logic PCU barrier/tree → scalar finalize/RSQRT → tag-context lookup → 활성 bank broadcast를 하나의 ready/valid 경로로 통합했다.

- Top: `rtl/hierarchical_normalization_scalar_return_top.sv`
- config 수락과 row-context allocation은 같은 handshake에서 원자적으로 수행된다.
- scalar 응답 tag로 target mask를 lookup한다.
- broadcast가 응답을 실제 수락한 때에만 context entry와 scalar response를 함께 소비한다.
- 서로 다른 row mask와 bank별 scalar backpressure를 지원한다.

## 기능 검증

```text
HIERARCHICAL_NORMALIZATION_SCALAR_RETURN_TOP_TB PASS rows=2 masks=2 bank_stalls=1 cycles=22
```

4-bank 축소 환경에서 다음을 검증했다.

- row `0x8000`은 mask `0101`, row `0x8001`은 mask `1010`
- bank raw vector 도착 skew
- scalar 수신 bank별 stall
- 각 row scalar가 해당 mask의 bank에만 정확히 한 번 전달
- mean=`0x0000`, LUT 기반 inv_std=`0x3bfa`
- protocol/tag/config/allocation/context/broadcast 오류 없음

## 16-bank generic synthesis

설정: 16 banks, 4 lanes/bank, 8 scalar engines, bank result FIFO 4, context entries 16.

| Metric | Raw-to-scalar top | Raw-to-bank-scalar-return top | 증가량 |
|---|---:|---:|---:|
| Generic cells | 953,623 | 958,507 | 4,884 |
| Wire bits | 1,024,828 | 1,032,771 | 7,943 |
| Port bits | 21,729 | 24,668 | 2,939 |

Yosys `check -assert`는 PASS했다. 증가량은 tag context 16 entries와 scalar broadcast를 포함한다.

## 해석 제한

- **RTL_MEASURED:** raw activation으로부터 계산된 scalar가 row별 활성 Bank-PCU 포트까지 손실·오결합 없이 전달된다.
- 아직 scalar 출력 포트가 실제 `bank_pim_core` SRF write 명령으로 변환되지는 않는다.
- activation replay/storage, gamma/beta GRF 공급, affine microprogram issue, 최종 normalized output 수집이 남아 있다.
- 958,507 cells는 generic synthesis proxy이며 Bank-PCU 본체, DRAM/PHY, 물리 fanout buffer, timing/power를 포함하지 않는다.
- 기능 TB는 FP16이다. 공식 GR00T BF16 정확도 검증은 별도 미완료다.

## 다음 작업

bank scalar handshake를 각 Bank-PCU의 mean/inv_std SRF write sequence로 변환하는 adapter를 구현하고, 검증된 RMSNorm 2-command / LayerNorm 4-command affine microprogram issue 경로와 연결한다.
