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
