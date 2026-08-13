# Mixed-precision 최적화 기준선 및 설계 요구사항

## 목표

이 단계의 목표는 현재 BF16 hierarchical normalization 경로를 무조건 확장하는 것이 아니라, 실제 확보한 GR00T action-head trace에서 정확도 기준을 통과하는 **최소 mixed-precision datapath**를 찾고 성능 병목을 줄인 RTL로 구현하는 것이다.

Production replay/write-back은 여전히 별도 architecture gate 대상이다. 이번 작업은 normalization arithmetic core의 정확도와 처리량을 먼저 해결한다.

## 보존해야 하는 기준선

- activation 저장 및 외부 mapping: BF16
- banks/lanes: 16 banks × 4 lanes
- 실제 trace 분류: `PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`
- 대표 profile: 6개
- 전체 captured elements: 1,909,248
- 사전 정확도 기준: profile별 `max_abs <= 0.025`, nonfinite 0
- 비교 golden: captured PyTorch BF16 LayerNorm output
- 기존 address mapping과 tag 의미 유지
- ready/valid backpressure에서 payload 안정성 유지
- FP16/BF16 기존 경로 회귀를 깨지 않음

## 현재 RTL 병목 감사

### 정확도 경로

현재 BF16 경로는 다음 위치마다 BF16 rounding을 수행한다.

1. bank-local element square
2. bank-local SUM/SUMSQ의 매 누산
3. 16개 bank partial의 global 누산
4. mean, mean-square, variance, epsilon
5. LUT256 RSQRT output
6. center, normalize, gamma multiply, beta add

첫 representative row의 RTL 결과는 software stage model로 10,240/10,240 bit-exact 재현됐다. 전체 captured tensor를 동일 정책으로 모델링하면 profile 통과 수는 0/6, overall max abs 0.1875다. 따라서 mapping/testbench 문제가 아니라 중간 precision과 rounding 위치가 원인이다.

### 성능 경로

- 기존 4-lane reducer는 vector tree가 pipeline되어 있으나 row accumulator feedback에 floating-point add 조합 경로가 남는다.
- 현재 scalar engine은 BF16 LUT256까지 5-cycle control path지만 정확도 개선을 위해 추가 scalar 연산이 필요하다.
- 기존 apply는 element당 네 연산을 조합으로 연결하고 매 연산 BF16 rounding을 수행한다.
- 기존 Sky130 결과에서 4-lane BF16 reducer critical path는 약 21.48 ns이며 100 MHz constraint를 통과하지 못했다.
- Phase 5 latency model의 GPU break-even은 약 275 MHz였으므로, 정확도만 개선하고 같은 저주파 구조를 유지해서는 architecture 결론이 바뀌지 않는다.

## 구현 요구사항

선택되는 RTL은 다음을 만족해야 한다.

1. BF16 input/gamma/beta와 BF16 output interface 유지
2. wider partial statistic의 format과 bit width 명시
3. local reduction과 global reduction의 실제 연산 순서를 software model과 일치
4. RSQRT approximation의 LUT 크기와 Newton iteration 수 고정
5. mean/inv_std broadcast precision 명시
6. apply 내부 pipeline과 최종 BF16 rounding 위치 명시
7. 실제 GR00T trace에서 RTL output 생성 및 PyTorch metric 계산
8. constant, zero variance, small variance, large offset, NaN/Inf 정책 검증
9. backpressure/reset/tag protocol 검증
10. generic synthesis와 가능한 범위의 mapped timing 비교
11. cycle simulator를 새 latency/II로 재보정

## 증거 분류

- PyTorch captured output: measured runtime artifact
- mixed-precision Python DSE: numerical model
- RTL cycle: RTL simulation measurement
- generic cells: Yosys generic synthesis measurement
- mapped timing: 지정 library/constraint에서의 pre-layout STA
- workload latency: measured stage count를 actual calls에 투영한 model
- energy: activity-calibrated 결과가 없으면 unavailable 유지

## 기존 변경 보존

작업 시작 시 worktree에는 normalization foundation을 포함한 다수의 기존 사용자 변경이 있었다. 이번 작업은 새 mixed-precision 모듈·검증·보고서를 우선 추가하고, 기존 FP16/BF16 path를 대체하기 전 독립 검증을 수행한다.

