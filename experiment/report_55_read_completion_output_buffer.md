# 55차 실험 보고서: READ 완료 기반 로직 다이 출력 버퍼

## 1. 목적

기존 구현은 `runPIM()`이 끝난 뒤 계산 결과를 출력 버퍼에 복사했다. 따라서 버퍼의 상태는
검사할 수 있었지만, 실제 메모리 READ 반환 시점과 버퍼 포화가 시뮬레이션 진행에 영향을 주지
않았다. 이번 실험은 각 READ 완료 버스트가 로직 다이 출력 버퍼를 직접 채우도록 연결한다.

## 2. 구현 내용

1. 출력 READ 트랜잭션에 `layer`, `position`, `channel tile`, `burst index`, `expected bursts`를 기록했다.
2. 각 채널의 `MemoryController`가 READ 데이터를 반환할 때 공유 출력 버퍼에 해당 버스트를 쓴다.
3. 첫 버스트가 도착할 때 타일을 지연 예약한다.
4. 용량 2가 모두 차 있으면 반환 패킷을 삭제하지 않고 해당 채널에서 대기시킨다.
5. 선두 타일의 모든 버스트가 도착하면 downstream 결과 저장영역에 순서대로 커밋하고 버퍼 entry를 해제한다.
6. `readPointwiseSpatial()`은 사후 복사를 하지 않고 커밋된 결과만 읽는다.

## 3. 재현 명령

WSL의 프로젝트 루트에서 다음 명령을 실행한다.

```bash
scons -j4
./sim --gtest_filter=LogicDieOutputBufferTest.*
./sim --gtest_filter=MobileNetV4WorkloadTest.MiniatureUibRunsEndToEnd
./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd
```

실행 시간을 제한하려면 마지막 명령을 다음처럼 실행한다.

```bash
timeout 300 ./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd
```

## 4. 출력 예시와 해석

```text
MOBILENETV4_ACTUAL_UIB_RESULT
outputs_checked[18816]
logic_output_buffer_reservations[392]
logic_output_buffer_retirements[392]
logic_output_buffer_full_stalls[751369]
logic_output_buffer_peak_entries[2]
total_cycle[214842]
[  PASSED  ] 1 test.
```

| 출력 | 해석 |
|---|---|
| `outputs_checked[18816]` | `14 x 14 x 96` 출력 18,816개가 기준값과 일치했다. |
| `reservations[392]` | Expand 196개와 Project 196개, 총 392개 위치 타일이 실제 READ 도착 시 예약되었다. |
| `retirements[392]` | 예약된 모든 타일이 완성되어 downstream 저장영역으로 커밋되었다. |
| `full_stalls[751369]` | 버퍼가 찬 동안 각 채널이 READ 반환을 재시도한 누적 횟수다. 타일 거절 수가 아니라 채널별 대기 강도다. |
| `peak_entries[2]` | 설정한 2-entry 용량을 넘지 않았다. |
| `total_cycle[214842]` | 이번 모델에서 측정된 전체 완료 cycle이다. |
| `PASSED` | 출력 정확도와 구조적 검증 조건을 모두 만족했다. |

## 5. 결과

| 시험 | 결과 |
|---|---:|
| 출력 버퍼 단위 테스트 | 4 PASS |
| 소형 UIB | PASS, 38,664 cycles |
| 실제 크기 UIB | PASS, 214,842 cycles |
| 실제 크기 출력 비교 | 18,816 PASS |
| 예약 / 퇴출 | 392 / 392 |
| 최대 entry | 2 |
| READ 반환 재시도 | 751,369 |

## 6. 결론과 주의사항

실제 READ 완료가 출력 타일 생산 이벤트가 되었고, 2-entry 포화가 메모리 컨트롤러의 반환
경로에 backpressure를 발생시키는 단계까지 구현했다. 이는 사후 상태 검사에서 cycle-level 실행
모델로 넘어간 것이다.

이전 사후 복사 모델의 247,342 cycles와 이번 214,842 cycles의 차이는 32,500 cycles
(`13.14%`)이다. 그러나 현재는 두 경로를 같은 실행 조건에서 선택하는 A/B 설정이 없고,
downstream 커밋 latency도 0이므로 이 차이를 성능 향상으로 주장하면 안 된다. 현재 값은 새
구현의 회귀 기준값으로만 사용한다.

다음 구현은 다음 두 항목이다.

1. 출력 버퍼 모델을 설정으로 켜고 끌 수 있게 하여 동일 바이너리 A/B 비교를 만든다.
2. downstream drain latency와 bandwidth를 설정값으로 추가하고, 포화 대기를 wall-cycle과
   channel-cycle로 분리해 기록한다.

