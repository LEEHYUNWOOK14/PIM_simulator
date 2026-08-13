# Phase 5 Logic row dispatcher 및 partial-port 병목 보고서

## 판정

**CONTROL PASS, BANDWIDTH FAIL** — free-engine 할당, tag 기반 partial routing, response arbitration 및 backpressure를 포함한 Logic dispatcher top을 구현·검증했다. 제어 면적은 작지만 shared partial input이 1 port라 16-engine array의 병렬 처리량을 공급하지 못한다.

따라서 이전의 “16 engines에서 Hierarchical 33.8 ms” 결과는 engine당 독립 partial input을 제공하는 fabric이 있을 때만 성립한다. 현재 합성된 dispatcher 기준 Hierarchical은 80.1 ms로 assumed GPU full 36.8 ms보다 느리다.

## 구현 기능

- round-robin free-engine 선택
- active engine/tag table
- duplicate active tag 거부
- interleaved partial의 tag-match routing
- unmatched partial 오류
- round-robin response arbitration
- output stall 시 선택 response backpressure
- engine duplicate/context error 집계

## 기능 검증

4개 row를 4개 engine에 배치하고, 두 bank의 partial을 row 사이에 interleave하여 단일 stream으로 공급했다.

```text
bank0: row0, row1, row2, row3
bank1: row0, row1, row2, row3
```

response를 2 cycle stall한 뒤 네 tag가 중복 없이 모두 반환되고 RMSNorm scalar가 bit-exact인지 확인했다.

```text
LOGIC_NORMALIZATION_DISPATCHER_TOP_TB PASS rows=4 responses=4 cycles=29
```

## 합성

조건: BANKS=16, Yosys generic synthesis.

| Engines | bare array cells | dispatcher top cells | control overhead | strict check |
|---:|---:|---:|---:|---|
| 4 | 110,100 | 111,053 | 953 (0.87%) | 문제 0 |
| 8 | 220,200 | 222,644 | 2,444 (1.11%) | 문제 0 |
| 16 | 440,400 | 445,337 | 4,937 (1.12%) | 문제 0 |

dispatcher 상태·arbiter의 면적은 engine array 대비 작다. 문제는 제어 면적이 아니라 partial 입력 port 수다.

## partial-port sweep

조건: 16 Logic engines, 4-lane multi-row Bank reducer, 16 banks, 100 MHz, 333 calls.

| Shared partial ports | pairs/cycle | Hierarchical latency | 1-port 대비 speedup | area 상태 |
|---:|---:|---:|---:|---|
| 1 | 1 | 80.104 ms | 1.00× | 445,337 cells 측정 |
| 2 | 2 | 55.395 ms | 1.45× | crossbar 미구현 |
| 4 | 4 | 43.040 ms | 1.86× | crossbar 미구현 |
| 8 | 8 | 36.863 ms | 2.17× | crossbar 미구현 |
| 16 | 16 | 33.775 ms | 2.37× | 독립 engine input 상한 |

assumed GPU full은 36.773 ms다. 8 ports는 0.091 ms 느리고, 16 ports에서만 앞선다. 이 차이는 GPU 가정 오차보다 작으므로 실제 GPU 실측 전에는 8/16-port 경계를 확정할 수 없다.

## 보정된 기본 모델

현재 구현된 shared port 수 1을 reference로 변경했다.

| 구조 | 333-call projected latency |
|---|---:|
| Logic-only | 16.397 ms |
| GPU full | 36.773 ms |
| Bank-only | 62.909 ms |
| Hierarchical, scalar Bank reducer | 107.395 ms |
| Hierarchical, 4-lane multi-row Bank reducer | 80.104 ms |

Logic-only 값에는 raw reducer/apply hardware가 없어 하한이다. 따라서 이를 최종 우승자로 선언할 수 없다.

## 결론

- RSQRT latency는 여전히 병목이 아니다.
- engine 복제보다 partial network 폭이 먼저다.
- 단일 shared stream에서는 16-engine 대부분이 partial을 기다린다.
- Hierarchical이 GPU offload 가정값을 넘으려면 거의 16 pairs/cycle에 가까운 cross-bank fabric이 필요하다.
- 이 fabric의 mux, wire, FIFO, arbitration 및 physical congestion 비용은 아직 측정되지 않았다.

## 다음 구현 우선순위

1. 4-port 및 8-port partial crossbar/arbiter RTL
2. bank별 parallel producer에서 port별 engine routing
3. 같은 tag의 16 partial을 tree로 먼저 합쳐 scalar engine에 전달하는 대안
4. 8/16-port generic area/path와 dispatcher contention simulation
5. crossbar까지 포함한 production top 통합 후 최종 engine 수 재선정

## 재현

```bash
bash verification/groot_normalization/run_logic_normalization_dispatcher_top_test.sh
bash verification/groot_normalization/run_logic_normalization_dispatcher_top_synthesis.sh
python tools/analyze_logic_partial_ports.py
```

산출물:

- `rtl/logic_normalization_dispatcher_top.sv`
- `results/logic_normalization_dispatcher_e{4,8,16}_yosys.log`
- `results/logic_partial_port_sweep.csv`
