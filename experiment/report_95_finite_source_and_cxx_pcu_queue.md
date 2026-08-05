# 95차 실험 보고서: Finite source FIFO와 C++ PCU queue backpressure

## 1. 목적

94차에서는 logic die 중앙 ready queue를 64 entries로 제한했지만 source FIFO는 무제한이었다.
이번 실험은 다음 두 단계를 수행한다.

1. 실제 UIB 요청 trace에서 source FIFO를 `8·16·32 entries/stream`으로 제한한다.
2. C++ `LogicDieScheduler::canAccept()`에 `LOGIC_PCU_QUEUE_DEPTH`를 연결해 실제 command issue를
   보류할 수 있게 한다.

## 2. Finite source replay 원리

실제 trace에서 stream 하나는 cycle당 최대 1개 요청을 발행하고 연속 요청의 최소 간격은
4 cycle이었다. FIFO가 가득 차면 head 요청과 같은 stream의 이후 요청을 동일한 stall만큼
뒤로 이동시켜 원래 순서와 간격을 유지했다.

```text
upstream command stream
  -> finite source FIFO (8/16/32 entries)
  -> round-robin admission
  -> central ready queue (64 entries)
  -> pointwise PCU (16/32/64 units)
```

## 3. Replay 결과

9개 조합 모두 요청 92,512건을 손실·starvation·교착 없이 완료했다.

### Project 마지막 완료 cycle

| PCU | Source 8 | Source 16 | Source 32 |
|---:|---:|---:|---:|
| 16 | 298,891 | 297,867 | 295,819 |
| 32 | 207,832 | 207,386 | 206,219 |
| 64 | 162,634 | 162,702 | 161,957 |

### 물리 source 저장량

| Source depth | 전체 peak | Stream당 hard maximum |
|---:|---:|---:|
| 8 | 504 | 8 |
| 16 | 1,008 | 16 |
| 32 | 2,016 | 32 |

`32 PCU + source depth 8 + central depth 64`는 source 32 대비 저장량을 75% 줄이면서 Project
완료가 1,613 cycle, 0.78%만 느렸다. 따라서 현재 trace의 1차 bounded 후보는 다음과 같다.

```text
LOGIC_PCU_COUNT        = 32
LOGIC_READY_QUEUE_DEPTH = 64
LOGIC_SOURCE_DEPTH      = 8 / stream
```

이는 합성 전 후보이며 확정 사양은 아니다.

## 4. C++ 설정과 동작

다음 설정을 추가했다.

```ini
LOGIC_PCU_QUEUE_DEPTH=0
```

- `0`: 기존 무제한 scheduler와 호환
- `1 이상`: 아직 service를 시작하지 못한 pointwise reservation 수 제한
- 실행을 시작한 요청은 queue entry를 반환한다.
- queue가 찼으면 `PIMRank -> Rank -> MemoryController/CommandQueue`의 기존 ready 경로가 명령을
  보류한다.

## 5. 구현 중 발견한 동시 승인 문제

### 5.1 Soft cap

처음에는 `canAccept()`가 현재 waiting 수만 검사했다. 전체 UIB는 정확도 PASS하고 32 PCU에서
145,232 cycle을 기록했지만 trace interval의 waiting peak가 Expand 126, Project 127이었다.
설정한 64를 초과했으므로 이 결과는 성능 참고값일 뿐 hard-cap 검증으로 인정하지 않는다.

원인은 64개의 독립 memory controller가 같은 cycle에 queue 상태를 보고 각자 명령을 승인하는
분산 승인 경쟁이다. Queue가 비어 있을 때 최대 한 channel wave가 동시에 들어올 수 있다.

### 5.2 선점 credit 방식 폐기

`canAccept(recordStall=true)`에서 credit을 미리 선점하는 방식도 시험했다. 그러나 command queue가
후보를 검사한 뒤 실제 pop하지 않을 수 있어 credit이 누수됐다. Miniature UIB는 cycle 2,000,083
에서도 같은 MAC 앞에서 진행하지 못했다. 이 구현은 제거했다.

### 5.3 현재 low-watermark 방식

현재 코드는 동시에 들어올 수 있는 channel wave만큼 headroom을 남긴다.

```text
low_watermark = max(1, queue_depth - NUM_CHANS + 1)
```

64채널에서 depth 64이면 waiting queue가 비어 있을 때만 다음 wave를 허용한다. 보수적이지만
선점 credit 없이 최대 64개를 넘지 않으며 후보 검사 누수로 교착하지 않는다.

## 6. 검증 결과

### Scheduler 단위 테스트

```text
[ PASSED ] LogicDieSchedulerTest.FinitePcuQueueReleasesEntriesAtServiceStart
[ PASSED ] LogicDieSchedulerTest.FinitePcuQueueLeavesDistributedAdmissionHeadroom
```

첫 테스트는 service 시작 시 entry 반환을, 두 번째 테스트는 64-channel admission headroom을
검증한다.

### 실제 command path smoke test

```text
[       OK ] MobileNetV4WorkloadTest.MiniatureUibRunsEndToEnd
[  PASSED  ] 1 test.
total_cycle[55472]
```

실행 조건은 `32 PCU + queue depth 64 + HIERARCHY_SOURCE_QUEUES=true`다. Bank/logic 계층을
통과한 miniature UIB의 최종값이 모두 일치했고 교착 없이 완료됐다.

재현 명령:

```bash
bash experiment/run_hard_pcu_queue_smoke.sh
```

## 7. Full-shape 검증 상태

Low-watermark hard-cap의 14x14x96 full UIB는 C++ polling 비용이 매우 커 현재 실행을 완료하지
못했다. 약 40분 동안 CPU 99.9%로 계산했으며 정지 메시지는 없었지만, 실험 효율이 낮아 중단하고
설정을 복원했다. 따라서 soft-cap의 145,232 cycle을 hard-cap 최종 성능으로 인용하면 안 된다.

현재 확보된 근거는 다음과 같이 구분한다.

| 항목 | 상태 |
|---|---|
| Finite source trace replay | 9개 조합 PASS |
| Queue release/headroom 단위 테스트 | PASS |
| Low-watermark miniature UIB 정확도·진행성 | PASS |
| Low-watermark full UIB end-to-end cycle | 미완료 |

## 8. 다음 구현

64 controller가 매 cycle 같은 queue를 polling하는 구조를 중앙 grant vector로 바꿔야 한다.

1. 각 channel은 logic request valid와 stream/ordinal만 제출한다.
2. Global scheduler가 한 cycle에 허용할 channel mask를 한 번 계산한다.
3. Grant된 channel만 command를 pop한다.
4. Ready queue credit은 실제 grant 수만큼만 차감한다.
5. Full UIB에서 waiting peak ≤64, 출력 18,816개, end-to-end cycle을 다시 검증한다.

RTL에서도 같은 `request_valid[63:0]`, `grant[63:0]`, `queue_credits` 인터페이스를 사용해야 한다.

## 9. 파일

- `experiment/replay_uib_finite_source_backpressure.py`
- `experiment/results/uib_finite_source_backpressure.csv`
- `experiment/run_hard_pcu_queue_smoke.sh`
- `experiment/results/hard_pcu_queue_smoke.log`
