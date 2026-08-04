# 검증 단계 설정 파일 수정 가이드

## 1. 목적

이 문서는 코드 수정 없이, 현재 시뮬레이터의 검증 단계에서 바로 바꿀 수 있는 설정 파일 항목과 수정 방법을 정리한다.

대상은 다음 두 파일이다.

- `system_hbm.ini`
- `ini/HBM2_samsung_2M_16B_x64.ini`

이 문서는 **설정 파일로 가능한 수정**만 다룬다.  
새 파라미터를 추가하거나 연산 동작을 바꾸는 작업은 코드 수정이 필요하다.

## 2. 수정 전에 알아둘 점

1. `system_hbm.ini`는 시뮬레이터 실행 정책과 디버그 옵션을 정한다.
2. `ini/HBM2_samsung_2M_16B_x64.ini`는 메모리 디바이스 타이밍과 구조를 정한다.
3. 값만 바꾸면 되는 항목과, 코드 수정이 필요한 항목을 구분해야 한다.
4. 검증 단계에서는 먼저 작은 범위에서 바꾸고 테스트를 다시 돌리는 것이 좋다.

## 3. `system_hbm.ini`에서 바꿀 수 있는 항목

### 3.1 채널 및 큐 관련

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `NUM_CHANS` | 논리 채널 수 | 채널 병렬성, 전체 처리량 변화 |
| `JEDEC_DATA_BUS_BITS` | 데이터 버스 폭 | 전송량과 대역폭 영향 |
| `TRANS_QUEUE_DEPTH` | 트랜잭션 큐 깊이 | 호스트 요청 적재량 변화 |
| `CMD_QUEUE_DEPTH` | 명령 큐 깊이 | DRAM 명령 발행 여유 변화 |
| `EPOCH_LENGTH` | 통계 집계 주기 | 출력 통계의 granularity 변화 |

### 3.2 주소 매핑 및 스케줄링

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `ADDRESS_MAPPING_SCHEME` | 주소 디코딩 방식 | 채널/뱅크 분산 방식 변화 |
| `ROW_BUFFER_POLICY` | open-page / close-page | row hit behavior 변화 |
| `SCHEDULING_POLICY` | rank/bank 스케줄링 방식 | 명령 발행 순서 변화 |
| `QUEUING_STRUCTURE` | 큐 구조 | rank 단위 / bank 단위 관리 방식 변화 |

### 3.3 PIM 관련

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `PIM_PRECISION` | `FP16`, `INT8`, `FP32` | PIM 연산 정밀도와 결과 표현 변화 |
| `PIM_MODE` | PIM 동작 모드 | bank-side PIM 동작 방식 변화 |

### 3.4 디버그 및 출력

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `DEBUG_CMD_TRACE` | 명령 trace 출력 | PIM 명령 흐름 확인 |
| `DEBUG_PIM_TIME` | PIM 시간 trace | PIM 실행 시점 확인 |
| `DEBUG_PIM_BLOCK` | PIM block 내부 출력 | 연산 내부 상태 확인 |
| `DEBUG_TRANS_Q` | 트랜잭션 큐 출력 | 요청 적재 상태 확인 |
| `DEBUG_CMD_Q` | 명령 큐 출력 | 명령 큐 상태 확인 |
| `DEBUG_ADDR_MAP` | 주소 매핑 출력 | 주소 분해 확인 |
| `DEBUG_BANKSTATE` | bank state 출력 | bank open/close 상태 확인 |
| `DEBUG_BANKS` | bank 동작 출력 | bank 레벨 동작 확인 |
| `DEBUG_BUS` | bus 상태 출력 | 버스 전송 상태 확인 |
| `DEBUG_POWER` | power 출력 | 전력 통계 확인 |
| `PRINT_CHAN_STAT` | 채널 통계 출력 | 채널별 통계 확인 |
| `PRINT_MEM_TRACE` | 메모리 trace 출력 | 요청 흐름 추적 |
| `SHOW_SIM_OUTPUT` | 콘솔 출력 표시 | 실행 메시지 표시 |
| `LOG_OUTPUT` | 로그 파일 출력 | 로그 저장 여부 |
| `SIM_TRACE_FILE` | trace 파일 이름 | trace 저장 경로 지정 |
| `VERIFICATION_OUTPUT` | 검증용 출력 활성화 | 외부 검증용 출력 생성 |

### 3.5 전력 및 저전력

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `USE_LOW_POWER` | idle 시 저전력 진입 | 대기 시 전력 동작 변화 |
| `TOTAL_ROW_ACCESSES` | row open 유지 한도 | row starvation 방지 정책 변화 |

## 4. `ini/HBM2_samsung_2M_16B_x64.ini`에서 바꿀 수 있는 항목

### 4.1 구조 관련

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `NUM_BANKS` | bank 수 | bank 병렬성 및 PIM 배치 영향 |
| `NUM_BANK_GROUPS` | bank group 수 | bank group 배치와 타이밍 영향 |
| `NUM_ROWS` | row 수 | 메모리 공간 구조 변화 |
| `NUM_COLS` | column 수 | 열 방향 접근 구조 변화 |
| `NUM_PIM_BLOCKS` | PIM block 수 | bank-side PIM 병렬도 변화 |
| `DEVICE_WIDTH` | 디바이스 폭 | 데이터 폭과 내부 경로 영향 |

