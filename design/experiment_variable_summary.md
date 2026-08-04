# 실험변수 요약본

## 1. 이 파일의 역할

이 파일은 검증 단계에서 실제로 바꿔볼 수 있는 실험변수만 모아둔 요약본이다.

대상 파일은 두 개다.

- `system_hbm.ini`
- `ini/HBM2_samsung_2M_16B_x64.ini`

## 2. 어디를 바꾸면 되는가

| 파일 | 바꾸는 내용 | 방법 |
|---|---|---|
| `system_hbm.ini` | 채널 수, 주소 매핑, 스케줄링, PIM precision, 디버그 옵션 | 값을 직접 수정한다 |
| `ini/HBM2_samsung_2M_16B_x64.ini` | bank 수, bank group 수, row/column 구조, 타이밍, 전압, 전류 | 값을 직접 수정한다 |

## 3. `system_hbm.ini` 실험변수

### 3.1 구조와 정책

| 변수 | 역할 | 바꾸는 법 |
|---|---|---|
| `NUM_CHANS` | 논리 채널 수 | `16`, `1`, `64`처럼 바꾼다 |
| `JEDEC_DATA_BUS_BITS` | 데이터 버스 폭 | 보통 `64`를 유지한다 |
| `TRANS_QUEUE_DEPTH` | 트랜잭션 큐 깊이 | 숫자를 키우면 요청을 더 많이 쌓는다 |
| `CMD_QUEUE_DEPTH` | 명령 큐 깊이 | 숫자를 키우면 명령 대기 여유가 커진다 |
| `EPOCH_LENGTH` | 통계 구간 길이 | 숫자를 키우면 통계 집계 구간이 길어진다 |
| `ROW_BUFFER_POLICY` | row buffer 정책 | `open_page` / `close_page`로 바꾼다 |
| `ADDRESS_MAPPING_SCHEME` | 주소 매핑 방식 | 보통 `Scheme8`을 쓴다 |
| `SCHEDULING_POLICY` | 명령 발행 순서 | `rank_then_bank_round_robin` 등으로 바꾼다 |
| `QUEUING_STRUCTURE` | 큐 구조 | `per_rank` / `per_rank_per_bank`로 바꾼다 |
| `PIM_PRECISION` | PIM 정밀도 | `FP16`, `INT8`, `FP32` 중 하나로 바꾼다 |

### 3.2 디버그와 출력

| 변수 | 역할 | 바꾸는 법 |
|---|---|---|
| `DEBUG_TRANS_Q` | 트랜잭션 큐 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_CMD_Q` | 명령 큐 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_ADDR_MAP` | 주소 매핑 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_BUS` | 버스 상태 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_BANKSTATE` | bank state 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_BANKS` | bank 내부 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_POWER` | 전력 출력 | `false`를 `true`로 바꾼다 |
| `DEBUG_TRANS_TRACE` | 트랜잭션 trace | `false`를 `true`로 바꾼다 |
| `DEBUG_PIM_TIME` | PIM 시간 trace | `false`를 `true`로 바꾼다 |
| `DEBUG_CMD_TRACE` | PIM 명령 trace | `false`를 `true`로 바꾼다 |
| `DEBUG_PIM_BLOCK` | PIM block 내부 출력 | `false`를 `true`로 바꾼다 |
| `SHOW_SIM_OUTPUT` | 콘솔 출력 표시 | `false`를 `true`로 바꾼다 |
| `LOG_OUTPUT` | 로그 저장 | `false`를 `true`로 바꾼다 |
| `SIM_TRACE_FILE` | trace 파일명 | 원하는 파일명으로 바꾼다 |
| `VIS_FILE_OUTPUT` | 시각화 출력 | `false`를 `true`로 바꾼다 |
| `USE_LOW_POWER` | 저전력 모드 | `true` / `false`를 바꾼다 |
| `VERIFICATION_OUTPUT` | 검증용 출력 | 보통 `false`, 검증 시 `true` |
| `TOTAL_ROW_ACCESSES` | row 유지 제한 | 숫자를 바꾸면 row starvation 제어가 달라진다 |
| `PRINT_CHAN_STAT` | 채널 통계 출력 | `false`를 `true`로 바꾼다 |
| `PRINT_MEM_TRACE` | 메모리 trace 출력 | `false`를 `true`로 바꾼다 |

## 4. `ini/HBM2_samsung_2M_16B_x64.ini` 실험변수

### 4.1 구조 변수

