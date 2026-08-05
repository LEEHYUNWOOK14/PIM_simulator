# 80차 구현 보고서: Bank-local reduction RTL 초안

## 1. 목적

C++ cycle-level 실험에서 선택한 `8 banks × 16 entries × 1 port` 후보를 실제 하드웨어 인터페이스 형태로 구체화한다. 이번 단계의 목표는 완성된 HBM RTL이나 물리 설계가 아니라, 합성 가능한 제어 구조와 검증해야 할 경계를 명시하는 것이다.

## 2. 생성 파일

| 파일 | 역할 |
|---|---|
| `rtl/bank_local_reduction_buffer.sv` | 8-bank partial-sum 저장·누산 제어와 final handshake |
| `rtl/tb/bank_local_reduction_buffer_tb.sv` | 정상 누산, first-and-last, protocol error를 검사하는 testbench |
| `rtl/README.md` | 모듈 의미, 실행 명령, 미결 연구 항목 |

## 3. C++ 모델과 RTL 대응

| C++ 설정/동작 | RTL parameter/port |
|---|---|
| `BANK_LOCAL_ACCUMULATOR_BANKS=8` | `BANKS=8` |
| 총 128 entries | `ENTRIES_PER_BANK=16` |
| bank당 1 update port | 각 bank의 `update_valid_i/update_ready_o` lane |
| PIM block modulo bank mapping | PIM block별 고정 update lane |
| output key | `update_key_i`, `final_key_o` |
| partial FP16 burst | `update_partial_i[255:0]`, 16×FP16 = 32 B |
| accumulator backpressure | `update_ready_o` |
| final logic-die 전송 | `final_valid_o/final_ready_i/final_data_o` |

## 4. 동작 원리

1. Scheduler가 bank와 slot을 선택하고 첫 partial에 `update_first_i=1`을 보낸다.
2. 모듈은 빈 slot인지 확인하고 key와 첫 누산 결과를 저장한다.
3. 다음 partial은 같은 slot과 key를 사용해야 한다. 다르면 `protocol_error_o=1`이고 ready를 내리지 않는다.
4. 마지막 partial은 `update_last_i=1`로 표시한다.
5. 최종 합은 output register로 이동하고 slot은 즉시 반환된다.
6. Downstream이 막혀 final register가 비어 있지 않으면 해당 bank의 마지막 update에 backpressure를 건다.

## 5. FP16 arithmetic 경계

현재 모듈은 FP16 덧셈기를 내부에서 임의 구현하지 않는다. 대신 bank별로 다음 포트를 제공한다.

```text
add_lhs_o + add_rhs_o -> 외부 FP16 vector adder -> add_result_i
```

C++ 모델은 16-lane FP16 burst를 update latency 1로 가정한다. 실제 FP16 adder가 2~N cycle pipeline이면 RTL에 valid pipeline을 추가하고 C++의 `BANK_LOCAL_ACCUMULATOR_LATENCY`를 합성 결과로 갱신해야 한다.

## 6. Testbench 검사 항목

- 같은 key의 `10 + 20 + 12 = 42` 누산
- first와 last가 동시에 들어오는 단일 partial 출력
- 빈 slot에 continuation partial을 보내는 protocol error
- final valid/ready 출력 handshake

로컬 도구 설치와 실행 명령:

```bash
bash rtl/bootstrap_iverilog_local.sh
bash rtl/run_tests.sh
```

## 7. 현재 검증 상태

`sudo` 없이 Ubuntu의 Icarus Verilog 12.0 패키지를 사용자 홈에 압축 해제했다. Reduction buffer와 logic-die link arbiter를 SystemVerilog 2012 모드로 compile하고 simulation을 실행해 `BANK_LOCAL_REDUCTION_BUFFER_TB PASS`, `LOGIC_DIE_LINK_ARBITER_TB PASS`를 확인했다. Verilator lint, Yosys/FPGA/ASIC synthesis, timing·area·power 분석은 아직 수행하지 않았다.

현재 단일 link arbiter는 256-bit burst 하나, 즉 32 B/cycle을 처리한다. C++ 실험의 `LOGIC_ACCUMULATOR_BW=64`를 RTL로 재현하려면 2-output-lane 구조가 필요하다. 따라서 현재 arbiter PASS만으로 64 B/cycle 성능 후보가 구현됐다고 주장하지 않는다.

## 8. 다음 구현 순서

1. Icarus Verilog 또는 Verilator를 설치해 control testbench를 통과시킨다.
2. FP16 vector adder의 구현 또는 IP wrapper와 valid pipeline을 추가한다.
3. Slot allocator를 추가하고 key collision 처리 정책을 정한다.
4. Bank output을 logic-die link 하나로 모으는 arbiter를 구현한다.
5. 합성에서 latency, Fmax, area, power를 측정해 C++ 설정을 재보정한다.

## 9. 연구자가 결정해야 할 항목

- FP16 adder를 bank마다 둘지 time-multiplex할지
- Slot mapping을 direct, hash, CAM 중 무엇으로 할지
- 8개 bank에서 logic die로 이어지는 reduction/interconnect topology
- 면적·전력 예산에서 4 KiB/rank accumulator가 허용되는지
- Tile-batch 명령과 slot allocation의 담당 주체

이 선택은 성능 코드만으로 자동 확정할 수 없으며 프로젝트 novelty와 물리 제약을 함께 고려해야 한다.