### 4.2 타이밍 관련

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `tRFC` | refresh cycle 시간 | refresh 부담 변화 |
| `tRFCSB` | SB refresh cycle 시간 | PIM/refresh 상호작용 변화 |
| `tREFI` | refresh interval | refresh 빈도 변화 |
| `tREFISB` | SB refresh interval | PIM 모드에서 refresh 빈도 변화 |
| `tCK` | 클럭 주기 | 전체 타이밍 스케일 변화 |
| `tRAS` | row active time | row 활성 유지 시간 변화 |
| `tRCDRD` | read activate delay | read 접근 지연 변화 |
| `tRCDWR` | write activate delay | write 접근 지연 변화 |
| `tRC` | row cycle time | row 전환 총시간 변화 |
| `tRP` | precharge time | row 닫기 시간 변화 |
| `tWR` | write recovery time | write 후 복구 시간 변화 |
| `tRTRS` | read-to-read/transfer 계열 지연 | 버스 전환 영향 |
| `tXAW` | activate window | activate burst 제한 |
| `tCKE`, `tXP`, `tCMD` | 저전력 및 명령 타이밍 | 전력/명령 제약 변화 |

### 4.3 전력 관련

| 항목 | 의미 | 수정 효과 |
|---|---|---|
| `IDD0`~`IDD7` | 전류 소모 모델 | 전력 통계 변화 |
| `IDD0C`, `IDD0Q` 등 | 세부 전류 값 | 각 명령 전력 모델 변화 |
| `Vdd`, `Vddq`, `Vpp`, `Vddc` | 전압 값 | 전력 계산과 타이밍 영향 |
| `Ealu`, `Ereg` | ALU, register 에너지 | PIM 에너지 통계 변화 |

### 4.4 DDR4 호환 타이밍

| 항목 | 의미 |
|---|---|
| `tCCDL`, `tCCDS` | column-to-column delay |
| `tRRDL`, `tRRDS` | activate 간 지연 |
| `tWTRL`, `tWTRS` | write-to-read delay |
| `tRTPL`, `tRTPS` | read-to-precharge delay |

## 5. 수정하는 방법

### 5.1 직접 수정

가장 쉬운 방법은 텍스트 편집기로 `.ini` 파일을 열고 값을 바꾸는 것이다.

예:

```ini
NUM_CHANS=64
PIM_PRECISION=FP16
DEBUG_CMD_TRACE=true
PRINT_MEM_TRACE=true
```

수정 후에는 저장하고 다시 `./sim --gtest_filter=...`를 실행하면 된다.

### 5.2 비교 실험용으로 복사해서 수정

원본을 보존하려면 파일을 복사해서 실험용 버전을 만든다.

예:

```bash
cp system_hbm.ini system_hbm_debug.ini
cp ini/HBM2_samsung_2M_16B_x64.ini ini/HBM2_samsung_2M_16B_x64_debug.ini
```

그 다음 실험용 파일을 수정해서 사용한다.

### 5.3 한 번에 하나씩 바꾸기

검증 단계에서는 여러 항목을 동시에 바꾸지 않는 편이 좋다.

추천 순서:

1. `DEBUG_CMD_TRACE` 켜기
2. `DEBUG_PIM_TIME` 켜기
3. `PRINT_MEM_TRACE` 켜기
4. `PIM_PRECISION` 바꾸기
5. `NUM_CHANS` 바꾸기
6. `ADDRESS_MAPPING_SCHEME` 바꾸기

## 6. 실험 예시

### 6.1 기능 검증용

```ini
PIM_PRECISION=FP16
DEBUG_CMD_TRACE=true
DEBUG_PIM_TIME=false
PRINT_MEM_TRACE=false
```

### 6.2 성능 분석용

```ini
PIM_PRECISION=FP16
DEBUG_CMD_TRACE=false
DEBUG_PIM_TIME=false
PRINT_MEM_TRACE=false
PRINT_CHAN_STAT=true
```

### 6.3 내부 흐름 확인용

```ini
DEBUG_CMD_TRACE=true
DEBUG_PIM_TIME=true
DEBUG_PIM_BLOCK=true
PRINT_MEM_TRACE=true
```

## 7. 검증 단계에서 자주 만지는 항목

처음에는 아래 항목만 건드려도 충분하다.

- `PIM_PRECISION`
- `NUM_CHANS`
- `ADDRESS_MAPPING_SCHEME`
- `DEBUG_CMD_TRACE`
- `DEBUG_PIM_TIME`
- `PRINT_MEM_TRACE`

## 8. 아직 코드 수정이 필요한 항목

아래는 설정 파일만으로는 안 되고 코드 수정이 필요한 경우다.

- `ENABLE_LOGIC_DIE_PIM`
- `NUM_LOGIC_PIM_UNITS`
- `LOGIC_PIM_LATENCY`
- `LOGIC_DIE_BW`
- `PIM_TARGET`
- `CONV`, `DW CONV`, `H-SWISH` 같은 새 연산 추가

이런 값은 현재 설정 파일에 정의되어 있지 않으므로, `ConfigurationData.h`와 관련 코드부터 추가해야 한다.

## 9. 결론

검증 단계에서는 설정 파일로 충분히 많은 실험을 할 수 있다.  
먼저 `system_hbm.ini`로 디버그와 precision을 조절하고, 필요하면 `ini/HBM2_samsung_2M_16B_x64.ini`에서 구조와 타이밍을 바꾼다.  
새 기능을 넣는 순간부터는 코드 수정이 필요하다.



