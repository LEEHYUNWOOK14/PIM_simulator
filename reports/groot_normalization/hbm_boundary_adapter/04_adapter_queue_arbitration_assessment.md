# Adapter queue/arbitration 최적화 판정

작성일: 2026-08-12

## 판정

현재 `dram_bank_array_model` 계약에서는 read request queue depth 1이 최적이다. queue entry를 늘려도 DRAM이 허용하는 outstanding read credit이 1이므로 두 번째 RD를 발행할 수 없다. 또한 channel command port가 하나이고 adapter가 한 row만 소유하므로 서로 경쟁하는 command source가 없어 별도 arbiter를 추가하면 상태와 mux만 늘고 issue rate는 증가하지 않는다.

따라서 이번 최적화는 queue 복제가 아니라 command 수와 row conflict를 줄이는 방향으로 수행했다.

| 후보 | effective credit/issue 조건 | 결과 | 판정 |
|---|---|---|---|
| read queue depth 1 | DRAM credit 1 | 모든 credit 사용, peak=1 | 채택 |
| read queue depth 2/4 | `min(queue depth, DRAM credit)=1` | 추가 RD 발행 불가 | 기각 |
| multi-source command arbiter | source 1개, command bus 1개 | 경쟁 source 없음 | 기각 |
| x word slice reuse | RD word 1개로 PCU vector 2개 | x RD 50% 감소 | 채택 |
| gamma/beta packing | 256-bit word 한 개에 두 operand | affine command 절반 | 채택 |
| output coalescing | PCU vector 2개를 WR 하나로 결합 | WR 50% 감소 | 채택 |
| same-row column layout | x/affine/output을 한 open row에 배치 | phase별 PRE/ACT 제거 | 채택 |

## 2048-hidden command 하한

| 구성 | RD | WR | data commands | tCCD=4 기반 data-command 하한 |
|---|---:|---:|---:|---:|
| unpacked 128-bit transaction | 1,024 | 256 | 1,280 | 5,117 cycles |
| optimized packed adapter | 512 | 128 | 640 | 2,557 cycles |

실제 LayerNorm 연결 cycle은 3,509이고 data-command 하한은 2,557이므로 현재 adapter가 제거하지 못한 최대 여지는 약 27.1%다. 반면 추상 PCU 167 cycles와의 전체 차이는 21.0배다. 즉 추가 queue/arbitration만으로 전체 차이를 해소할 수 없으며, production 규격에서 bank-parallel channel/credit을 제공해야 한다.

통합 testbench는 RD acceptance와 response retirement를 직접 계수해 다음을 assertion한다.

- peak outstanding read = 1
- 종료 outstanding read = 0
- 두 번째 RD가 credit 반환 전에 발행되지 않음
- timing error = 0
