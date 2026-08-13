# HBM boundary adapter RTL 검증 및 구조 재검토 보고서

작성일: 2026-08-12

## 1. 구현 결과

새 `rtl/normalization_hbm_boundary_adapter.sv`를 구현해 frozen 8-lane PCU와 `dram_bank_array_model`을 직접 연결했다.

적용한 adapter 최적화는 다음과 같다.

- open-row column layout으로 x/affine/output 간 PRE/ACT 제거
- 256-bit x word를 두 128-bit PCU vector가 공유
- gamma와 beta를 한 256-bit affine word에 packing
- 두 output slice를 한 WR로 coalescing
- odd vector count에서는 byte mask로 나머지 half-word 보존
- all-bank atomic ready/valid와 held replay request
- timing legality look-ahead 후 valid pulse
- read response credit 1 준수

2048 hidden에서 단순 128-bit 단위 구현은 최소 1,024 RD와 256 WR가 필요하지만, packing/reuse 후 512 RD와 128 WR로 줄었다. data command 수는 1,280개에서 640개로 50% 감소했다.

## 2. RTL simulation 결과

| mode | hidden | abstract PCU | HBM-connected | 배율 | RD/WR | timing error | output |
|---|---:|---:|---:|---:|---:|---:|---|
| LayerNorm | 128 | 130 | 523 | 4.02× | 48/16 | 0 | PASS |
| LayerNorm | 2048 | 167 | 3,509 | 21.01× | 512/128 | 0 | PASS |
| RMSNorm | 128 | 118 | 511 | 4.33× | 48/16 | 0 | PASS |
| RMSNorm | 2048 | 155 | 3,497 | 22.56× | 512/128 | 0 | PASS |

검증 항목:

- LayerNorm/RMSNorm 128·2048 output memory 값 일치
- 128 hidden의 upper half-word 보존
- ACT=16, PRE=16 exact
- 계산식과 RD/WR command count exact
- DRAM timing violation 0
- PCU/adapter protocol error 0
- Yosys hierarchy/check 통과; process/opt 후 1,644 generic cells, 내부 data buffer 12,288 bits

재현 명령:

```bash
bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh
bash verification/groot_normalization/run_normalization_pcu_abstract_cycle_test.sh
```

## 3. 병목 판정

2048 hidden 한 row의 optimized traffic은 512 RD + 128 WR다. shared command/data path에서 tCCD=4이므로 data command만으로도 약 2,557-cycle 하한이 생긴다. 실제 3,509 cycles는 이 하한의 1.37배다. 완벽한 queue/arbitration으로 줄일 수 있는 최대 여지는 약 27%이며 21× 전체 격차를 없앨 수 없다.

LayerNorm 2048에서 PCU로 전달한 입력은 bank당 reduction+replay `32 × 128 = 4,096 bit`다. 이를 3,507 adapter cycles로 나누면 bank당 평균 1.17 bit/cycle이다.

- 128-bit active-transfer 폭 기준 utilization: 약 0.91%
- 기존 sustained floor 64 bit/bank/cycle 대비: 약 1.83%
- shared channel payload: `(512+128)×256/3507 = 46.7 bit/cycle`
- tCCD 기반 64 bit/cycle channel 상한 대비: 약 73%

즉 channel 자체는 비교적 사용 중이지만, 하나의 shared channel을 16개 bank에 직렬 배분하므로 bank-parallel 8-lane PCU를 지속 공급할 수 없다. queue depth 문제가 아니라 topology/credit 계약 문제다.

## 4. PCU scheduler 재검토 결과

공급률 하한을 wall-clock sustained bandwidth로 해석하면 현재 shared host-command 모델에서는 8-lane뿐 아니라 4-lane도 만족할 수 없다. shared channel의 이론 상한을 16 banks에 균등 배분하면 bank당 4 bit/cycle이므로 4-lane의 64-bit 소비 폭에도 크게 못 미친다.

그렇다고 frozen PCU를 4-lane으로 변경하지 않는다.

1. 기존 8-lane 선정 하한은 **active bank transfer cycle의 128-bit slice** 기준이었고 이 adapter도 해당 폭을 정확히 전달한다.
2. 현재 DRAM port는 host-style shared channel이며, 프로젝트가 목표로 하는 logic-die 내부 bank-to-PCU fabric의 확정 규격이 아니다.
3. 기존 실제 trace에서 8-lane은 4-lane보다 약 1.9× 빠르고, 16-lane은 면적·timing 비용이 과다했다.
4. shared host bus 결과로 lane 수를 줄이면 내부 bank-parallel fabric이 제공될 때 성능을 잃는다.

따라서 `8 lanes / 4 scalar engines / split-RW / contexts 8` freeze는 유지한다. 변경 대상은 scheduler가 아니라 production boundary의 channel 수, bank-parallel read credit, TSV data width다.

## 5. 최종 판정과 남은 production 과제

현재 simulator용 boundary adapter는 완료됐고 기능·timing 검증을 통과했다. 그러나 이것을 production HBM adapter라고 부르지는 않는다. 실제 내부 HBM 규격이 정해질 때 다음을 확정해야 한다.

- logic die에서 bank별로 독립 발행 가능한 command 수
- bank-to-logic return channel 수와 각 channel data width
- outstanding read credit 및 response ID/order 규칙
- write acknowledgement와 error/poison 규칙
- refresh, row conflict, bank-group timing 노출 방식
- 여러 logical row의 address interleave와 arbitration

그 규격이 bank-parallel이면 현재 FSM의 transaction mapping·packing·scoreboard를 유지하고 command/credit front-end를 교체한다. 규격도 shared channel 하나라면 PCU는 계산기가 아니라 메모리 대기형 accelerator가 되므로, 그때는 4-lane 또는 bank-group별 소수 PCU로 구조를 다시 최적화해야 한다.
