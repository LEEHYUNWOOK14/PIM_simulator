# AI 기술 구현 목표

## 1. 목표

기존 64-channel HBM2-PIM 시뮬레이터에 bank-side PCU와 logic-die PCU가 함께 동작하는 계층형 연산 경로를 구현하고, MobileNetV4 UIB를 기준으로 정확도, cycle, memory transaction, 계층 간 전송량을 재현 가능하게 검증한다.

이 문서는 연구자가 결정해야 하는 최종 아키텍처의 독창성을 대신하지 않는다. 여기서는 결정된 가설을 코드로 구현하고 실험 가능한 형태로 만드는 기술 작업만 관리한다.

## 2. 현재 기준선

| 항목 | 현재 상태 | 확인 결과 |
|---|---|---|
| Bank-side PIM | 구현 및 기준선 확보 | MobileNetV4 실제 UIB 정확도 통과 |
| Logic-die PIM | MAC/MAD 라우팅 및 지연 모델 구현 | bank/logic 기능 경로 동작 |
| 계층 전송 모델 | `HIERARCHY_PIM_BW` 구현 | byte와 cycle 집계 가능 |
| Compact output mapping | 필요한 channel만 활성화 | UIB read 90.73%, write 74.14% 감소 |
| Spatial-group mapping | 구현 및 실제 UIB 검증 | expand 21 groups, project 32 groups; 최종 정확도 통과 |

## 3. AI가 수행할 구현 범위

1. pointwise GEMV에 연속 channel 범위 또는 명시적 channel 목록을 지정할 수 있게 한다.
2. MobileNetV4 공간 위치를 channel group에 배정하는 wave scheduler를 구현한다.
3. group마다 입력, weight, 결과 주소가 충돌하지 않도록 주소 배치를 확장한다.
4. expand(192 output)는 group당 3 channels, project(96 output)는 group당 2 channels를 사용하는 경로를 검증한다.
5. 출력 정확도와 cycle/read/write/transfer 통계를 자동 수집한다.
6. bank-only, fixed hybrid, compact hybrid, spatial-group hybrid를 같은 조건에서 비교한다.
7. 모든 실험 명령과 예상 출력 해석을 보고서에 남긴다.

## 4. 구현 순서와 통과 조건

| 단계 | 구현 내용 | 통과 조건 |
|---|---|---|
| T1 | channel subset API | 기존 prefix mapping 회귀 테스트 통과 |
| T2 | 두 spatial position을 서로 다른 group에 배치 | 두 결과 모두 CPU 기준값과 일치 |
| T3 | 한 wave에 가능한 최대 group 배치 | batch wave 수가 계산값과 일치 |
| T4 | 실제 UIB expand/project 연결 | 18,816개 최종 출력 모두 일치 |
| T5 | 성능·트래픽 ablation | 네 가지 architecture mode의 CSV 생성 |
| T6 | 재현 문서화 | 한 명령으로 실험 재실행 가능 |

## 5. 연구자가 결정해야 하는 입력

다음 항목은 코드가 자동으로 정답을 만들 수 없는 연구 가설이다. 구현 중에는 설정값으로 분리하고 특정 값을 정답처럼 고정하지 않는다.

- logic-die PCU의 실제 개수, 데이터 폭, 주파수와 면적 예산
- bank-side와 logic-die 사이의 물리 bandwidth 및 arbitration 정책
- 어떤 연산과 tensor를 어느 PCU에 배치할지에 대한 일반화 정책
- MobileNetV4 외 모델에서도 유효하다고 주장할 평가 workload와 평가 지표
- partial sum 이동, multicast, reduction network를 실제 RTL에서 구현할 방식

## 6. 현재 작업점

채널 시작 오프셋과 spatial wave scheduling을 구현했다. 실제 UIB는 18,816개 출력을 모두 통과했고 bank 기준 346,600 cycle에서 52,277 cycle로 감소했다.

전역 공유 scheduler와 PCU 병렬 lane을 구현했다. 실제 UIB에서 global PCU 8개는 400,340 cycle로 bank보다 느리고, 16개는 215,687 cycle로 bank 기준을 넘어섰다. 32개와 64개는 각각 123,376, 76,842 cycle이다. Logic bandwidth sweep 결과 PCU 16개에서는 64 B/cycle부터 pointwise crossover가 발생하고 128 B/cycle부터 compute-bound가 된다.

