# 17차 기술 구현 보고서: Logic Command Dispatch Coalescing

## 1. 목적

Global logic-PCU scheduler에서 다음 세 비용을 분리한다.

1. 실제 MAC compute
2. bank/logic 사이 operand transfer
3. logic 명령을 PCU scheduler에 전달하는 dispatch overhead

서로 다른 spatial position의 입력은 다르므로 MAC 계산을 제거할 수 없다. 다만 같은 cycle에 여러 채널이 동일한 PIM 명령을 요청하면 command word와 제어 신호는 한 번 broadcast할 수 있다.

## 2. 추가 설정

```ini
LOGIC_CMD_OVERHEAD=0
LOGIC_CMD_COALESCING=true
```

- `LOGIC_CMD_OVERHEAD`: 새로운 global command를 dispatch할 때 추가되는 cycle
- `LOGIC_CMD_COALESCING`: 같은 cycle·같은 command signature를 하나의 dispatch로 병합할지 결정
- 기본 overhead는 0이므로 기존 결과를 바꾸지 않는다.

## 3. Coalescing 판정

두 요청이 다음 조건을 모두 만족하면 뒤 요청은 dispatch overhead를 다시 지불하지 않는다.

```text
request.current_cycle == previous.current_cycle
request.command_signature == previous.command_signature
```

Coalescing은 dispatch에만 적용된다. 각 요청은 별도의 PCU service lane을 예약하고 compute 및 operand transfer 비용을 그대로 지불한다.

## 4. 단위 테스트

```bash
./sim --gtest_filter=LogicDieSchedulerTest.*
```

```text
[  PASSED  ] 4 tests.
```

검증 항목:

- PCU 8개의 명령 직렬화
- PCU 16개의 2-lane 병렬 실행
- 같은-cycle 동일 명령의 overhead 1회 적용
- coalescing 비활성화 시 모든 명령에 overhead 적용

## 5. Command Overhead Sweep

조건:

```text
Global PCU       = 16
Logic bandwidth = 64 B/cycle
Coalescing       = true
Workload         = MobileNetV4 expand pointwise, 196 positions
```

실행:

```bash
bash experiment/run_global_logic_command_overhead_sweep.sh
```

결과 파일:

```text
experiment/results/global_logic_command_overhead_sweep.csv
```

| Overhead | Logic requests | Dispatches | Coalesced | Pointwise cycle |
|---:|---:|---:|---:|---:|
| 0 | 42,336 | 720 | 41,616 | 86,244 |
| 1 | 42,336 | 720 | 41,616 | 86,601 |
| 2 | 42,336 | 720 | 41,616 | 86,958 |
| 4 | 42,336 | 720 | 41,616 | 87,668 |

동일 cycle broadcast로 요청의 98.30%가 기존 dispatch에 합쳐진다. Overhead가 0에서 4 cycle로 증가해도 전체 pointwise cycle 증가는 1.65%다.

## 6. Coalescing Ablation

Command overhead를 4 cycle로 고정했다.

```bash
bash experiment/run_global_logic_coalescing_ablation.sh
```

| Coalescing | Dispatches | Dispatch overhead 합 | Service cycles 합 | Pointwise cycle |
|---|---:|---:|---:|---:|
| Off | 42,336 | 169,344 | 338,688 | 170,580 |
| On | 720 | 2,880 | 172,224 | 87,668 |

Coalescing을 켜면 cycle이 1.95배 개선된다. Bank-side pointwise 기준 120,164 cycle과 비교하면 다음과 같다.

- Coalescing off: 0.70x로 bank보다 느림
- Coalescing on: 1.37x로 bank보다 빠름

따라서 `16 PCU + 64 B/cycle` crossover는 command overhead가 존재할 때 broadcast/coalescing 지원도 필요하다.

## 7. 해석 제한

현재 command signature는 PIM command encoding만 사용한다. 실제 RTL에서는 다음 조건까지 같아야 하나의 broadcast로 처리할 수 있다.

- opcode와 register index
- tensor/layer context
- source와 destination buffer
- precision과 accumulation mode
- 동기화 epoch

주소나 context가 다른 명령을 잘못 합치면 기능 오류가 발생한다. 따라서 98.30%는 현재 simulator command stream에서 얻은 상한이며 RTL command packet 형식이 정해진 뒤 다시 검증해야 한다.

## 8. 결론

Global logic PIM의 현재 최소 성능 후보는 다음과 같다.

```text
PCU count              = 16
Logic internal BW      = 64 B/cycle 이상
Command broadcast      = 필요
Same-cycle coalescing  = 필요
Hierarchy BW           = 64 B/cycle 기준
```

다음 단계는 shared weight buffer/multicast 모델이다. 현재 spatial group마다 같은 pointwise weight를 preload하므로, 중앙 logic die의 shared weight buffer가 이 중복 transaction과 저장공간을 얼마나 줄이는지 분리해 측정해야 한다.

