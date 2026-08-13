# Phase 5 — raw activation에서 bank별 정규화 명령 발행까지 통합

## 구현 결과

`hierarchical_normalization_scalar_return_top`의 bank별 scalar 출력을 동일 bank의 `bank_normalization_microprogram_adapter`에 연결했다.

- Top: `rtl/hierarchical_normalization_bank_issue_top.sv`
- adapter가 idle일 때만 해당 bank의 scalar를 수락한다.
- SRF write stall 또는 command stall은 해당 bank에만 국소적으로 전파된다.
- row tag는 모든 Bank-PCU command의 context key로 유지된다.
- gamma/beta GRF_B index는 top에서 공통 설정한다.

## 기능 검증

```text
HIERARCHICAL_NORMALIZATION_BANK_ISSUE_TOP_TB PASS rows=2 banks=4 commands=12 stalls=1 cycles=44
```

검증 workload:

| Row | Mode | Active mask | Expected commands |
|---|---|---:|---:|
| `0xa000` | RMSNorm | `0101` | 2 banks × 2 = 4 |
| `0xa001` | LayerNorm | `1010` | 2 banks × 4 = 8 |

총 12개 command, 각 활성 bank의 SRF write 1회와 transaction done 1회를 확인했다. 비활성 bank에는 SRF/command/done이 발생하지 않았다. RMSNorm SRF의 `inv=0x3bfa`, LayerNorm SRF의 `-mean=0xbc00`, `inv=0x3bfa`도 검사했다. 한 bank의 SRF ready를 지연시켜 독립 backpressure를 검증했다.

## 16-bank generic synthesis

설정: 16 banks, 4 reduction lanes/bank, 8 scalar engines, 16 contexts, 256-bit Bank-PCU width.

| Metric | Scalar-return top | Bank-command-issue top | 증가량 |
|---|---:|---:|---:|
| Generic cells | 958,507 | 961,299 | 2,792 |
| Wire bits | 1,032,771 | 1,048,405 | 15,634 |
| Port bits | 24,668 | 37,246 | 12,578 |

증가량은 16개 adapter와 top 연결 로직이다. Yosys `check -assert`는 PASS했다.

## 현재 E2E 경계

**RTL_MEASURED:** raw vector 입력부터 bank별 SRF payload 및 정확한 RMSNorm/LayerNorm command sequence 발행까지 연결됐다.

아직 다음은 포함하지 않는다.

- 이 top 내부의 실제 `bank_pim_core` array
- activation replay buffer와 even/odd bank operand 선택
- gamma/beta 사전 적재 scheduler
- 최종 `M_OUT` result handshake 및 row 완료 barrier
- normalized activation의 DRAM write-back

따라서 이 결과만으로 완전한 raw-to-normalized-output E2E라고 부를 수 없다.

## 다음 작업

축소 bank 구성에서 실제 `bank_pim_core` array, activation/gamma/beta 입력과 result collector를 연결하여 raw statistics 입력부터 최종 affine vector 결과까지 검증한다. 그 뒤 replay/write-back 구조와 16-bank 비용을 분리 평가한다.
