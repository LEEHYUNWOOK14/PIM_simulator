# 75차: Bank-local aggregation과 계층형 연산 배치 판단

## 1. 목적

256 B/cycle logic link를 넓히는 대신 기존 bank 인접 PCU에서 여러 depthwise tap을 먼저 합쳐 부분합 전송량을 줄인다. Link 폭과 local aggregation factor를 함께 낮추며 전체 UIB 정확도, cycle, write를 비교한다.

## 2. 구현 원리

- 매 tap의 accumulator-direct 패킷은 bank CRF의 PC/NOP 진행을 계속 담당한다.
- `BANK_LOCAL_AGGREGATION_TAPS`만큼의 FP16 MUL 결과를 PIMRank 내부 bank-local accumulator에서 더한다.
- 그룹 마지막 tap의 `flush` 패킷에서만 합쳐진 burst를 shared logic-die accumulator로 보낸다.
- 3×3 depthwise에서 factor 1/3/9의 logic contribution 수는 출력 burst당 9/3/1이다.
- Logic accumulator의 expected contribution 수도 같은 비율로 바뀌며 최종 DRAM write는 한 번만 수행한다.

## 3. 전체 UIB 결과

| 후보 | Depthwise | Total | Transfer bytes | Writes | 정확도 |
|---|---:|---:|---:|---:|---:|
| Bank-depthwise 기준 | 38,884 | 235,182 | - | 220,342 | 18,816 PASS |
| 256 B/cycle, factor 1 | 35,352 | 231,650 | 2,359,296 | 199,350 | PASS |
| 128 B/cycle, factor 3 | 35,674 | 231,727 | 786,432 | 199,350 | PASS |
| 64 B/cycle, factor 9 | **34,880** | **231,178** | **262,144** | **199,350** | **PASS** |

64 B/cycle, factor 9 후보는 기준보다 4,004 cycle(1.70%) 빠르고 modeled write를 20,992회(9.53%) 줄였다. Factor 1 대비 bank→logic partial bytes는 88.89% 감소했다.

## 4. 아키텍처 해석

Depthwise의 9개 tap은 같은 output channel과 같은 bank-local mapping에 속하므로 cross-bank reduction이 아니다. 따라서 모든 tap을 logic die로 보내는 것보다 bank PCU가 지역 누산을 끝내고 최종 burst만 logic die로 넘기는 편이 낫다.

Logic die의 역할이 사라진 것은 아니다.

1. 여러 bank에서 나온 최종 depthwise burst의 완료와 tensor 경계를 관리한다.
2. Shared output/weight buffer와 command frontend를 통해 다음 project pointwise를 준비한다.
3. Pointwise GEMV/MAC처럼 여러 bank/channel을 연결하는 연산을 수행한다.
4. Bank-local 처리가 불가능한 reduction 또는 data rearrangement를 담당한다.

이 결과는 프로젝트의 핵심인 “bank-side local PCU + base logic-die global PCU”의 역할 분담을 수치로 보여준다.

## 5. 제한

- Bank-local accumulator는 현재 C++ functional buffer이며 면적과 포트 수가 아직 제한되지 않았다.
- FP16 누산 순서가 바뀌면 일반 데이터에서 rounding 차이가 발생할 수 있으므로 tolerance 기반 검증이 추가로 필요하다.
- 64 B/cycle은 simulator 후보값이며 물리 interconnect 검증이 필요하다.
- MobileNetV4 UIB 한 shape의 결과이므로 다른 kernel, stride, channel shape로 일반화해야 한다.

## 6. 다음 작업

1. Bank-local accumulator entry 수와 read/write port 수를 유한하게 모델링한다.
2. Factor 3/9에서 FP16 rounding error를 random input으로 비교한다.
3. MobileNetV4의 다른 depthwise kernel/stride를 검증한다.
4. Pointwise와 depthwise를 포함한 자동 placement 정책의 cost 식을 만든다.
5. Verilog에는 bank local accumulator와 logic partial handshake를 별도 모듈로 정의한다.

## 7. 근거 파일

- `results/bank_local_aggregation_sweep.csv`
- `results/depthwise_local_agg3_overlap_128b.log`
- `results/full_uib_local_agg3_overlap_128b.log`
- `results/depthwise_local_agg9_overlap_64b.log`
- `results/full_uib_local_agg9_overlap_64b.log`

