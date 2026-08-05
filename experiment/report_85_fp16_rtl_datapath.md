 # 85차 실험 보고서: FP16 RTL 연산 경로 구현 및 C++ 교차 검증

## 1. 실험 목적

기존 `bank_local_reduction_buffer.sv`는 slot, key, valid/ready와 backpressure를
검증했지만 덧셈 결과는 testbench가 정수 덧셈으로 공급했다. 이번 실험은 이 빈
자리에 합성 가능한 FP16 가산기를 넣어, 계층형 PIM 누산 경로가 MobileNetV4의
데이터 형식인 FP16을 처리하도록 만드는 것이 목적이다.

## 2. 구현 구조

| 파일 | 역할 |
|---|---|
| `rtl/fp16_add.sv` | FP16 두 값을 더하는 조합형 1-lane 가산기 |
| `rtl/bank_local_fp16_reduction.sv` | 16개 FP16 lane과 기존 reduction buffer 결선 |
| `rtl/tools/generate_fp16_add_vectors.cpp` | 시뮬레이터와 같은 `lib/half.h`로 정답 생성 |
| `rtl/tb/fp16_add_random_tb.sv` | 4,096개 입력쌍을 C++ 정답과 bit 단위 비교 |
| `rtl/tb/bank_local_fp16_reduction_tb.sv` | 256-bit burst의 16개 lane을 실제 누산 |

가산기는 부호와 지수를 비교하고 작은 가수의 자릿수를 맞춘 뒤 덧셈 또는 뺄셈을
수행한다. 이어서 정규화하고 guard/round/sticky bit를 이용해
round-to-nearest-even 반올림을 적용한다. NaN, infinity, zero와 subnormal 입력도
데이터 경로에 포함된다.

## 3. 재현 명령

저장소 루트의 WSL 터미널에서 실행한다.

```bash
bash rtl/run_tests.sh
```

스크립트는 C++ 정답 생성기도 빌드하므로 WSL에 `g++`와 Icarus Verilog가 필요하다.

## 4. 실제 출력

```text
FP16_ADD_TB PASS
FP16_ADD_RANDOM_TB PASS vectors[4096] reference[C++ half.h]
BANK_LOCAL_FP16_REDUCTION_TB PASS lanes[16] sum[6.0]
LOGIC_DIE_64CH_REDUCTION_TOP ELABORATION PASS
LOGIC_DIE_64CH_TRACE_REPLAY_TB PASS bursts[8192] full_cycles[4096] bytes_per_active_cycle[64]
```

## 5. 결과 해석

`FP16_ADD_RANDOM_TB PASS`는 임의로 만든 유한 FP16 두 값 4,096쌍에서 RTL과
C++ 시뮬레이터의 결과 bit pattern이 모두 같다는 뜻이다. 단순 허용 오차 비교가
아니므로 부호, 지수, 가수와 반올림 결과까지 일치했다.

`BANK_LOCAL_FP16_REDUCTION_TB PASS`는 32 B burst 하나의 FP16 16개가 각각
`1.0 + 2.0 + 3.0 = 6.0`을 계산하고 마지막 update에서 final valid/key/data가
정상 출력됐다는 뜻이다. 기존 제어 buffer와 신규 FP16 datapath가 연결됐다.

이후 기존 64채널 elaboration, MobileNetV4 trace replay, arbiter stress test도 전부
통과했다. 신규 모듈이 기존 링크 제어 회귀를 깨지 않았다는 증거다.

## 6. 현재 말할 수 있는 범위

이번 결과로 FP16 가산의 **기능 정확도**와 16-lane buffer 연결은 확인했다. 그러나
조합형 가산기가 목표 주파수 한 cycle 안에 들어가는지는 확인하지 않았다. 따라서
C++의 `BANK_LOCAL_ACCUMULATOR_LATENCY=1`은 아직 합성으로 입증된 값이 아니라
실험 가정이다.

또한 이번 wrapper는 bank-local 누산 단계에 연결됐으며 production 64채널 top은
외부 adder port를 유지한다. 다음 단계에서 pipeline stage 수를 정한 뒤 64채널 top에
내장 datapath 선택 옵션으로 연결해야 한다.

## 7. 다음 단계

1. Yosys 또는 목표 FPGA/ASIC 도구로 FP16 lane과 16-lane wrapper를 합성한다.
2. 조합 지연이 한 cycle을 넘으면 ready/valid pipeline을 추가한다.
3. 합성 latency를 C++ `BANK_LOCAL_ACCUMULATOR_LATENCY`에 되돌려 넣는다.
4. C++ MobileNetV4 partial 값 자체를 CSV로 기록하고 RTL 결과까지 비교한다.
5. 검증된 wrapper를 64채널 top의 선택 가능한 내부 datapath로 연결한다.

이번 실험은 구조적 trace 재생에서 한 단계 더 나아가 실제 FP16 값이 RTL 누산기를
통과하도록 만든 단계다. 성능 수치는 합성 이후에 갱신해야 한다.