Command dispatch coalescing과 공유 가중치 버퍼의 실제 fill/read 경로도 구현했다. 64 KiB에서 실제 MobileNetV4 UIB의 logic weight traffic은 3,129,344 B에서 114,688 B로 96.34% 감소하고, 실제 write는 319,668건에서 225,460건으로 29.47% 감소한다. 702,464회 중앙 버퍼 read가 모두 hit하고 최종 정확도도 통과했다. 다만 fill이 2~3개 channel에 집중되어 cycle은 219,854에서 231,084로 5.11% 증가했다. 다음 작업은 중앙 버퍼 fill을 여러 HBM channel에 stripe하는 경로와 병렬도 sweep이다.

공유 버퍼 fill source를 여러 HBM channel에 round-robin stripe하는 경로와 sweep도 구현했다. 64채널 fill에서 트래픽 절감을 유지하면서 cycle은 219,405로 no-buffer hybrid 219,854보다 0.20% 개선됐다. 4~60채널은 bank/row 요청 배열과 compute 경합 때문에 비단조적이며 기준을 통과하지 못했다. 다음 작업은 bank-aware fill mapping과 channel별 완료 cycle 계측으로 channel 수 효과와 bank conflict 효과를 분리하는 것이다.

Bank별 channel 부하를 균등화하는 `bank_aware` 정책도 추가했지만 16/32/64채널 결과가 round-robin과 완전히 같았다. 현재 preload가 이미 bank를 고르게 순회하므로 단순 bank-count 균등화는 병목을 해결하지 못한다. 다음 작업은 channel별 fill 완료 cycle과 row activation/precharge를 별도 집계해 비단조성의 실제 원인을 찾는 것이다.

Fill transaction tag를 WRITE 완료와 자동 PRE까지 전달해 channel별 완료 cycle과 ACT/PRE를 계측했다. 16/32/64채널은 channel별 write가 각각 224/112/56으로 완전히 균등했지만 PRE가 384/768/0이었다. 64채널 crossover는 부하 균형보다 channel별 가중치 조각이 한 row 범위에 머물러 PRE가 제거된 효과다. 다음 작업은 32채널 row-local mapping으로 PRE를 제거할 수 있는지 검증하는 것이다.

32채널 source weight를 전용 row에 bank-interleaved로 배치하는 `row_interleaved` 정책을 구현했다. PRE는 768에서 0으로 줄고 cycle은 224,150에서 219,729로 감소해 no-buffer hybrid 219,854를 125 cycle 앞섰다. 20/24/28/30/31채널은 모두 실패해 현재 측정 범위의 최초 crossover는 32채널이다. 다만 성능 여유가 0.057%뿐이므로 다음 작업은 중앙 buffer write port 수와 arbitration latency를 명시적으로 모델링하는 것이다.

Fill-ready barrier를 추가하면서 21차의 즉시-visible 모델이 약 10,000 cycle의 잘못된 fill/compute overlap을 허용했음을 수정했다. 무제한 port의 정정 cycle은 229,856이다. 중앙 buffer write-port scheduler를 구현한 결과 4 ports, latency 1/2/4에서 각각 215,969/217,189/218,957 cycle로 no-buffer 219,854를 통과하고 latency 8은 226,757로 실패했다. 4-port wait가 32 channel command release를 정렬해 dispatch를 9,430에서 약 2,300으로 줄이는 synchronization 효과가 핵심이다. 다음 작업은 명시적인 post-fill synchronized release/guard 모델이다.

명시적인 post-fill guard를 구현하고 무제한 write-port 조건에서 0~666 cycle/layer를 sweep했다. 128 cycle/layer에서 dispatch가 9,430에서 2,314로 줄고 총 cycle은 215,865로 개선되어 4-port latency 1 결과 215,969를 재현했다. 따라서 핵심은 port 수 자체보다 buffer-ready 이후 channel command를 같은 release epoch에 정렬하는 제어다. 다음 작업은 guard를 고정 상수가 아닌 epoch/barrier 기반 release 규칙으로 바꾸고 4-port 조건과 결합했을 때 중복 대기가 없는지 검증하는 것이다.

고정 guard를 대체하는 epoch/ordinal/ready-mask release 모델을 구현했다. 두 pointwise epoch의 예상 channel mask가 모두 완성됐고 불완전 mask는 0개였다. 무제한 port에서 214,228 cycle, 4-port 결합에서 214,903 cycle로 각각 no-buffer 기준을 통과했다. 4-port 결합의 차이는 port wait 666 cycle과 거의 일치해 epoch release와 port arbitration의 역할도 분리됐다. 다음 작업은 command ordinal을 명시적 packet field로 옮기고 stream별 명령 수 불균형에서 channel mask가 축소되는 규칙을 검증하는 것이다.

