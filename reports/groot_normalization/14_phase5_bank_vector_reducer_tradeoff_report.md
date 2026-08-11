# Phase 5 Bank vector SUM/SUMSQ reducer 면적–처리량 비교

## 판정

**PASS WITH LIMITS** — 1/2/4/8/16-lane raw-input SUM/SUMSQ reducer를 synthesizable RTL로 구현하고 16-lane 기능 테스트, 전 구성 strict synthesis 및 generic logic path 측정을 완료했다.

현재 선택의 knee point는 **2 lanes/bank**, GPU-full 분석 가정을 이기기 위한 성능 후보는 **4 lanes/bank**다. 8/16 lanes는 latency 개선 대비 bank별 복제 면적이 너무 크므로 현 단계에서는 권고하지 않는다.

## 구현

`bank_normalization_vector_reducer.sv`는 매 cycle 다음을 동시에 처리한다.

1. 각 FP16 lane의 `x²` 계산
2. balanced binary tree로 vector SUM과 SUMSQ 생성
3. row accumulator에 두 partial을 누적
4. 마지막 vector에서 tagged SUM/SUMSQ 결과 생성

초기 직렬 adder chain은 16-lane generic path length가 4,046이었다. balanced tree로 변경한 뒤 1,262로 68.8% 줄었다. generic path length는 gate delay나 ns가 아니므로 100 MHz timing closure를 증명하지는 않는다.

## 기능 검증

16-lane 두 vector를 연속 입력했다.

- vector 0: 1.0 × 16
- vector 1: 2.0 × 16
- 기대 SUM: 48.0 (`0x5200`)
- 기대 SUMSQ: 80.0 (`0x5500`)

```text
BANK_NORMALIZATION_VECTOR_REDUCER_TB PASS lanes=16 vectors=2 cycles=6
```

tag, valid/ready, protocol error 및 FP16 bit-exact 결과가 통과했다.

## 합성 결과

Yosys generic synthesis이며 technology-mapped area/timing이 아니다. 모든 구성에서 `check -assert` 문제 0건이다.

| lanes/bank | elements/cycle/bank | cells/bank | generic path length | 16-bank cells | throughput/1k cells |
|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 10,787 | 334 | 172,592 | 0.09270 |
| 2 | 2 | 21,330 | 566 | 341,280 | 0.09376 |
| 4 | 4 | 42,389 | 798 | 678,224 | 0.09436 |
| 8 | 8 | 84,501 | 1,030 | 1,352,016 | 0.09467 |
| 16 | 16 | 168,725 | 1,262 | 2,699,600 | 0.09483 |

처리량/면적 효율은 거의 일정하다. 즉 lane 확장은 구조적 재사용 이득 없이 거의 선형 면적 복제를 요구한다. balanced tree는 critical-path proxy를 개선했지만 FP16 multiplier와 adder 수 자체는 줄이지 않는다.

1-lane 신규 구조가 기존 scalar reducer 15,307 cells보다 29.5% 작은 것은 불필요한 zero-add 경로를 제거하고 hierarchy를 단순화한 결과다. 서로 다른 합성 시점의 generic count이므로 최종 물리 면적 우위로 단정할 수는 없다.

## 333-call projected 영향

조건: 16 banks, 100 MHz, FP16, 동일 manifest 및 Phase 6 공통 가정. vector reducer throughput만 RTL 값으로 바꾸고 나머지는 동일하게 유지했다.

| lanes/bank | Hierarchical latency | scalar 대비 speedup | Hierarchical cells proxy | 전체 latency winner |
|---:|---:|---:|---:|---|
| 1 | 61.087 ms | 1.00× | 612,992 | Logic-only |
| 2 | 42.889 ms | 1.42× | 781,680 | Logic-only |
| 4 | 33.789 ms | 1.81× | 1,118,624 | Logic-only |
| 8 | 30.673 ms | 1.99× | 1,792,416 | Logic-only |
| 16 | 29.115 ms | 2.10× | 3,140,000 | Logic-only |

참고 비교값은 Logic-only 19.507 ms, GPU full 36.773 ms다. 이 두 값에는 아직 실제 GPU 측정이 없고, Logic-only 면적에는 raw tensor reducer/apply가 빠져 있어 Logic-only 우승을 확정 결론으로 사용할 수 없다.

관찰:

- 2→16 lanes로 8배 확장해도 Hierarchical latency는 42.889→29.115 ms로 1.47배만 줄어든다. apply와 global 단계가 남고, row 경계를 넘어 lane을 채울 수 없어 hidden=64 profile에서 8/16 lane이 활용되지 않기 때문이다.
- Hierarchical이 assumed GPU full보다 빨라지는 첫 점은 4 lanes/bank다.
- Bank-only도 4 lanes에서 35.612 ms로 assumed GPU full 36.773 ms를 근소하게 앞선다.
- 4-lane Hierarchical 면적 proxy는 1,118,624 cells다. 여기에는 reference의 16-engine Logic array 440,400 cells가 포함된다.

## 권고

- 면적을 중시하는 기본 후보: 2 lanes/bank
- assumed GPU full을 넘기 위한 성능 후보: 4 lanes/bank
- 8/16 lanes: technology mapping과 실제 power 증거 전에는 제외
- 최종 선택 전 2/4-lane pipeline register 삽입과 OpenSTA timing 비교 필요
- Logic-only에도 동등한 raw reducer와 apply 비용을 포함하기 전에는 아키텍처 최종 우승자를 선언하지 않음

## 재현

```bash
bash verification/groot_normalization/run_bank_normalization_vector_reducer_test.sh
bash verification/groot_normalization/run_bank_normalization_vector_reducer_synthesis.sh
python tools/analyze_bank_reducer_tradeoff.py
```

산출물:

- `results/bank_vector_reducer_tradeoff.csv`
- `results/bank_vector_reducer_l{1,2,4,8,16}_yosys.log`
- `rtl/bank_normalization_vector_reducer.sv`
