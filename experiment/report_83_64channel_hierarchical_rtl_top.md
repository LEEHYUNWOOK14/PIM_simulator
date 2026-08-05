# 83차 RTL 보고서: 64채널 계층형 reduction top

## 1. 수정이 필요했던 이유

초기 `hierarchical_reduction_path.sv`는 rank 하나의 8개 PIM block만 표현했다. 그러나 C++ 설정은 `NUM_CHANS=64`, rank/channel=1, `NUM_PIM_BLOCKS=8`이고 모든 channel이 하나의 `LogicDieAccumulator`를 공유한다.

## 2. 구현 구조

`rtl/logic_die_64ch_reduction_top.sv`를 추가했다.

```text
Channel 0:  8 local buffers → 8→1 arbiter ┐
Channel 1:  8 local buffers → 8→1 arbiter │
...                                       ├→ 64→2 global arbiter → 64 B/cycle
Channel 63: 8 local buffers → 8→1 arbiter ┘
```

- Channel 내부에서 8개 PIM-block final 중 하나를 round-robin 선택한다.
- Base logic die에서 64개 channel stream 중 두 개를 선택한다.
- Local/global arbiter 모두 stall 시 grant와 payload를 고정한다.

## 3. 자원 해석

```text
8 banks × 16 entries/bank × 32 B = 4 KiB/rank
64 channels × 4 KiB = 256 KiB/HBM stack
```

여기에 valid, key, slot metadata, arbiter, FP16 adder와 interconnect가 추가된다. 이전의 4 KiB는 stack 전체가 아니라 rank당 값이다.

## 4. 검증

CHANNELS=4 축소 testbench에서 세 channel이 동시에 final을 발생시켰다. Global dual link가 channel 0과 1을 먼저 보내고 다음 cycle에 channel 2를 보내는지 검사했다.

```text
LOGIC_DIE_64CH_REDUCTION_TOP_TB PASS
```

Testbench override 없이 production 기본값도 elaboration했다.

```text
CHANNELS=64
PIM_BLOCKS=8
ENTRIES_PER_BANK=16
DATA_WIDTH=256
LOGIC_DIE_64CH_REDUCTION_TOP ELABORATION PASS
```

## 5. C++ 대응 개선

| 항목 | 이전 RTL slice | 새 top |
|---|---:|---:|
| 표현 channel | 1 | 64 |
| 표현 PIM blocks | 8 | 512 |
| Local arbitration | 없음 | channel별 8→1 |
| Global arbitration | 8→2 | 64→2 |
| Data array 해석 | 4 KiB | 256 KiB/stack |

## 6. 남은 차이

1. C++은 bytes를 고정 64 B/cycle로 나누지만 RTL 평균폭은 valid 분포에 따라 달라진다.
2. RTL slot allocator와 FP16 pipeline은 아직 외부다.
3. 64채널 top은 elaboration을 통과했지만 64채널 전체 random simulation은 미수행이다.
4. 256 KiB array와 계층 arbiter의 합성 면적·전력은 미측정이다.

## 7. 다음 단계

1. C++에서 channel/PIM-block별 partial arrival cycle trace를 기록한다.
2. Trace를 64채널 RTL top에 재생해 sustained bandwidth를 측정한다.
3. Slot allocator와 FP16 pipeline을 추가한다.
4. 합성 결과로 C++ latency와 bandwidth를 재보정한다.
