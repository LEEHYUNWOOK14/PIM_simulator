# Logic-PIM RTL 파라미터 인터페이스 초안

## 1. 문서 목적

현재 C++ simulator에서 검증한 계층형 PIM 구조를 향후 Verilog RTL 파라미터로 연결하기 위한 인터페이스 초안이다. 아래 값은 확정된 물리 설계가 아니라 simulator 후보점과 연구자가 결정해야 할 변수를 구분해 기록한다.

## 2. 현재 Simulator 후보점

| 항목 | 후보값 | 근거 |
|---|---:|---|
| HBM channel | 64 | 현재 프로젝트와 simulator 기준 구조 |
| Bank-side PIM blocks/channel | 8 | 기존 HBM2-PIM 설정 |
| Global logic PCU | 16 | MobileNetV4 전체 UIB 최초 bank crossover |
| Logic PCU latency | 2 cycles | 현재 timing 가정 |
| Logic internal bandwidth | 64 B/cycle | PCU 16개에서 최초 pointwise crossover |
| Hierarchy bandwidth | 64 B/cycle | 현재 bank/logic tensor transfer 기준 |
| Spatial grouping | 사용 | expand 21 groups, project 32 groups |
| Command coalescing | 사용 | overhead 4 조건에서 1.95x 개선 |
| Shared weight buffer | 65,536 B 후보 | MobileNetV4 UIB의 expand 49,152 B와 project 65,536 B를 순차 수용 |

## 3. 권장 Verilog Parameter

```systemverilog
parameter int HBM_CHANNELS             = 64;
parameter int BANK_PCU_PER_CHANNEL     = 8;
parameter int LOGIC_PCU_COUNT          = 16;
parameter int LOGIC_PCU_LATENCY        = 2;
parameter int LOGIC_DATA_BYTES_PER_CYCLE = 64;
parameter int HIERARCHY_BYTES_PER_CYCLE  = 64;
parameter int LOGIC_CMD_OVERHEAD       = 4;
parameter bit ENABLE_CMD_COALESCING    = 1'b1;
parameter int CMD_SIGNATURE_WIDTH      = 32;
parameter int LOGIC_QUEUE_DEPTH        = 64;
parameter int WEIGHT_BUFFER_BYTES      = 65536; // MobileNetV4 UIB 트래픽 실험의 1차 후보
parameter int WEIGHT_FILL_CHANNELS     = 32; // row-interleaved 정책의 최소 실험 crossover 후보
parameter string WEIGHT_FILL_POLICY    = "row_interleaved";
parameter int WEIGHT_STAGING_ROW       = 2048;
parameter int WEIGHT_BUFFER_WRITE_PORTS = 4;
parameter int WEIGHT_BUFFER_WRITE_LATENCY = 1; // 1~4 cycle sweep 통과
```

## 4. RTL 모듈 경계

| 모듈 | 주요 역할 | 필수 입력/출력 |
|---|---|---|
| `bank_pcu_array` | 기존 bank-side elementwise/depthwise 처리 | bank data, PIM command, local result |
| `logic_cmd_router` | bank와 logic 연산 분류 | opcode, placement, tensor context |
| `logic_cmd_coalescer` | 동일 epoch 명령 broadcast 병합 | command signature, channel mask |
| `logic_pcu_scheduler` | global PCU lane 할당과 queue 관리 | command, ready/valid, PCU completion |
| `logic_pcu_array` | cross-bank GEMV/reduction 실행 | operands, weight, partial sum |
| `hierarchy_interconnect` | 64채널과 logic die 사이 이동 | channel mask, payload, backpressure |
| `shared_weight_buffer` | pointwise weight 재사용 | layer id, weight address, cache hit/miss |
| `result_router` | logic 결과를 bank 또는 다음 계층에 전달 | destination, result data |

## 5. Command Packet 최소 필드

| 필드 | 목적 | 연구 결정 필요 여부 |
|---|---|---|
| opcode | MAC, MAD, reduction 등 구분 | 필요 |
| channel mask | broadcast 대상 채널 그룹 | 필요 |
| source buffer | 입력 또는 partial sum 위치 | 필요 |
| destination buffer | 결과 저장 위치 | 필요 |
| tensor/layer id | 잘못된 명령 coalescing 방지 | 필요 |
| precision | FP16/INT8 등 데이터 형식 | 필요 |
| accumulation mode | local/global reduction 방식 | 필요 |
| epoch/barrier id | 명령 순서와 동기화 보장 | 필요 |

현재 simulator는 주로 opcode와 PIM register encoding으로 signature를 만든다. RTL에서는 위 context가 다른 명령을 합치면 안 된다.

## 6. Simulator와 RTL Parameter 대응

| Simulator 설정 | RTL parameter | 비고 |
|---|---|---|
| `NUM_CHANS` | `HBM_CHANNELS` | 현재 64 고정 |
| `NUM_PIM_BLOCKS` | `BANK_PCU_PER_CHANNEL` | bank-side 구조 |
| `NUM_LOGIC_PIM_UNITS` | `LOGIC_PCU_COUNT` | global scheduler 기준 |
| `LOGIC_PIM_LATENCY` | `LOGIC_PCU_LATENCY` | RTL 합성 후 갱신 필요 |
| `LOGIC_PIM_BW` | `LOGIC_DATA_BYTES_PER_CYCLE` | 내부 interconnect 포함 |
| `HIERARCHY_PIM_BW` | `HIERARCHY_BYTES_PER_CYCLE` | bank/logic 경계 |
| `LOGIC_CMD_OVERHEAD` | `LOGIC_CMD_OVERHEAD` | command router 지연 |
| `LOGIC_CMD_COALESCING` | `ENABLE_CMD_COALESCING` | channel-mask broadcast 필요 |
| `LOGIC_WEIGHT_FILL_CHANNELS` | `WEIGHT_FILL_CHANNELS` | channel별 tile이 한 row에 들어가는지 함께 검증 |
| `LOGIC_WEIGHT_FILL_POLICY` | `WEIGHT_FILL_POLICY` | 현재 round-robin 후보; bank-count 균등화는 이득 없음 |

## 7. 연구자가 채워야 하는 값

다음 값은 simulator가 자동으로 정답을 정할 수 없다.

1. PCU 16개의 허용 면적과 전력
2. 64 B/cycle interconnect의 배선 폭과 목표 주파수
3. shared weight buffer 용량과 bank 수
4. command signature와 epoch 정의
5. partial sum reduction network 구조
6. bank-side와 logic-side 동시 실행 arbitration 정책
7. MobileNetV4 외 workload에서의 최소 성능 조건

## 8. 다음 검증 게이트

1. 65,536 B shared weight buffer의 fill을 여러 HBM channel에 stripe할 interconnect를 결정한다.
2. RTL command packet 필드를 확정한다.
3. Verilog scheduler에서 16 PCU와 2개 이상 lane 동시 완료를 검증한다.
4. 합성 결과의 PCU latency와 bandwidth를 simulator 설정에 다시 입력한다.
5. MobileNetV4 전체 UIB 결과가 C++ simulator와 RTL timing model에서 같은 경향을 보이는지 비교한다.
