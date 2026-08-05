# 86차 실험 보고서: MobileNetV4 C++ partial을 512-source FP16 RTL에서 재생

## 1. 목표

84차 실험은 C++에서 발생한 burst의 시각과 source를 64채널 RTL link에서
재생했다. 85차 실험은 FP16 가산기 자체를 C++ `half.h`와 비교했다. 이번 실험은
두 검증 사이의 빈칸을 메우기 위해 **실제 MobileNetV4 depthwise partial 값**을
C++에서 기록하고 동일 값을 RTL reduction buffer가 누산하도록 했다.

## 2. 계층형 연산 조건

| 항목 | 값 | 의미 |
|---|---:|---|
| 입력 shape | `14×14×192` | MobileNetV4 실제 depthwise shape |
| kernel | `3×3` | 출력 하나당 tap 9개 |
| bank-local aggregation | 3 tap | bank에서 3개씩 묶어 logic 방향으로 전달 |
| logic partial 수 | 24,576 burst | final 8,192 burst × partial 3개 |
| RTL source | 512개 | 64 channel × channel당 8 PIM block |
| burst | 256 bit | FP16 16 lane, 32 B |
| accumulator entry | source당 16개 | 실제 trace의 동시 key 수 |

Bank PIM은 9개 tap을 세 묶음으로 줄이고, logic-die reduction은 같은 key의 세
partial을 다시 합쳐 최종 9-tap 결과를 만든다. 따라서 이번 설정은 bank에서 전부
합치는 경우와 logic die에서 전부 합치는 경우의 중간인 계층형 분담 사례다.

## 3. C++ trace 확장

기존 `depthwise_actual_payload_trace.csv`는 도착 시간과 channel, PIM block, key를
유지한다. 새 sidecar 파일은 다음 필드를 추가한다.

```text
sequence,cycle,channel,rank,pim_block,key,tap_index,tap_count,partial_hex,final_hex
```

`partial_hex`는 bank-local 3-tap 결과 16개를 담은 256-bit 값이고 `final_hex`는
C++ logic accumulator가 세 partial을 합친 기대값이다. lane 0이 packed vector의
하위 16 bit가 되도록 출력 순서를 명시적으로 맞췄다.

생성 파일:

```text
experiment/results/depthwise_actual_payload_trace.csv
experiment/results/depthwise_actual_payload_trace.csv.payload.csv
```

각 파일은 header를 제외하고 24,576행이다.

## 4. 재현 명령

전체 C++ trace 생성과 RTL 회귀를 다시 수행한다.

```bash
bash experiment/run_fp16_payload_replay.sh all
```

C++만 실행하려면 `cpp`, 이미 생성된 trace로 RTL만 실행하려면 `rtl`을 사용한다.

```bash
bash experiment/run_fp16_payload_replay.sh cpp
bash experiment/run_fp16_payload_replay.sh rtl
```

스크립트는 `system_hbm_64ch.ini`를 임시로 복사한 뒤 실험값을 넣는다. 정상 종료나
오류 종료 모두 `trap`으로 원본 설정을 복원한다. C++ 실제 shape 실행은 이 환경에서
약 211초, 전체 RTL 회귀는 약 137초가 걸렸다.

## 5. 실제 C++ 결과

```text
DEPTHWISE_HIERARCHICAL_ACTUAL_SHAPE_RESULT
 outputs_checked[37632]
 aggregation_taps[3]
 bank_local_peak_entries[128]
 bank_local_peak_entries_per_bank[16]
 bank_local_stalls[25344]
 mismatches[0]
 partial_bursts[24576]
 final_bursts[8192]
 link_replay_cycles[13878]
 link_replay_full_cycles[12288]
 link_replay_idle_cycles[1590]
 total_cycle[40538]
```

`mismatches[0]`은 논리 출력 37,632개가 CPU 기준값과 모두 같다는 뜻이다.
`partial_bursts[24576] / final_bursts[8192] = 3`이므로 logic die가 final 하나마다
정확히 세 partial을 받았다. `bank_local_peak_entries_per_bank[16]`은 RTL의 source당
16-entry 선택과도 일치한다.

## 6. 실제 RTL 결과

```text
LOGIC_DIE_512SOURCE_FP16_PAYLOAD_TB PASS partials[24576] finals[8192] lanes[16] reference[C++ MobileNetV4]
LOGIC_DIE_64CH_TRACE_REPLAY_TB PASS bursts[8192] full_cycles[4096] bytes_per_active_cycle[64]
```

첫 줄은 512개 source의 24,576개 실제 partial을 RTL FP16 가산기가 처리해 final
8,192개를 만들었으며, 모든 final key와 16개 lane이 C++ 값과 bit 단위로 같다는
뜻이다. 비교한 FP16 결과 수는 `8,192×16=131,072`개다.

두 번째 줄은 aggregation 9로 생성한 기존 final-arrival trace가 64채널 2단계
arbiter에서 64 B/cycle로 재생되는 링크 검증이다. 현재 testbench는 수치 검증과
cycle-accurate link 검증을 분리해 실패 원인을 구분한다.

## 7. 결론과 제한

이번 결과로 다음 연쇄가 실제 값 기준으로 연결됐다.

```text
MobileNetV4 3×3 tap
→ bank-local 3-tap partial
→ C++ logic accumulator
→ 512-source RTL FP16 accumulator
→ C++ final과 bit 단위 일치
```

따라서 logic-die 누산기는 더 이상 count와 timing만 있는 빈 제어 모델이 아니다.
실제 MobileNetV4에서 발생한 FP16 payload를 처리하는 RTL datapath가 생겼다.

이 보고서 작성 당시 payload test와 final link arbitration은 별도 test가 검증했다.
이후 87차 실험에서 `USE_INTERNAL_FP16` 경로를 64채널 top에 추가하고 실제
aggregation 3 arrival timing, representative FP16 lane, 2단계 arbiter를 하나의
timed test로 연결했다. 16-lane 전체 값 검증은 이 보고서의 512-source test를 함께
유지한다. 합성 전이므로 latency 1과 면적·주파수는 여전히 가정이다.
