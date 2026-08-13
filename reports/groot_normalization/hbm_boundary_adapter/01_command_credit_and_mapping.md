# Normalization PCU–DRAM command/credit mapping

작성일: 2026-08-12  
대상: `logic_die_normalization_pcu_top` 8-lane freeze RTL과 현재 `dram_bank_array_model`

## 결론

기존 bank-side PIM adapter는 정규화 PCU의 boundary adapter로 재사용할 수 없다. 재사용 가능한 것은 `dram_bank_array_model`의 bank state와 timing rule뿐이다. 기존 PIM read port는 조합 read이고 response credit, backpressure, write-back 경로가 없기 때문이다.

새 `normalization_hbm_boundary_adapter`는 PCU의 reduction/replay/write-back transaction을 ACT/RD/WR/PRE command로 변환한다. 이는 현재 simulator 규격에 맞춘 command-level prototype이며, 향후 실제 logic-die 내부 HBM interface가 정해지면 외부 포트와 credit engine을 그 규격으로 교체해야 한다.

## 현재 DRAM simulator 계약

| 항목 | 확인된 계약 |
|---|---|
| command | NOP=0, ACT=1, RD=2, WR=3, PRE=4, REF=5 |
| command bus | channel당 한 command candidate |
| ready 의미 | 현재 command/address가 timing상 legal이면 1 |
| valid 규칙 | illegal cycle에 valid를 올리면 `timing_error_o=1`; adapter는 field를 먼저 제시하고 ready cycle에만 valid를 pulse |
| read credit | 1; pending read 또는 stalled response가 있으면 다음 RD 불가 |
| read response | `READ_LATENCY=2`, valid/ready로 보존 |
| write completion | 별도 response 없음; WR command acceptance가 retirement |
| 기본 timing | tRCD_RD=14, tRCD_WR=10, tRAS=33, tRP=14, tWR=12, tCCD=4, tRRD=4, tFAW=16, tWTR=4, tRTW=4 |
| row state | bank당 open row 하나 |

`dram_bank_array_model`의 RD legality는 `!read_pending_q && (!read_valid_o || read_ready_i)`를 검사하므로 response credit 1이 유지된다.

## PCU transaction mapping

8-lane PCU vector는 bank당 `8 × BF16 = 128 bit`이고 DRAM word는 256 bit다. 따라서 activation/output word 하나에 연속 PCU vector 두 개를 저장한다.

| PCU transaction | DRAM operation | packing |
|---|---|---|
| row start | bank 0..15 ACT | 모든 tensor 구간은 같은 physical row의 column 구간 사용 |
| reduction vector `v` | RD `x_base + floor(v/2)` | even vector=word[127:0], odd vector=word[255:128] |
| replay activation `v` | RD `x_base + floor(v/2)` | 한 word를 두 vector에 재사용 |
| replay affine `v` | RD `affine_base + v` | gamma=word[127:0], beta=word[255:128] |
| write-back vector `v` | WR `output_base + floor(v/2)` | 두 128-bit 결과를 coalesce; 마지막 single slice는 byte mask 사용 |
| row finish | bank 0..15 PRE | tRAS/tWR legal cycle까지 대기 |

### 대표 column map

| hidden | vectors/bank | X columns | affine columns | output columns | total columns |
|---:|---:|---|---|---|---:|
| 128 | 1 | 0 | 1 | 2 | 3 |
| 2048 | 16 | 0–7 | 8–23 | 24–31 | 32 |

동일 physical row에 세 구간을 배치하는 이유는 x→affine→output마다 PRE/ACT를 반복하지 않기 위해서다. RMSNorm은 beta를 산술에서 무시하지만 현재 packed affine word는 gamma와 beta를 함께 전달한다.

## 순서와 atomicity

1. 16개 bank를 ACT한다.
2. activation word를 bank 0..15에서 읽어 reduction vector를 all-bank lockstep으로 전달한다.
3. PCU의 held replay request를 수락한다.
4. replay x word와 affine word를 읽어 all-bank lockstep으로 전달한다.
5. PCU write-back 두 slice를 256-bit word로 결합한 뒤 bank 0..15에 기록한다.
6. 마지막 write의 tWR 조건 이후 모든 bank를 PRE한다.

Adapter의 PCU-side ready는 all-bank 공통값이다. 특히 write-back ready는 valid에 의존하지 않고 buffer availability만으로 결정해 PCU scheduler와 조합 순환을 만들지 않는다.

## 규격 경계

현재 DRAM command port는 shared host-channel 성격이다. 로직 다이 PCU와 16개 bank 사이의 실제 내부 TSV/bank fabric이 bank-parallel credit을 제공한다면 이 모델은 지나치게 보수적이다. 따라서 이 adapter의 command FSM과 검증 자산은 재사용하되, 이 결과만으로 frozen PCU lane 수를 변경하지 않는다.
