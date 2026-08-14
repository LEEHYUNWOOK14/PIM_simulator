# 작업 008: 외부 출처와 provenance 스냅샷 정리

## 1. 목적

프로젝트의 HBM2, normalization, 배치, 열, 비용 근거가 여러 디렉터리에 흩어져 있어 연구 결과와 출처의 연결을 한곳에서 추적하기 어려웠다. 이 작업은 원본을 대체하지 않고, 특정 시점의 출처 파일을 보존하고 원본과 수집본의 동일성을 검증할 수 있는 중앙 색인을 만드는 것이 목적이다.

## 2. 작업시간

- 관측 시작: 2026-08-14 02:42:17 UTC
- 관측 종료: 2026-08-14 02:42:27 UTC
- 관측 구간: 10초
- 산정 근거: `source_artifact_inventory.md`와 `archive/` 파일의 수정 시각
- 한계: 준비·조사 시간을 별도로 계측하지 않았으므로 실제 작업시간이 아니라 파일 생성이 확인되는 최소 구간이다.

## 3. 수행 내용

1. 기존 canonical provenance 파일의 위치를 조사했다.
2. `work_status/sources/archive/`에 수집 시점의 스냅샷을 보존했다.
3. 각 수집본을 원본 경로, SHA-256, byte 크기와 연결했다.
4. 측정값, 공개자료, 프로젝트 가정이 혼동되지 않도록 출처 인덱스의 판정 경계를 유지했다.

핵심 산출물은 [`sources/source_artifact_inventory.md`](sources/source_artifact_inventory.md)이며, 수집 정책과 전체 출처 분류는 [`sources/README.md`](sources/README.md)에 설명되어 있다.

## 4. 논리적 의미

스냅샷은 “출처가 존재한다”는 증거이고, 수치가 곧 실측값이라는 증거는 아니다. 따라서 결과 해석은 다음 순서를 따른다.

```text
결과 수치
  -> provenance 파일에서 입력과 분류 확인
  -> inventory에서 원본과 snapshot hash 일치 확인
  -> measured / modeled / assumed 경계에 맞게 주장 강도 결정
```

## 5. 검증과 한계

- inventory에 8개 수집본의 원본 경로·SHA-256·크기가 기록되어 있다.
- 추가 canonical provenance는 중복 복사하지 않고 직접 참조한다.
- 외부 웹페이지 자체를 저장한 것이 아니라 프로젝트가 사용한 source registry와 실행 로그를 고정한 것이다.