`LogicCommandContext`를 추가해 `PIMRank`가 해독한 logic 명령마다 epoch ID, command ordinal, stream ID를 명시적으로 생성하고 scheduler로 전달하도록 변경했다. 불균형 stream 단위 테스트에서 fanout 3과 1의 동적 mask를 검증했고, 실제 UIB에서는 1,616개 mask의 총 fanout이 92,512로 전체 logic request와 정확히 일치했다. fanout 범위는 8~64이며 최종 정확도와 214,228 cycle 결과가 유지됐다. 다음 작업은 layer/epoch별 fanout 분포와 command queue depth를 계측해 RTL broadcast queue 용량을 결정할 근거를 만든다.

Epoch별 broadcast mask assembly residency를 계측했다. Expand는 720 masks/42,336 fanout, 최대 residency 0 cycle, peak open mask 1이었다. Project는 896 masks/50,176 fanout, 최대 residency 728 cycles, 총 residency 181,176 cycles, peak open mask 78이었다. 현재 schedule의 queue depth 관측 하한은 78이므로 RTL 1차 후보를 128 entries로 기록했다. 다음 작업은 `LOGIC_BROADCAST_QUEUE_DEPTH`를 simulator 설정으로 추가하고 64/78/128 entry에서 overflow 또는 backpressure를 모델링하는 것이다.

`LOGIC_BROADCAST_QUEUE_DEPTH`와 trace-derived finite queue backpressure를 구현했다. Depth 32는 11회 full/1,561 stall cycles로 total 215,417, depth 64는 1회 full/53 stall cycles로 214,289였다. Depth 78/96/128은 full과 stall이 모두 0이며 214,228 cycle을 유지했다. Stall 직전 cycle은 모든 조건에서 211,108로 같고 실제 적용 loop도 추정 stall과 일치했다. Total 증가량이 stall과 정확히 같지 않은 것은 이후 bank-side 연산의 DRAM timing phase가 이동한 결과다. 다음 작업은 사후 trace 모델을 online expected-mask/EOS 기반 queue로 바꿔 command issue 단계에서 직접 backpressure를 전달하는 것이다.

Spatial scheduler가 group별 position 수와 CRF 반복 구조로 stream별 EOS ordinal을 실행 전에 계산하고 scheduler에 등록하도록 구현했다. Expand는 position당 72 commands, project는 128 commands로 실제 fanout과 일치했다. Online expected-mask completion의 peak open mask는 1/78로 사후 trace 분석과 같고 두 epoch 모두 incomplete expected mask가 0이었다. Depth 64는 online full 상태에 1회 진입하고 depth 128은 0회였다. 다음 작업은 online queue full 상태를 `PIMRank`/MemoryController의 ready 신호로 연결해 현재 trace-derived stall 적용을 완전히 대체하는 것이다.

Expected completion 조건을 fanout 크기에서 실제 stream-ID 집합 일치로 강화했다. 이 과정에서 PIMKernel이 활성 rank 수를 stream-ID stride로 쓰고 PIMRank는 물리 `NUM_RANKS`를 쓰는 불일치를 발견해 둘 다 `channel * NUM_RANKS + rank`로 통일했다. 잘못된 stream이 같은 fanout을 채워도 완료되지 않는 단위 테스트를 추가했고, 실제 UIB exact-mask 검증에서도 epoch 1/2 incomplete mask가 모두 0, online peak가 1/78로 유지됐다.

`LOGIC_ONLINE_QUEUE_BACKPRESSURE`를 추가하고 scheduler `canAccept`를 PIMRank의 side-effect-free command peek, Rank ready, MemoryController의 CommandQueue pop predicate까지 연결했다. Queue full에서는 기존 mask completion command는 허용하고 새 mask만 보류한다. 실제 UIB에서 depth 32/64/128의 project peak는 각각 정확히 32/64/78로 제한됐고 blocked channel-cycles는 7,513/211/0이었다. 모든 조건에서 incomplete mask 0, 정확도 통과, total 214,228 cycle을 유지했다. Trace-derived stall은 online 모드에서 0으로 비활성화됐다. 다음 작업은 blocked channel-cycle이 wall-clock에 숨겨지는 원인을 channel별 issue/utilization 통계로 분리하는 것이다.

