# Phase 5 공유 reducer 및 Bank-PCU 재사용 구조 비교

## 결론

현재 RTL에는 bank마다 전용 normalization apply 연산기를 복제하기보다, **공유 pair reducer + Logic-PCU scalar/RSQRT + 기존 Bank-PCU 마이크로프로그램** 구조가 더 적합하다.

4-bank 기준 공유 pair reducer와 Logic normalization engine의 단순 합은 67,172 generic cells로, 전용 종단간 normalization datapath의 183,082 cells보다 115,910 cells(63.3%) 작다. 다만 이 수치는 공유 구조에서 raw activation으로부터 SUM/SUMSQ pair를 만드는 회로와 명령 제어 비용을 제외하므로 최종 물리 면적 비교가 아니다.

## 이번 작업에서 수정한 합성 결함

`bank_local_reduction_buffer.sv`는 기존에 module-level packed 상태 배열의 bank slice를 여러 `always_ff` 블록이 나누어 갱신했다. RTL 시뮬레이션은 동작했지만 Yosys strict check에서는 이를 다중 드라이버 및 조합 루프로 보고했다.

상태를 generate bank 스코프별 unpacked 배열과 레지스터로 분리했다. payload 배열은 valid bit가 설정된 뒤에만 읽히므로 reset하지 않고, valid 상태만 reset한다.

검증 결과:

- `bank_local_reduction_buffer_tb`: PASS
- `bank_local_fp16_reduction_tb`: PASS, 16 lanes 합 6.0
- Yosys `check -assert`: BANKS=1/2/4/8/16 모두 문제 0건
- 전체 `rtl/run_tests.sh`: 180초 제한 내 완료되지 않아 이번 작업의 통과 근거로 사용하지 않음

## 합성 결과

조건은 `ENTRIES_PER_BANK=2`, `LANES=2`, Yosys generic synthesis이다.

| Banks | 공유 pair reducer generic cells | strict check |
|---:|---:|:---:|
| 1 | 7,029 | PASS |
| 2 | 14,055 | PASS |
| 4 | 28,108 | PASS |
| 8 | 56,215 | PASS |
| 16 | 112,525 | PASS |

거의 bank 수에 선형 비례한다. 따라서 이름은 공유 reducer지만 현재 구성에서는 bank별 buffer와 FP16 vector adder가 복제된다. 더 큰 bank 수에서는 pipeline fabric을 제한된 개수로 공유하는 구조도 별도 탐색해야 한다.

## 연산 배치

권장 데이터 흐름은 다음과 같다.

1. Bank 측에서 local SUM/SUMSQ를 만든다.
2. 공유 pair reducer가 bank partial을 모은다.
3. Logic-PCU가 평균, 분산, epsilon clamp, RSQRT를 계산한다.
4. scalar를 bank에 broadcast한다.
5. 기존 Bank-PCU의 ADD/MUL/GRF/SRF를 재사용해 elementwise apply를 수행한다.

실제 Bank-PCU TB에서 affine RMSNorm apply는 scalar/weight 설정 뒤 MUL 2개, affine LayerNorm apply는 scalar/gamma/beta 설정 뒤 ADD/MUL/MUL/ADD 4개로 검증됐다. 비-affine이면 gamma/beta 단계를 생략할 수 있다. 전용 apply RTL의 추가 산술 데이터패스는 필요하지 않지만, 시스템 수준 parameter 공급과 명령 발행 비용은 simulator에서 추가 계측해야 한다.

## 해석 한계와 다음 게이트

- generic cell 수는 서로 다른 합성 top의 상대 지표이며 공정 PPA가 아니다.
- 67,172-cell 합계는 raw element reduction producer를 포함하지 않는다.
- 기존 Bank-PCU 재사용의 incremental arithmetic area를 0으로 보는 것은 데이터패스에 한정한다. 제어·레지스터·배선 증가는 0이 아니다.
- Bank-PCU RMSNorm/LN apply command sequence RTL TB는 완료됐다. 다음 구현 게이트는 raw input에서 SUM/SUMSQ pair까지 생성하는 공유 reduction 경로의 비용 측정이다.

원시 결과는 [bank_architecture_cost_comparison.csv](results/bank_architecture_cost_comparison.csv)와 `results/shared_pair_reducer_b*_yosys.log`에 있다.
