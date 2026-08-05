# 81차 구현 보고서: 64 B/cycle dual link와 통합 RTL 경로

## 1. 목적

C++ 후보의 `LOGIC_ACCUMULATOR_BW=64`를 RTL 데이터 폭으로 재현한다. FP16 burst 하나는 `16 lane × 16 bit = 256 bit = 32 B`이므로 한 cycle에 burst 두 개를 보내는 dual-lane link가 필요하다.

## 2. 구현 파일

| 파일 | 역할 |
|---|---|
| `rtl/logic_die_dual_link_arbiter.sv` | 8개 bank 중 최대 2개를 round-robin으로 선택 |
| `rtl/hierarchical_reduction_path.sv` | Reduction buffer와 dual-link arbiter를 직접 연결한 top-level |
| `rtl/tb/logic_die_dual_link_arbiter_tb.sv` | 2-output 선택, fairness, backpressure 검증 |
| `rtl/tb/hierarchical_reduction_path_tb.sv` | Bank partial부터 64 B link 출력까지 통합 검증 |

## 3. 동작 원리

1. Round-robin pointer부터 valid bank를 검색한다.
2. 첫 두 bank를 output lane 0과 lane 1에 배치한다.
3. 두 lane이 모두 ready일 때만 두 input에 ready를 반환한다.
4. Handshake 후 두 번째 source 다음 bank로 pointer를 이동한다.
5. Valid input이 하나뿐이면 lane 0만 사용한다.

두 output의 ready를 결합한 이유는 lane 0이 stall된 동안 lane 1만 전송되어 round-robin pointer가 바뀌면, stall 중인 lane 0의 payload가 바뀔 수 있기 때문이다. 현재 구조는 안정성을 우선하며 한 lane만 ready인 경우 두 lane을 함께 기다린다.

## 4. 실제 검증 결과

실행 명령:

```bash
bash rtl/run_tests.sh
```

결과:

```text
BANK_LOCAL_REDUCTION_BUFFER_TB PASS
HIERARCHICAL_REDUCTION_PATH_TB PASS
LOGIC_DIE_DUAL_LINK_ARBITER_TB PASS
LOGIC_DIE_LINK_ARBITER_TB PASS
```

통합 testbench에서 bank 0과 bank 1이 각각 32 B burst를 동시에 final로 만들고, dual link의 lane 0과 lane 1로 같은 cycle에 전달되는 것을 확인했다. 한 output lane만 ready인 상태를 두 cycle 유지해도 두 payload와 source ID가 변하지 않았다.

## 5. C++ 모델과의 대응

| C++ 후보 | RTL 현재 구현 |
|---|---|
| 8 accumulator banks | 8 reduction input lanes |
| Bank당 16 entries | `ENTRIES_PER_BANK=16` |
| FP16 burst 32 B | `DATA_WIDTH=256` |
| Link 64 B/cycle | 256-bit output lane 2개 |
| Backpressure | coupled `valid/ready` |
| PIM-block source | `link_source_o` |

따라서 데이터 폭과 최대 burst 처리량은 C++ 후보와 일치한다. 그러나 실제 평균 64 B/cycle은 두 bank가 동시에 valid일 때만 가능하며, arbitration 분포와 FP16 adder pipeline을 포함한 sustained bandwidth는 아직 측정하지 않았다.

## 6. 남은 검증

1. 내부 skid buffer를 추가해 output lane별 독립 ready를 지원할지 판단한다.
2. FP16 vector adder latency를 포함한 valid pipeline을 구현한다.
3. Random valid pattern으로 fairness와 sustained bandwidth를 수천 cycle 검증한다.
4. Yosys 또는 ASIC 합성에서 dual-link mux의 timing과 area를 측정한다.
5. 합성 결과를 C++의 latency와 bandwidth 설정에 되돌려 넣는다.

## 7. 현재 주장 가능한 범위

현재는 8-bank reduction control과 2×256-bit shared link의 RTL 기능 testbench가 통과했다. HBM TSV가 실제로 매 cycle 64 B를 운반할 수 있다는 물리적 주장, FP16 연산 latency 1-cycle 주장, 면적·전력 허용 가능성은 아직 검증되지 않았다.