채널별 blocked/issued 통계와 blocked wall-cycle, logic PCU busy 중첩을 추가했다. Depth 32는 291 wall-cycle 동안 7,513 channel-cycle이 막혀 평균 25.82 streams가 동시에 정지했고, depth 64는 53 wall-cycle 동안 211 channel-cycle이 막혀 평균 3.98 streams가 정지했다. 두 조건 모두 blocked channel-cycle의 100%가 PCU busy 구간과 겹쳐 total 214,228 cycle에 영향을 주지 않았다. Depth 128은 정지가 없었다. RTL queue는 128 entries를 안전 후보, 64 entries를 면적 절감 후보로 유지하며, 다음 작업은 여러 MobileNetV4 pointwise shape에 대한 queue-depth 일반화 검증이다.

MobileNetV4 CSV의 세 가지 고유 pointwise 형상을 환경변수로 선택하는 정확도 테스트와 depth 32/64/128 자동 sweep을 추가했다. Expand `28×28, 64→192`와 `14×14, 96→192`는 peak open mask 1, project `14×14, 192→96`은 독립 실행 peak 64였다. 독립 project는 depth 64에서 역압력이 없지만 실제 UIB 연결 실행은 peak 78과 53 blocked wall-cycle을 보였다. Queue 용량은 개별 shape가 아니라 연산 체인의 epoch/PCU 위상까지 포함해 정해야 한다는 근거를 확보했다. 다음 작업은 PCU count와 logic bandwidth를 queue depth와 교차 sweep해 128-entry 여유의 microarchitecture 민감도를 검증하는 것이다.

PCU 8/16/32 × logic bandwidth 32/64/128 × queue depth 64/128의 18개 실제 UIB 교차 실행을 완료했다. 모든 실행이 정확도와 exact expected-mask completion을 통과했고 depth 128의 최대 peak는 78이었다. Depth 64는 0~211 blocked channel-cycle을 보였지만 모두 PCU busy와 겹쳐 동일 microarchitecture의 총 cycle은 depth 128과 같았다. 128 entries를 현재 RTL 기준 후보로 유지한다. 다음 작업은 online queue full로 인한 MemoryController head-of-line blocking을 분리 계측하고 bank-side/logic-side 동시 요청 arbitration 모델로 확장하는 것이다.

CommandQueue predicate reject와 발행 가능한 뒤쪽 독립 command를 분리하는 HOL 계측을 추가했다. 진단 probe가 기존 stall counter를 갱신하는 부작용을 발견해 `canAcceptCommand(packet, false)` 경로를 별도로 만들었다. 수정 후 depth 32/64/128 blocked 값은 기존 7,513/211/0으로 복원됐고 predicate reject도 정확히 같았다. 세 조건 모두 발행 가능한 대체 queued command가 없어 command-level HOL은 0이었다. 다음 작업은 bank-side와 logic-side 요청을 의도적으로 겹치는 arbitration microbenchmark와 ready-bypass 정책을 구현하는 것이다.

기존 command path에 bank/logic 독립 요청 arbiter가 없음을 확인하고 `HierarchyPIMArbiter` 사전 통합 모델을 구현했다. Bank/logic 각 64개 동시 요청과 logic 16-cycle not-ready trace에서 bank priority, logic priority, strict round-robin, ready-bypass를 비교했다. Strict round-robin은 15 idle cycles로 142 cycle, ready-bypass는 15회 우회해 127 cycle에 완료했다. 단위 테스트 4개가 통과했다. 다음 작업은 이 arbiter를 PIMRank의 실제 route 결과와 연결해 MobileNetV4에서 source별 wait와 정확도를 검증하는 것이다.

`HIERARCHY_READY_BYPASS`를 실제 MemoryController CommandQueue 발행 경로에 통합했다. 첫 logic predicate reject 후 blocked packet을 보존하고 뒤쪽 ready packet을 probe하는 방식이다. Bypass 탐색이 같은 cycle의 stall을 중복 기록하던 문제를 수정해 기존 7,513/211/0 blocked 값을 복원했다. MobileNetV4 UIB on/off × depth 32/64/128의 6개 실행은 정확도와 214,228 cycle을 유지했고 barrier 때문에 실제 bypass issue는 0이었다. 다음 작업은 독립 spatial tile의 logic pointwise와 bank-side stage를 겹치는 workload overlap scheduler다.

실제 UIB에 stage cycle 계측을 추가해 expand/depthwise/project/add/ReLU가 각각 88,048/20,360/103,288/1,659/873 cycle이고 합계가 전체 214,228과 일치함을 확인했다. 이 측정값과 3×3 halo dependency를 사용하는 14×14 tile pipeline 모델을 구현했다. Wavefront 상한은 191,348 cycle, overlap gain은 22,880 cycle(10.68%)이며 logic resource work 191,336 cycle이 critical path다. 다음 작업은 pointwise spatial 실행을 enqueue/wait/readback으로 나누는 nonblocking tile API다.

