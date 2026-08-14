# 작업 010: WBQ 3_4 repair 정체 진단과 Steiner alpha 실험

## 1. 문제 정의

WBQ Phase 3의 `3_4 place_resized`가 고 fanout net의 Steiner tree 계산과 buffer 삽입 이후의 anonymous subtree 계산에서 장시간 정체됐다. 목표는 실행을 무조건 완료시키는 것이 아니라, 병목을 재현하고 우회 실험과 최종 정책을 구분하는 것이다.

## 2. 작업시간

- 관측 시작: 2026-08-14 06:34:20 UTC
- 실험 실행 시작: 2026-08-14 08:28:25 UTC
- 진단·전환 관측 구간: 1시간 54분 5초
- 산정 근거: 최초 보존 로그, net 진단 로그, guarded archive와 V3 실행 기록
- 한계: V3 실행은 문서 작성 시점에도 별도 프로세스로 진행될 수 있으므로 위 시간은 완료 시간이 아니라 진단 후 새 실험을 시작하기까지의 구간이다.

## 3. 원인 규명

진단은 다음 순서로 진행했다.

1. 검증된 `3_3_place_gp.odb`에서 문제 net의 Steiner 계산을 분리 재현했다.
2. `clk_i`와 `rst_ni`의 `alpha=0.3` 경로가 180초 제한을 초과함을 확인했다.
3. 같은 net의 `alpha=0.0` 계산이 약 4초에 완료됨을 확인했다.
4. net별 guard 적용으로 placement parasitic estimation이 925초에서 약 189초로 줄어드는 것을 관측했다.
5. buffer 삽입 뒤 원본 `dbNet`이 없는 subtree가 global alpha로 복귀하면서 정체가 재발하는 소스 경로와 실행 현상을 연결했다.

따라서 V3의 global `alpha=0.0`은 품질 최적화가 아니라 anonymous subtree까지 병목 경로를 우회하는 진단용 기준선이다.

## 4. 실행 안전장치와 보존

- 중복 OpenROAD 실행을 거부한다.
- `PRE_RESIZE_TCL`로 설정 범위를 3_4 프로세스에 한정한다.
- 기존 부분 결과와 로그를 timestamp archive로 이동해 보존한다.
- 검증된 3_3 ODB hash와 hook hash를 실행 보고서에 기록한다.
- Phase 4 ownership gate는 3_4 결과가 분류될 때까지 유지한다.

부분 배치 ODB 두 경로는 각각 2,935,363,098 byte로 GitHub 단일 파일 제한을 넘는다. 두 경로의 내용은 동일하며 SHA-256은 `2debf80b1917e212d27f090ada86aab0f04f0f0eab3bff9005e033632858d07b`이다. 파일은 로컬에 보존하고, Git에는 [`partial_place_archive_20260814T074614Z/MANIFEST.md`](../reports/groot_normalization/physical_feasibility/partial_place_archive_20260814T074614Z/MANIFEST.md)와 로그·SDC를 보존한다.

## 5. 품질 판정과 장기 수정

global alpha 결과는 다음 gate를 통과하기 전에는 최종 결과가 아니다.

1. 3_4 정상 종료와 ODB 생성
2. slew/capacitance/fanout 위반 비교
3. setup/hold와 buffer·면적 증가 비교
4. detailed placement legality 확인
5. global-route congestion과 최종 구조 hash 확인

품질 손실이 있으면 3_4부터 다시 계산해야 한다. 선호하는 장기 수정은 모든 net의 alpha를 하나로 통일하는 것이 아니라, repair transaction에서 결정한 원본 net의 alpha를 buffer subtree에 명시적으로 전달하는 것이다.

```text
subtree_alpha = original_net_alpha
```

세부 측정값, 비교 gate와 후보 alpha 정책은 [`../reports/groot_normalization/physical_feasibility/wbq_alpha_policy/README.md`](../reports/groot_normalization/physical_feasibility/wbq_alpha_policy/README.md)에 고정되어 있다.
