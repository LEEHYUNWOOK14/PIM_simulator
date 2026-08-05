# 91차 실험 보고서: MobileNetV4 UIB 통합 trace 계약

## 1. 목적

이 실험은 따로 검증해 온 pointwise와 depthwise 경로가 실제 MobileNetV4 UIB 한 블록에서
연속된 데이터로 연결되는지 기계 판독 가능한 trace로 남긴다. 최종 RTL 통합 trace의 바로 전
단계로서 다음 다섯 단계의 순서, cycle 범위, 원소 수와 FP16 bit 해시를 고정한다.

```text
expand pointwise (logic die)
  -> depthwise 3x3 (bank-local + logic accumulation)
  -> project pointwise (logic die)
  -> residual ADD (bank side)
  -> ReLU/readback (bank side)
```

## 2. 구현

`LOGIC_UIB_TRACE_FILE` 설정을 추가했다. 기본값은 `none`이므로 기존 테스트에는 파일 I/O나
동작 변화가 없다. 경로를 지정하면 `ActualShapeUibRunsEndToEnd`가 다음 열을 기록한다.

| 열 | 의미 |
|---|---|
| `stage`, `target` | UIB 단계와 배치 계층 |
| `start_cycle`, `end_cycle`, `cycles` | 시뮬레이터 공통 시간축에서의 구간 |
| `input_elements`, `output_elements` | FP16 논리 원소 수 |
| `input_fp16_hash`, `output_fp16_hash` | FNV-1a 방식으로 계산한 FP16 bit열 식별자 |

해시는 성능 수치가 아니라 단계 사이 데이터가 바뀌거나 잘못 연결됐는지 감지하는 회귀
식별자다. `verify_uib_integration_trace.py`는 생산 단계의 출력 해시와 소비 단계의 입력 해시를
비교한다. Residual ADD는 project 결과와 원래 입력을 함께 받으므로 두 해시를 `+`로 기록한다.

## 3. 재현 명령

WSL에서 저장소 루트로 이동한 뒤 다음 한 줄을 실행한다.

```bash
bash experiment/run_uib_integration_trace.sh
```

스크립트는 `system_hbm_64ch.ini`를 임시 백업하고 다음 핵심 조건을 설정한다.

```ini
ENABLE_BANK_SIDE_PIM=true
ENABLE_LOGIC_DIE_PIM=true
PIM_TARGET=hybrid
HIERARCHY_SOURCE_QUEUES=true
LOGIC_DEPTHWISE_ACCUMULATION=true
BANK_LOCAL_AGGREGATION_TAPS=9
LOGIC_ACCUMULATOR_PIPELINES=2
LOGIC_UIB_TRACE_FILE=experiment/results/uib_integration_trace.csv
```

정상 종료와 오류 종료 모두 `trap`으로 원래 설정 파일을 복원한다.

## 4. 출력 예시와 해석

```text
[       OK ] MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd (342541 ms)
[  PASSED  ] 1 test.
UIB_INTEGRATION_TRACE PASS stages[5] outputs[18816]
total_stage_span_cycles[230856] final_fp16_hash[4068a98fc1531583]
```

- GoogleTest PASS는 CPU 기준값과 최종 FP16 출력 18,816개가 모두 일치했다는 뜻이다.
- `stages[5]`는 UIB의 다섯 단계가 빠짐없이 정해진 순서로 기록됐다는 뜻이다.
- `outputs[18816]`은 `14x14x96` 최종 tensor 크기다.
- `230856`은 첫 expand 시작부터 ReLU/readback 종료까지의 공통 시뮬레이터 cycle 범위다.
- 최종 해시는 출력값 전체의 bit열 식별자이며 다른 코드·설정에서 값이 바뀌면 달라진다.

## 5. 실제 trace 결과

| 단계 | 배치 | 입력 -> 출력 원소 | Cycle |
|---|---|---:|---:|
| Expand pointwise | Logic die | 18,816 -> 37,632 | 88,033 |
| Depthwise 3x3 | Bank-local + logic accumulation | 37,632 -> 37,632 | 34,819 |
| Project pointwise | Logic die | 37,632 -> 18,816 | 103,620 |
| Residual ADD | Bank side | 37,632 -> 18,816 | 3,669 |
| ReLU/readback | Bank side | 18,816 -> 18,816 | 715 |

단계 cycle의 합은 230,856이다. 검증기는 다음 연결을 모두 통과했다.

1. Expand 출력 해시 = Depthwise 입력 해시
2. Depthwise 출력 해시 = Project 입력 해시
3. Project 출력 해시 = Residual ADD의 첫 입력 해시
4. Residual 출력 해시 = ReLU 입력 해시 = 최종 출력 해시

## 6. 이번 결과가 증명하는 것과 증명하지 않는 것

이번 결과는 C++ cycle-level 시뮬레이터에서 bank-side와 logic-die 경로가 하나의 UIB를
정확한 데이터 연쇄로 수행하고, 단계별 cycle과 데이터 경계를 재현 가능하게 저장한다는 것을
증명한다. 기존 depthwise-only RTL trace와 전체 UIB 사이의 인터페이스 계약도 확보했다.

그러나 이 CSV는 아직 모든 MAC·MUL 요청을 cycle마다 기록한 RTL 입력 trace가 아니다.
Pointwise와 depthwise를 함께 넣은 완성 RTL top-level의 end-to-end PASS도 아직 아니다.
따라서 다음 단계는 이 계약 아래에 pointwise request/payload 이벤트를 추가하고, 64채널
shared scheduler RTL에서 `expand -> depthwise -> project`를 연속 재생하는 것이다.

## 7. 생성 파일

- `experiment/results/uib_integration_trace.csv`: 단계별 통합 trace
- `experiment/results/uib_integration_trace.csv.requests.csv`: 실제 logic-PCU reservation 요청 trace
- `experiment/results/uib_integration_trace.log`: 전체 시뮬레이터 출력
- `experiment/verify_uib_integration_trace.py`: 순서·원소 수·해시 연결 검사기
- `experiment/analyze_uib_pointwise_requests.py`: pointwise queue와 coalescing 요약
- `experiment/run_uib_integration_trace.sh`: 설정, 실행, 복원, 검증 자동화