Spatial pointwise를 `enqueuePointwiseSpatialGroups`, `waitPointwiseSpatial`, `readPointwiseSpatial`로 분리했다. Handle이 compact weight, position input, raw output 버퍼 lifetime을 보장하고 한 번에 한 outstanding handle만 허용한다. 2-position 테스트는 enqueue 82/wait 782 cycle과 6개 출력 정확도를 통과했다. Expand 3개 row를 bank-side 3×3 depthwise에 연결해 앞 2개 output row 5,376개도 reference와 일치했다. 기존 전체 UIB wrapper는 정확도와 214,228 cycle을 유지했다. 다음 작업은 row-range enqueue/completion을 제공하는 `PointwiseSpatialSession`이다.

`PointwiseSpatialSession`과 연속 행 범위 enqueue/wait/read API를 구현했다. `3×4×3` pointwise를 `2행 + 1행`으로 실행해 36개 출력이 전체 reference와 일치했고 총 2,770 cycle이었다. Active 범위 중복과 비연속 행 요청도 예외 계약으로 검증했다. 현재는 행 범위마다 shared weight fill을 반복하며 하나의 범위만 outstanding이므로, 다음 작업은 세션 단위 weight/CRF residency를 구현한 뒤 3-row line buffer와 실제 wavefront overlap으로 연결하는 것이다.

세션 단위 shared weight residency와 weight layer generation 보호를 구현했다. 첫 범위에서 512 bursts를 채우고 두 번째 범위는 추가 fill 0으로 같은 weight를 재사용했으며, 36개 출력은 유지되고 총 cycle은 2,770에서 2,672로 감소했다. 전체 UIB 18,816개 출력과 214,228 cycle 회귀도 통과했다. 다음 작업은 channel group별 CRF residency를 구현한 뒤 3-row line buffer와 실제 wavefront overlap으로 연결하는 것이다.

Channel group별 logic-die CRF residency를 구현했다. 첫 범위에서 8개 group을 각 1회 프로그램하고 두 번째 범위는 CRF program 0회로 재사용했으며, 36개 출력 정확도를 유지하면서 총 cycle은 2,658로 감소했다. 일반 blocking UIB 경로는 18,816개 출력과 214,228 cycle을 유지했다. 다음 작업은 3-row activation line buffer와 row completion token을 구현해 logic expand와 bank depthwise를 실제 wavefront로 연결하는 것이다.

3-row activation line buffer와 output-row completion token을 구현했다. 독립 4-row 테스트에서 상단/중앙/하단 3×3 window 27개 값, output token 4개, peak resident 3행을 검증했다. 실제 pointwise session의 `2행 + 1행` 결과도 depthwise token `1행 + 2행`으로 release됐다. 다음 작업은 tap마다 전체 큐를 drain하는 `executeDepthwiseLowered`를 nonblocking stage handle로 분리하고 다음 logic 행과 실제 transaction overlap을 만드는 것이다.

Depthwise lowered 연산을 `9 MUL + 8 ADD`의 17개 nonblocking stage handle로 분리했다. Bank 첫 stage와 resident logic pointwise 다음 행을 동시에 pending으로 만든 실험에서 기존 shared CRF가 logic 출력 12개를 모두 0으로 오염시켰다. `PIMRank`에 bank/logic CRF를 분리한 뒤 한 drain에서 bank stage 1개와 logic row 1개가 완료되고 logic 출력 12개가 모두 통과했다. 다음 작업은 packet-domain-aware ready probe와 source별 issue overlap 계측 후 전체 17-stage row wavefront로 확장하는 것이다.

Ready probe도 packet tag에 따라 bank/logic CRF를 선택하도록 수정해 online backpressure 판단과 실제 decode를 일치시켰다. 공동 drain은 1,942 cycle, pending 0, logic 출력 12개 정확도를 유지했다. 다음 작업은 source별 issue overlap 계측과 전체 17-stage row wavefront다.

Source별 issue cycle tracker를 추가했다. Co-pending drain에서 bank는 1,748~2,344 cycle, logic은 2,758~3,080 cycle에 issue되어 window 교집합이 0이고 전환 공백이 414 cycle임을 확인했다. 현재 단일 queue/barrier가 실제 overlap을 직렬화한다. 다음 작업은 bank/logic 독립 command queue와 source-scoped barrier를 실제 MemoryController 발행 경로에 통합하는 것이다.

