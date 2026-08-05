# 73차: Logic-die Depthwise 계층형 누산 1차 구현

## 1. 목적

기존 bank-side depthwise의 `9 MUL + 8 ADD` 과정에서 발생하는 중간 DRAM write를 줄이기 위해, bank PCU는 tap별 곱셈을 수행하고 base logic die의 공유 accumulator가 9개 부분합을 누산한 뒤 최종 합만 DRAM에 기록하는 경로를 구현했다.

## 2. 모델링 원리와 배치

- `MultiChannelMemorySystem`에 `LogicDieAccumulator`를 하나 생성한다.
- 64개 `MemorySystem/Rank/PIMRank`가 같은 accumulator를 공유한다. 이는 HBM stack 최하단 base logic die에 공유 누산기를 하나 배치한다는 뜻이다.
- 누산 entry key는 `{channel, rank, PIM block, bank parity, row, column}`이다.
- bank-side PCU의 GRF에 생성된 FP16 곱셈 결과를 `BANK_TO_LOGIC_ACCUM` 패킷으로 전달한다.
- 9번째 tap 뒤 `LOGIC_ACCUM_TO_BANK` 패킷이 9개 부분합을 검사하고 최종 burst만 실제 DRAM bank에 기록한다.
- `LOGIC_ACCUMULATOR_BW`, `LOGIC_ACCUMULATOR_LATENCY`, `LOGIC_ACCUMULATOR_ENTRIES`로 link와 buffer 제약을 모델링한다.

## 3. 수행 결과

| 실험 | 결과 |
|---|---:|
| 1채널 기능 검증 | 1,152 partial → 128 final, pending 0, PASS |
| 64채널 실제 shape depthwise | 37,632 outputs, 73,728 partial → 8,192 final, pending 0, PASS |
| DRAM write A/B | 174,656 → 153,664, 20,992회(12.02%) 감소 |
| Depthwise micro cycle A/B | 36,426 → 66,716, 30,290 cycle(83.16%) 증가 |
| 전체 UIB 정확도 | 최종 FP16 출력 18,816개 PASS |
| 전체 UIB cycle | 235,182 → 265,022, 29,840 cycle(12.69%) 증가 |
| 전체 UIB modeled write | 220,342 → 199,350, 20,992회(9.53%) 감소 |

초기 전체 UIB에서는 일부 테두리 출력이 7 대신 10으로 관찰됐다. 원인은 accumulator 산술이 아니라 기존 MUL의 중간 writeback 패킷 8개를 제거하면서 bank-side CRF의 PC/NOP 진행까지 함께 제거한 것이었다. 그 결과 odd-bank 입력 FILL이 건너뛰어졌다. `logicAccumulatorDirect` 패킷이 DRAM에는 쓰지 않되 CRF context를 진행하도록 수정한 뒤 corner/edge/center를 포함한 depthwise 출력 37,632개와 전체 UIB 최종 출력 18,816개가 모두 통과했다.

## 4. 해석

첫 구현은 전체 정확도와 DRAM I/O 감소를 모두 검증했지만 아직 성능 이득은 없다. 각 tap 뒤 2,359,296 B의 부분합 전송을 직렬로 기다려 36,873 transfer cycle이 추가된 것이 성능 저하의 주원인이다.

## 5. 다음 작업

1. Bank MUL과 부분합 전송을 overlap한다.
2. Tap별 전송 대신 tile 또는 row 단위 local aggregation을 비교한다.
3. Accumulator 용량, link bandwidth, latency를 sweep해 I/O 감소와 cycle의 Pareto 후보를 찾는다.
4. CRF-drain 패킷을 RTL의 explicit `partial_valid/ready` handshake로 치환한다.
5. 다른 depthwise shape와 kernel size에서 key/lane mapping을 회귀 검증한다.

## 6. 재현 로그

- `results/depthwise_hierarchical_1ch_payload_fix.log`
- `results/depthwise_hierarchical_64ch.log`
- `results/depthwise_bank_source_queues_64ch.log`
- `results/depthwise_hierarchical_crf_drain_fix.log`
- `results/full_uib_depthwise_hierarchical_crf_drain_fix.log`
- `results/depthwise_hierarchical_ab.csv`
