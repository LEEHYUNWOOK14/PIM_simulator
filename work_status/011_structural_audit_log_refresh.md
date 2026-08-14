# 작업 011: normalization 구조 감사 로그 재생성

## 1. 목적

Normalization RTL의 FP16/BF16 및 scalar/vector/pipelined/reduction/hierarchical 변형에 대한 Yosys 구조 감사 로그를 현재 EDA 환경에서 다시 생성했다. 결과의 논리적 통과 여부뿐 아니라 실제 사용 도구와 실행 환경을 provenance로 남기는 작업이다.

## 2. 작업시간

- 실행시간: 산정 불가
- 이유: 로그 내부의 개별 Yosys 실행시간은 기록되어 있지만 전체 batch의 명시적인 시작·종료 timestamp가 없다.
- 원칙: 확인할 수 없는 시간을 파일 수정 시각으로 추측해 총 작업시간으로 주장하지 않는다.

## 3. 변경 내용

28개 구조 감사 로그에서 다음 환경 정보가 현재 실행값으로 갱신됐다.

- Yosys/techmap 경로: 로컬 OSS CAD Suite 경로에서 ORFS 설치 경로로 변경
- Yosys revision과 compiler 정보 갱신
- 실행시간, peak memory와 logfile hash 갱신

각 RTL 변형의 구조 검사 결과는 계속 `0 problems`를 보고한다. 따라서 이번 diff는 RTL 기능 변경이 아니라 동일 감사를 현재 도구 환경에서 재생성한 provenance 변경이다.

## 4. 해석 경계

```text
구조 감사 0 problems
  -> Yosys check가 탐지하는 구조 오류가 없음
  -/-> RTL 기능 전체가 증명됨
  -/-> timing / placement / routing signoff 완료
```

기능 정확도는 별도 testbench 회귀, 물리 구현 가능성은 OpenROAD 단계별 gate로 판단해야 한다.

## 5. 재현

재생성 진입점은 `verification/groot_normalization/run_normalization_structural_audit.sh`이며, 결과는 `reports/groot_normalization/results/structural_audit/`에 저장된다.