`HIERARCHY_SOURCE_QUEUES` 뒤에 source-tagged transaction round-robin과 source-scoped command barrier를 실험 구현했다. 활성화 시 cycle은 1,596으로 짧아졌지만 logic issue 0, 출력 0/12로 실패했다. CRF만 분리되고 PC, jump/repeat, exit, PIM mode가 공유된 것이 원인이다. 기본값은 false로 격리했으며 다음 작업은 bank/logic `PIMExecutionContext` 전체 분리다.

Source queue off 경로의 tag/ACT scan 차이로 UIB cycle이 일시적으로 435 증가한 회귀를 찾아 완전히 격리했다. 최종 off 회귀는 출력 18,816개, total 214,228 cycle, stage 88,048/20,360/103,288/1,659/873으로 기존 기준과 동일하다.

Bank/logic 실행 문맥과 command frontend를 분리하고 logic output buffer 및 read-completion 경로를 연결했다. HAB residency의 full UIB timeout은 logic register 출력이 일반 DRAM READ frontend를 거치며 열린 staging row와 충돌한 것이 원인이었다. Direct output transaction을 logic-control frontend로 분류하고 Rank bank-state 검사를 우회한 뒤 3-channel, 6-channel, 42-position expand/depthwise, full UIB가 모두 통과했다. Full UIB는 residency OFF/ON 모두 235,182 cycle과 18,816개 출력 PASS를 유지했고 modeled writes는 225,460에서 220,342로 5,118회(2.27%) 감소했다. 다음 작업은 1,209,004회의 rank command reject를 source, operation tag, mode-ready, bank-state 원인별로 분해해 full workload critical path를 결정하는 것이다.

Rank command reject를 mode transition/logic queue와 bank/logic domain으로 분해했다. HAB residency ON, mode latency 32의 full UIB는 18,816개 출력과 235,182 cycle을 유지했고, 1,943,168회의 rank reject가 모두 mode transition이었다. Logic queue reject는 0, bank domain은 669,056, logic domain은 1,274,112회였다. 이 값은 후보 command의 거절 시도 횟수이므로 손실 cycle과 같지 않다. 다음 작업은 CommandQueue issuability 실패와 원인별 wall-cycle을 계측하고 mode latency 0/32 A/B로 실제 critical-path 기여도를 측정하는 것이다.

CommandQueue issuability를 bank state/timing/row mismatch 등으로 분해하고 controller 무발행 channel-cycle을 추가했다. Full UIB mode latency 0/32 A/B는 모두 18,816개 출력을 통과했으며 233,556/235,182 cycle로 mode 비용은 1,626 cycle(0.70%)이었다. Latency 32의 rank mode blocked controller channel-cycle은 160,451이었고 logic queue blocked는 0이었다. Bank-state blocked channel-cycle은 14,358,548/14,462,890으로 가장 컸다. 다음 작업은 MultiChannelMemorySystem에서 동일 cycle의 channel 상태를 집계해 합산 channel-cycle과 실제 global critical path를 분리하는 것이다.

MultiChannel global any/all-active/peak blocked 계측을 구현했다. Latency 0/32의 bank-state all-active cycle은 218,988/219,645, timing은 35,189/34,360, row mismatch는 9,862/9,854였다. Latency 32의 Rank mode any/all-active는 3,171/2,155 cycle이고 peak는 64채널이었다. Bank-state는 full 실행 대부분과 공존하는 강한 병목 후보지만 epoch mismatch/barrier/write-bus predicate와 같은 cycle에 중복될 수 있다. 다음 작업은 hierarchy predicate의 global/exclusive blocker를 추가해 실제 원인을 확정하는 것이다.

Exclusive 분석에서 bank-state only 175,229 cycles, hierarchy-only 0 cycle을 확인해 direct weight staging command path를 첫 architecture 변경으로 구현했다. Fill ACT는 1,120에서 0으로 제거되고 fill completion 3,584와 modeled writes 220,342, 출력 18,816개는 유지됐지만 total cycle은 235,182에서 235,130으로 52 cycle만 감소했다. Stage 분해 결과 bank-state-only는 expand 79,748, project 94,758 cycle로 대부분이 logic pointwise에 집중됐다. 다음 작업은 pointwise bank-state reject를 operation tag별로 분해해 mode/park/input/MAC 중 두 번째 architecture 변경 대상을 선택하는 것이다.

위 bank-state-only 결론은 speculative PRECHARGE probe가 실제 workload blocker로 집계된 계측 오류였다. 계측을 보정한 뒤 bank-state-only는 0 cycle이었고, 정확도와 235,182 cycle은 유지됐다. Direct staging의 52-cycle 개선은 유효하지만 주 병목 제거 근거로는 사용하지 않는다.