| 변수 | 역할 | 바꾸는 법 |
|---|---|---|
| `NUM_BANK_GROUPS` | bank group 수 | bank group 개수를 숫자로 바꾼다 |
| `NUM_BANKS` | bank 수 | bank 수를 숫자로 바꾼다 |
| `NUM_COLS` | column 수 | row 안의 column 개수를 바꾼다 |
| `NUM_ROWS` | row 수 | bank 안의 row 개수를 바꾼다 |
| `NUM_PIM_BLOCKS` | bank-side PIM 블록 수 | PIM 블록 수를 숫자로 바꾼다 |
| `DEVICE_WIDTH` | 디바이스 폭 | 보통 `64`를 유지한다 |
| `BL` | burst length | burst 길이를 숫자로 바꾼다 |

### 4.2 타이밍 변수

| 변수 | 역할 | 바꾸는 법 |
|---|---|---|
| `RL` | read latency | read 지연을 숫자로 바꾼다 |
| `WL` | write latency | write 지연을 숫자로 바꾼다 |
| `tRCDRD` | activate 후 read 지연 | 숫자를 바꾸되 관련 값과 같이 본다 |
| `tRCDWR` | activate 후 write 지연 | 숫자를 바꾸되 관련 값과 같이 본다 |
| `tRAS` | row active 최소 시간 | 숫자를 바꾸되 `tRC`와 관계를 본다 |
| `tRP` | precharge 시간 | 숫자를 바꾸되 row 닫기 비용을 같이 본다 |
| `tRC` | row cycle time | row 전체 주기를 바꾼다 |
| `tRRDS`, `tRRDL` | activate 간 지연 | 짧은/긴 활성화 간격을 바꾼다 |
| `tCCDS`, `tCCDL`, `tCCDR` | column 간 지연 | column 접근 간격을 바꾼다 |
| `tRTPS`, `tRTPL` | read 후 precharge 지연 | read 직후 닫기 지연을 바꾼다 |
| `tWR` | write recovery time | write 후 안정화 시간을 바꾼다 |
| `tWTRS`, `tWTRL` | write-to-read 지연 | write 후 read 전환 시간을 바꾼다 |
| `tREFI`, `tREFISB` | refresh interval | refresh 빈도를 바꾼다 |
| `tRFC`, `tRFCSB` | refresh cycle time | refresh 소요 시간을 바꾼다 |
| `tXP` | power-down exit 지연 | 저전력 종료 후 복귀 시간을 바꾼다 |
| `tCKE` | clock enable 지연 | CKE 전환 지연을 바꾼다 |
| `tCMD` | 명령 기본 지연 | 명령 모델링 기본 단위를 바꾼다 |
| `AL` | additive latency | 보정 지연을 바꾼다 |
| `tCK` | 클럭 주기 | 전체 타이밍 스케일 기준을 바꾼다 |

#### 타이밍 변수 간 관계

아래 변수들은 서로 독립적으로 보기보다 하나의 타이밍 묶음으로 봐야 한다.

- `tRCDRD`와 `tRCDWR`
  - row를 activate한 뒤 read 또는 write를 시작하기까지의 준비 시간이다.
  - 보통 `tRCDRD`와 `tRCDWR`를 따로 보면 read와 write 준비 비용 차이를 볼 수 있다.
  - 둘 중 하나만 크게 바꾸면 activate 이후 read/write 균형이 깨질 수 있다.

- `tRAS`, `tRP`, `tRC`
  - `tRAS`는 row를 최소 얼마 동안 열어둬야 하는지 나타낸다.
  - `tRP`는 열린 row를 닫는 데 필요한 시간이다.
  - `tRC`는 row를 열고 닫아 다음 row를 다시 여는 전체 주기다.
  - 실무적으로는 `tRC`가 `tRAS + tRP`와 맞물려 있어야 row open/close 타이밍이 자연스럽다.
  - 따라서 `tRAS`나 `tRP`를 바꾸면 `tRC`도 함께 점검해야 한다.

- `tRRDS`, `tRRDL`
  - 둘 다 activate-to-activate 간격이지만, 짧은 경로와 긴 경로를 나눠 본 값이다.
  - bank group 안과 bank group 밖의 활성화 템포를 다르게 볼 때 쓰인다.
  - 한쪽만 낮추면 활성화가 너무 빽빽해질 수 있으므로 같이 보는 편이 좋다.

- `tCCDS`, `tCCDL`, `tCCDR`
  - column 계열 접근 간격이다.
  - 연속된 read/write 또는 column 전환이 얼마나 빨리 이어질 수 있는지를 정한다.
  - short와 long 값을 따로 둔 이유는 같은 그룹 내부와 더 먼 경로의 제약이 다르기 때문이다.
  - `tCCDR`은 read 경로 중심으로 볼 때 같이 확인해야 하는 보조값이다.

