# 작업 009: OpenROAD 장시간 작업 분석·모니터링 도구

## 1. 목적

OpenROAD `repair_design`은 CPU를 계속 사용하면서도 진행 counter가 오랫동안 바뀌지 않을 수 있다. 단순히 프로세스가 살아 있다는 사실만으로 정상 진행과 계산 정체를 구분할 수 없으므로, 실행 중 관측과 실행 이력 분석을 분리해 제공했다.

## 2. 작업시간

- 관측 시작: 2026-08-14 06:09:02 UTC
- 관측 종료: 2026-08-14 06:37:49 UTC
- 관측 구간: 28분 47초
- 산정 근거: 모니터 소스와 생성 보고서의 수정 시각
- 한계: 사전 조사시간은 포함되지 않은 최소 관측 구간이다.

## 3. 구현 구조

### 실시간 관측

[`../tools/monitor_openroad_repair.py`](../tools/monitor_openroad_repair.py)는 repair 로그의 최신 iteration, remaining net, buffer/resize 수를 읽고 `/proc`의 CPU 시간과 결합한다. 이 정보로 진행률, 처리율, ETA, 로그 나이와 다음 세 상태를 구분한다.

- `advancing`: counter가 실제 증가함
- `CPU active; counter stalled`: CPU는 사용하지만 counter가 정지함
- `idle/stalled`: counter와 CPU 활동이 모두 낮음

모니터 종료는 OpenROAD 프로세스를 종료하지 않는다.

### 사후 분석

[`../tools/generate_long_running_task_report.py`](../tools/generate_long_running_task_report.py)는 장시간 명령과 로그 표식을 수집해 JSON과 HTML 보고서를 만든다. 생성물은 `REPORT/long_running_tasks/`에 보존된다.

## 4. 판정 흐름

```text
프로세스 존재 확인
  -> CPU 시간 변화 확인
  -> repair counter 변화 확인
  -> 처리율과 log age 계산
  -> 정상 진행 / 내부 장시간 계산 / 유휴 정체 분류
  -> 필요하면 net 단위 재현 진단으로 전환
```

이 도구는 정체 원인을 스스로 확정하지 않는다. “어디에서 진행 관측이 사라졌는가”를 재현 가능한 데이터로 좁혀 다음 진단의 입력을 만든다.

## 5. 검증과 한계

- Python 구문 검사를 수행할 수 있는 독립 스크립트로 구성했다.
- 로그 형식이 바뀌면 정규식 갱신이 필요하다.
- ETA는 최근 처리율을 기반으로 하므로, 초대형 net 내부 계산처럼 counter가 불연속적으로 증가하는 구간에서는 참고값이다.