단계별 hierarchy predicate를 분해한 결과 depthwise 38,884 cycle 중 hierarchy all-active가 30,173 cycle이었다. Write-bus busy 22,394, epoch mismatch 10,031, barrier outstanding 8,729 cycle로 writeback 병목이 가장 컸다. 다음 기술 구현은 `9 MUL + 8 ADD` 중간 결과를 DRAM에 반복 기록하는 대신 logic-die accumulation buffer에서 누산하고 최종 합만 기록하는 선택형 depthwise hierarchical accumulation 경로다.

선택형 depthwise hierarchical accumulation 1차 경로를 구현했다. 공유 `LogicDieAccumulator`를 base logic die 범위에 배치하고 bank partial/final packet, 용량/latency/bandwidth 설정과 통계를 연결했다. 초기 64채널 경계 오류는 중간 writeback 제거 시 CRF 진행 패킷도 함께 사라져 odd-bank FILL이 건너뛴 것이 원인이었다. Accumulator-direct 패킷이 DRAM write 없이 CRF PC/NOP를 진행하도록 수정했다. 이후 실제 shape depthwise 출력 37,632개와 전체 UIB 최종 출력 18,816개가 모두 통과했다. 전체 UIB modeled write는 220,342→199,350으로 9.53% 감소했지만 tap별 직렬 전송 때문에 cycle은 235,182→265,022로 12.69% 증가했다. 다음 작업은 bank MUL과 전송 overlap, tile/row aggregation, accumulator link parameter sweep이다.

Bank MUL과 accumulator link를 겹치는 선택형 streaming 모델을 추가하고 raw/overlap/wait cycle을 분리 계측했다. 전체 UIB 64 B/cycle overlap은 256,484 cycle로 직렬 265,022보다 개선됐지만 기준보다 느렸다. 256 B/cycle에서는 depthwise 35,352, total 231,650 cycle로 기준 235,182를 3,532 cycle(1.50%) 통과했고 최종 출력 18,816개와 modeled write 199,350을 유지했다. 256 B/cycle은 최초 성능 crossover 후보일 뿐 물리 사양 확정이 아니다. 다음 작업은 128 B/cycle 이하에서 bank local aggregation으로 전송 bytes를 줄이는 구조다.

Bank-local aggregation factor를 구현해 CRF 진행은 매 tap 유지하면서 factor 마지막에만 logic partial을 flush하도록 만들었다. 실제 UIB에서 128 B/cycle·factor 3은 231,727 cycle, 64 B/cycle·factor 9는 231,178 cycle로 모두 최종 출력 18,816개를 통과했다. Factor 9는 partial burst 73,728→8,192, transfer 2,359,296→262,144 B로 88.89% 줄였고 기준보다 4,004 cycle(1.70%) 빨랐다. 다음 작업은 bank-local accumulator entry/port 제한과 random FP16 정확도다.

Bank-local accumulator에 entries/ports/latency와 command-ready backpressure를 구현했다. 실제 peak는 rank당 128 entries였고 128 entries·4 ports·latency 1의 전체 UIB는 231,309 cycle, modeled write 199,350, 최종 출력 18,816 PASS였다. 무제한 후보보다 131 cycle만 느리고 기준보다 3,873 cycle(1.65%) 빨랐다. 현재 RTL 후보는 64 B/cycle link, factor 9, 128 entries/rank, 4 ports, latency 1이다. 다음 작업은 banked port conflict와 random FP16 rounding 검증이다.

Signed fractional deterministic 입력으로 FP16 rounding을 검증했다. Factor 1과 factor 9 모두 software FP16 golden 128개와 bit-equivalent하게 일치했고 FP32 기준 최대 절대오차는 0.00601459로 같았다. Factor 9는 tap 순서를 유지해 연산 위치만 bank-local로 옮기므로 현재 순차 accumulator에서는 rounding 결과가 바뀌지 않는다. 다음 작업은 PIM-block별 banked port conflict와 다른 MobileNetV4 depthwise shape다.

PIM-block별 banked accumulator를 구현했다. `BANK_LOCAL_ACCUMULATOR_BANKS`로 총 entry를 균등 분할하고, PIM block modulo mapping, bank별 capacity/peak, bank당 port service cycle을 실제 command-ready backpressure에 연결했다. 14×14×192에서 4 banks×1 port는 중앙 1 bank×4 ports와 같은 33,622 cycle, 8 banks×1 port는 33,138 cycle이었으며 출력 37,632개가 모두 통과했다. 28×28×192 확장 shape도 출력 150,528개가 모두 통과했고 총 peak 256, bank당 peak 32를 확인했다. 따라서 128-entry는 shape 종속값이며 다음 작업은 tile별 flush로 live entry를 제한하고 8-bank 후보를 전체 UIB에서 검증하는 것이다.

