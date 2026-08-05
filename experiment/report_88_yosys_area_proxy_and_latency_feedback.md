# 88차 실험 보고서: Yosys 합성 면적 proxy와 C++ latency feedback

## 1. 목적

87차까지 계층형 PIM의 기능과 timing trace를 검증했지만 다음 두 값은 가정이었다.

- FP16 16-lane accumulator가 한 cycle에 동작할 수 있는가
- 64 channel × 8 PIM block마다 accumulator를 복제할 수 있는가

이번 실험은 오픈소스 합성 도구 Yosys로 generic gate 수와 조합 논리 깊이를 얻고,
가정한 accumulator latency를 C++ 시뮬레이터에서 바꿨을 때 cycle이 어떻게 변하는지
확인한다.

## 2. 도구 설치와 재현 명령

WSL 사용자 영역에 Yosys 0.52를 설치한다. sudo는 필요하지 않다.

```bash
bash rtl/bootstrap_yosys_local.sh
```

합성 sweep:

```bash
bash rtl/run_synthesis_sweep.sh
```

C++ latency feedback sweep:

```bash
bash experiment/run_fp16_latency_feedback.sh
```

두 실험 모두 결과 CSV와 개별 log를 `experiment/results` 아래에 저장한다. latency
스크립트는 `system_hbm_1ch.ini`를 임시 변경하고 종료 시 원본을 자동 복원한다.

## 3. 합성 방법과 한계

Yosys의 generic gate mapping과 ABC를 사용했다. `flatten; opt; stat; ltp -noff`를
실행해 gate 수와 longest topological path를 측정했다.

이 수치는 **실제 ASIC 면적, ns, GHz, 전력 값이 아니다.** 사용한 generic
`cells.lib`에는 선택한 반도체 공정의 물리 면적과 delay 정보가 없다. 따라서 서로
다른 구조의 상대적 규모를 비교하는 proxy로만 사용한다.

## 4. FP16 lane 폭 합성 결과

| FP16 lane | 데이터 폭 | Generic cell | Topological depth |
|---:|---:|---:|---:|
| 1 | 16 bit | 3,227 | 232 |
| 2 | 32 bit | 6,454 | 232 |
| 4 | 64 bit | 12,908 | 232 |
| 8 | 128 bit | 25,816 | 232 |
| 16 | 256 bit | 51,632 | 232 |

lane은 독립 계산이므로 cell 수가 정확히 선형으로 증가했다. 병렬 lane 수가 늘어도
각 lane의 경로는 같아 depth는 232로 유지됐다.

depth 232는 “232 cycle”이라는 뜻이 아니다. 한 cycle 안에 직렬로 지나가야 하는
generic logic stage가 많다는 뜻이다. 따라서 물리 합성 근거 없이 C++
`BANK_LOCAL_ACCUMULATOR_LATENCY=1`을 확정값으로 쓰기는 어렵다.

## 5. source buffer 포함 결과

source 하나를 다음 조건으로 합성했다.

```text
16 FP16 lane
16 key/data entries
64-bit key
256-bit data
valid-ready 및 final register
```

| 구성 | Generic cell | Flip-flop | Depth |
|---|---:|---:|---:|
| 16-lane FP16 pipeline만 | 51,632 | 0 | 232 |
| source buffer + pipeline | 88,987 | 5,457 | 244 |
| 차이: buffer/control proxy | 37,355 | 5,457 | 분리 측정 안 함 |

현재 RTL은 entry array를 reset 가능한 register와 mux로 합성한다. 실제 ASIC에서는
register file 또는 SRAM macro를 사용하면 수치가 달라질 수 있다. 다만 source마다
16×256-bit data와 key를 무조건 복제하는 구조가 가볍지 않다는 사실은 확인된다.

## 6. 512-source 구조 추정

512개의 source buffer는 유지하고 16-lane burst pipeline 수만 공유한다고 가정했다.

| 공유 burst pipeline | FP16 lane 총수 | Cell proxy | Flip-flop proxy |
|---:|---:|---:|---:|
| 1 | 16 | 19,177,392 | 2,793,984 |
| 2 | 32 | 19,229,024 | 2,793,984 |
| 4 | 64 | 19,332,288 | 2,793,984 |
| 8 | 128 | 19,538,816 | 2,793,984 |
| 16 | 256 | 19,951,872 | 2,793,984 |
| 64 | 1,024 | 22,430,208 | 2,793,984 |
| 512 전용 복제 | 8,192 | 45,561,344 | 2,793,984 |

완전 복제는 가산 datapath만 약 2,643만 cell proxy이고 buffer까지 합치면 약
4,556만 cell proxy다. 1개 공유 pipeline으로 줄여도 source buffer 때문에 약
1,918만 cell proxy가 남는다.

따라서 다음 설계 비교는 가산기 공유만으로 끝나지 않고 entry storage도 함께 봐야
한다. 후보는 다음과 같다.

1. source별 16-entry register를 유지하고 FP16 pipeline만 공유
2. channel별 shared accumulator RAM과 8-source arbiter 사용
3. logic die 전체 shared SRAM bank와 여러 FP16 pipeline 사용
4. bank-local에서 더 많이 합쳐 logic die live entry 수 자체를 줄임

어느 구조가 연구의 최종안인지는 면적 예산과 목표 throughput을 연구자가 정한 뒤
선택해야 한다.

## 7. C++ latency feedback 결과

빠른 1채널 MobileNetV4 depthwise에서 `BANK_LOCAL_ACCUMULATOR_LATENCY`만 바꿨다.
나머지는 aggregation 3, entries 128, banks 8, port 1로 고정했다.

| Latency | Total cycle | 기준 대비 증가 | Partial/final |
|---:|---:|---:|---:|
| 1 | 29,894 | 0 | 384 / 128 |
| 2 | 29,894 | 0 | 384 / 128 |
| 4 | 30,282 | +388 | 384 / 128 |
| 8 | 30,803 | +909 | 384 / 128 |
| 16 | 31,798 | +1,904 | 384 / 128 |

latency 2가 숨겨진 이유는 accumulator 서비스와 기존 DRAM/PIM 동작이 겹치기
때문이다. latency가 더 커지면 overlap으로 감출 수 있는 범위를 넘어 total cycle이
증가한다. latency 16은 latency 1보다 약 6.37% 느리다.

## 8. 현재 설계 판단

이번 결과만으로 몇 stage pipeline이 정답이라고 말할 수는 없다. 공정 library,
목표 clock, 전압, 배치배선 정보가 없기 때문이다. 그러나 다음은 기술적으로 분명하다.

- 512 source마다 16-lane 조합 가산기를 완전 복제하는 안을 기본안으로 확정하면 안 된다.
- latency 1도 확정값이 아니라 optimistic lower bound로 표시해야 한다.
- C++ sweep 기준에는 latency 1뿐 아니라 2, 4, 8, 16을 포함해야 한다.
- shared pipeline 수와 accumulator storage banking을 함께 설계 변수로 만들어야 한다.

## 9. 다음 구현

다음 RTL 작업은 `source request → shared FP16 pipeline → key/slot writeback` 구조다.
우선 channel 하나의 8 source가 1·2·4개 16-lane pipeline을 공유하는 scheduler를
만든다. 실제 payload trace에서 정확도, FIFO occupancy, stall, 처리 cycle을 비교한
뒤 64채널 전체로 확장한다.

그 결과의 `pipeline count`는 C++의 accumulator port 수에, 실제 합성 pipeline
stage는 accumulator latency에 대응시킨다. 이렇게 해야 Verilog와 cycle simulator의
파라미터가 같은 하드웨어 가정을 표현한다.