- `tRTPS`, `tRTPL`
  - read 이후 precharge로 넘어가기까지의 지연이다.
  - read를 끝내고 row를 닫는 시점을 얼마나 늦출지 정하는 값이다.
  - `tRP`와 같이 row close 비용을 구성한다.

- `tWTRS`, `tWTRL`
  - write 후 read로 넘어갈 때의 지연이다.
  - write가 끝난 직후 바로 read를 넣을 수 없어서 생기는 전환 제약이다.
  - short와 long이 나뉘어 있는 이유는 가까운 경로와 먼 경로의 전환 비용이 다르기 때문이다.

- `tWR`
  - write recovery time이다.
  - write 후 row를 닫기 전에 안정화가 필요하므로, `tRP`와 함께 보아야 한다.
  - write가 길어지면 precharge 가능 시점이 밀린다.

- `tREFI`, `tRFC`
  - `tREFI`는 refresh를 몇 사이클마다 할지 정하는 간격이다.
  - `tRFC`는 refresh 하나를 수행하는 데 걸리는 시간이다.
  - refresh는 자주 할수록 `tREFI`가 줄고, 한 번 할 때 오래 걸릴수록 `tRFC`가 커진다.
  - 두 값은 함께 봐야 refresh 오버헤드를 해석할 수 있다.

- `tREFISB`, `tRFCSB`
  - SB 모드에서의 refresh 간격과 refresh 소요 시간이다.
  - 일반 모드의 `tREFI`, `tRFC`와 짝을 이루는 별도 세트로 보면 된다.
  - PIM이나 저전력 모드에서 refresh 정책을 다르게 잡을 때 이 둘을 함께 조정한다.

- `tXP`, `tCKE`
  - 저전력 상태와 관련된 복귀 지연이다.
  - `tCKE`는 clock enable 전환에 필요한 시간이고, `tXP`는 power-down에서 빠져나올 때 필요한 시간이다.
  - 둘 다 저전력 진입/복귀 정책과 연결되므로 함께 확인해야 한다.

- `XAW`, `tXAW`
  - activate 폭주를 막기 위한 창(window) 제약이다.
  - `XAW`는 허용되는 activate 횟수이고, `tXAW`는 그 제한이 적용되는 시간 길이다.
  - 이 둘은 activation이 너무 몰리지 않도록 균형을 잡는다.

- `tCMD`, `AL`
  - 실제 DRAM 타이밍 제약이라기보다 명령 모델링과 보정에 가까운 값이다.
  - 실험에서 큰 비중을 두기보다, 다른 타이밍 값을 해석할 때 보조적으로 본다.

- `tCK`
  - 모든 타이밍의 기준 단위다.
  - 이 값이 바뀌면 나머지 타이밍 값을 사이클 관점에서 다시 읽어야 한다.

### 4.3 전력 변수

| 변수 | 역할 | 바꾸는 법 |
|---|---|---|
| `IDD0`~`IDD7` | 전류 모델 | 전류 값을 바꾼다 |
| `IDD0C`, `IDD0Q`, `IDD3NC`, `IDD3NQ`, `IDD4WC`, `IDD4WQ`, `IDD4RC`, `IDD4RQ` | 세부 전류 항목 | 필요한 항목만 조정한다 |
| `Vdd`, `Vddc`, `Vddq`, `Vpp` | 전압 모델 | 전압 값을 바꾼다 |
| `Ealu` | PIM ALU 에너지 | PIM 연산 에너지 값을 바꾼다 |
| `Ereg` | PIM register 에너지 | PIM 레지스터 에너지 값을 바꾼다 |

## 5. 바꾸는 방법 요약

1. 파일을 연다.
2. 원하는 변수 값을 수정한다.
3. 저장한다.
4. `./sim --gtest_filter=...`로 다시 실행한다.

예:

```ini
NUM_CHANS=1
DEBUG_CMD_TRACE=true
PRINT_MEM_TRACE=true
```

## 6. 검증 단계 추천

처음에는 아래만 바꾸면 된다.

- `NUM_CHANS`
- `PIM_PRECISION`
- `ADDRESS_MAPPING_SCHEME`
- `DEBUG_CMD_TRACE`
- `PRINT_MEM_TRACE`

그 다음에 구조를 볼 때:

- `NUM_BANKS`
- `NUM_BANK_GROUPS`
- `NUM_PIM_BLOCKS`
- `tRCDRD`
- `tRP`
- `tRFC`

를 조금씩 조정한다.

## 7. 주의

타이밍 값은 서로 연결되어 있다.  
특히 `tRAS`, `tRP`, `tRC`, `tRCDRD`, `tRCDWR`, `tRFC`, `tREFI`는 같이 보는 게 좋다.