`BANK_LOCAL_ACCUMULATOR_TILE_BATCH`를 추가해 tile batch 바깥, tap 안쪽 실행 순서를 구현했다. 28×28×192를 batch 1로 실행하면 총 peak 256→128, bank당 peak 32→16으로 줄고 출력 150,528개가 모두 통과했다. Cycle은 63,910→65,250으로 2.10% 증가했다. 동일 현재 설정의 전체 UIB controlled A/B에서 bank-depthwise 233,365 cycle/225,460 writes, 중앙 1 bank×4 ports 230,514/204,468, 분산 8 banks×1 port 230,075/204,468이었고 세 경로 모두 최종 출력 18,816개를 통과했다. 다음 작업은 shape sweep과 Verilog module/interface 초안이다.

C++ 후보를 `rtl/bank_local_reduction_buffer.sv`의 SystemVerilog 제어 모듈로 구체화했다. 8 banks, bank당 16 slots, bank당 1 update lane, key/slot validation, valid-ready backpressure와 final output register를 표현했다. FP16 vector adder는 외부 port로 분리했고 self-checking testbench도 추가했다. 현재 WSL에는 RTL 도구가 없어 compile/simulation/synthesis는 미검증 상태다. 다음 작업은 RTL 도구 설치 후 testbench와 FP16 pipeline 검증, 이어서 logic-die link arbiter 구현이다.

Icarus Verilog 12.0을 사용자 홈에 로컬 설치하고 RTL compile 및 self-checking simulation을 수행해 `BANK_LOCAL_REDUCTION_BUFFER_TB PASS`를 확인했다. Procedural packed-array index의 Icarus 제한은 bank별 generate 구조로 바꿔 해결했고, 이 구조는 8개 독립 SRAM bank라는 설계 의미와도 일치한다. 재실행용 `rtl/bootstrap_iverilog_local.sh`, `rtl/run_tests.sh`를 추가했다. 다음 작업은 FP16 pipeline과 logic-die link arbiter다.

8-input round-robin `logic_die_link_arbiter.sv`를 추가해 downstream backpressure와 공정한 bank 선택을 검증했고 `LOGIC_DIE_LINK_ARBITER_TB PASS`를 확인했다. RTL burst 기본폭을 C++와 같은 256 bit=32 B로 정정했다. 현재 단일 output lane은 32 B/cycle이라 C++ 후보 64 B/cycle과 차이가 있으며, 다음 작업은 dual-lane arbiter와 FP16 pipeline이다.

2×256-bit `logic_die_dual_link_arbiter.sv`를 구현해 최대 64 B/cycle 폭을 C++ 후보와 일치시켰다. Reduction buffer와 arbiter를 연결한 `hierarchical_reduction_path.sv` 통합 testbench를 추가했고 buffer, single/dual arbiter, 통합 경로 네 테스트가 모두 PASS했다. 다음 작업은 random sustained-bandwidth 검증과 FP16 valid pipeline이다.

Dual-link stress test를 추가했다. 초기 arbiter는 stall 중 새 valid source가 나타나면 output payload가 바뀌는 valid/ready 위반이 발견됐고, hold grant/key/data/source register를 추가해 수정했다. 최종 512-cycle saturation에서 1,024 burst=64 B/cycle, 2,000-cycle random에서 1,052 burst, 모든 source progress와 stalled payload 안정성을 통과했다. 다음 작업은 C++ workload trace와 FP16 pipeline이다.

초기 RTL top이 한 rank의 8 PIM-block slice만 표현한다는 C++ 대응 불일치를 발견했다. `logic_die_64ch_reduction_top.sv`를 추가해 64 channel 각각에 8→1 local arbiter를 두고 global 64→2 dual arbiter로 연결했다. 4채널 축소 기능 test와 production default 64채널×8 block elaboration이 PASS했다. Data array 해석도 4 KiB/rank, 256 KiB/stack으로 정정했다. 다음 작업은 C++ partial arrival trace replay다.

C++ bank-local flush에 cycle/channel/rank/PIM-block/key trace를 추가했다. 실제 14×14×192 trace는 8,192 event이며 16개 cycle에 각 512 event가 wave로 도착했다. C++ 2-stage replay와 `logic_die_64ch_trace_replay_tb.sv` RTL replay가 모두 4,096 full cycles, 64 B/cycle로 일치했고 출력 37,632개도 PASS했다. 다음 작업은 다른 shape의 utilization과 source queue depth다.
