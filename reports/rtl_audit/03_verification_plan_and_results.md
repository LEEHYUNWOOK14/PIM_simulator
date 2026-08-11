# 03. 검증 계획과 결과

## 계획

1. 기존 정상-path unit/integration 회귀
2. FP16 independent reference 비교
3. valid/ready 및 bank timing 반례
4. CRF illegal/control-flow 반례
5. epoch 및 metadata association 반례
6. 16-PCU concurrency와 randomized backpressure
7. reduced/default elaboration 및 synthesis
8. 작은 조합 block formal proof

## 결과

|ID|검사|구성|결과|증거|
|---|---|---|---|---|
|T01|기존 Full-PIM regression|8 self-checking TB|PASS 8/8|`rtl/run_full_pim_tests.sh`|
|T02|16 PCU simultaneous issue|16/16|PASS|`LOGIC_PCU_SCHEDULER_16_TB`|
|T03|random output stall|40 batches, 320 results|PASS|`LOGIC_DIE_RANDOM_STRESS_TB`|
|T04|FP16 add reference|C++ half.h, 4096 vectors|PASS 4096/4096|`fp16_add_random_tb`|
|T05|FP16 multiply reference|edge+random 4217 vectors|FAIL 452 mismatch|`fp16_mul_random_audit_tb`|
|T06|닫힌 bank operand 사용|2 banks, 1 PCU|DEFECT REPRODUCED|`bank_operand_validity_repro_tb`|
|T07|DRAM response stall|두 연속 RD|DEFECT REPRODUCED|`dram_read_backpressure_repro_tb`|
|T08|illegal CRF|reserved opcode 9|DEFECT REPRODUCED|`invalid_crf_deadlock_repro_tb`|
|T09|finite JUMP|count 1, offset 1|DEFECT REPRODUCED|`crf_jump_repro_tb`|
|T10|epoch bypass|begin/fill/release 없음|DEFECT REPRODUCED|`logic_tag_channel_repro_tb`|
|T11|tag/channel 독립성|channel=1, tag low bit=0|DEFECT REPRODUCED|동일 TB|
|T12|shared FP16 cluster|pipeline 1/2/4|PASS|`run_shared_cluster_tests.sh`|
|T13|구형 전체 regression|64ch timed payload|TIMEOUT|5분 이상 CPU 100%, 진행 없음|
|T14|default Full-PIM Icarus elaboration|64ch/16bank/8PB/16PCU|PASS, 14.3 s|compile-only|
|T15|default Full-PIM Yosys hierarchy|동일|RESOURCE/ENV FAILURE|272 s 후 WSL service failure|

## FP16 multiply 대표 오차

```text
0001 × 3c00: RTL 0401, C++ reference 0001
03ff × 3c00: RTL 07ff, C++ reference 03ff
2021 × 0601: RTL 0004, C++ reference 000c
```

NaN payload 차이는 NaN class가 같으면 허용했음에도 452건이 남았다. 주된 실패는 subnormal 정규화·rounding 영역이다.

## Coverage 제한

- reset-during-active 전 인터페이스 조합은 미검증
- INT8 동작은 C++가 실질적인 독립 INT8 수치 계약을 제공하지 않아 `AMBIGUOUS`
- coalescer 128-entry full/ordinal ordering과 TSV 장기 fairness formal은 미완료
- actual 64-channel Full-PIM end-to-end 계산 simulation은 없음
- 물리 netlist equivalence simulation은 없음

기존 PASS는 정상 경로의 증거지만 위 반례를 상쇄하지 않는다.
