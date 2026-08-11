# PIM 전체 RTL 구현·안정화 보고서

## 결론

기존 로직 다이의 단순 PCU만으로는 부족했던 구조를 보완해, DRAM 뱅크 옆 PIM부터 로직 다이 16-PCU까지 이어지는 실행 가능한 RTL 계층을 추가했다. 총 8개 자체검증 테스트가 모두 통과했고, 핵심 연산 블록은 Yosys 합성과 구조 검사를 통과했다.

## 전체 데이터 흐름

`DRAM 명령/타이밍 → bank/subarray 모델 → 2-bank PIM block → 채널 결과 중재 → 직접 TSV 또는 로직 operand context → 명령 coalescer/epoch barrier → 16-PCU scheduler → result router/reduction`

뱅크 PIM은 C++의 `PIMRank.cpp`와 같이 짝수·홀수 두 뱅크를 한 PIM block이 읽는다. CRF 명령은 채널 내 PIM block들이 lockstep으로 실행한다. 로직 다이는 동일 epoch/ordinal/signature의 채널 명령을 하나의 mask로 합치고, 최대 16개 PCU에 한 사이클에 분배한다.

## 근거와 설계 판단

- 명령 비트와 ADD/MUL/MAC/MAD/MOV/FILL 의미: `src/PIMCmd.h`, `src/PIMCmd.cpp`.
- 8개 GRF-A/B, SRF, M_OUT/A_OUT 및 FP16 16-lane 의미: `src/PIMBlock.h`, `src/PIMBlock.cpp`.
- 두 뱅크당 한 PIM block: `src/PIMRank.cpp`.
- 64채널, 16뱅크, 채널당 8 PIM block, 16 PCU, 2-cycle PCU, 64 B/cycle, 64KiB buffer, 128 coalescer entry: 저장소의 HBM 설정과 `LogicDieScheduler` 계열 소스.
- C++에 없는 ready/valid, 유한 큐, backpressure 안정성은 실제 하드웨어를 위해 명시적으로 추가한 설계 판단이다.
- DRAM 배열은 ACT/RD/WR/PRE/REF와 tRCD/tRAS/tRP를 검사하는 유한 behavioral model이며 실제 DRAM cell 합성을 의미하지 않는다.

외부 논문은 기능 계약의 근거로 사용하지 않았다. 따라서 출처는 저장소 내부 C++와 설정 파일이며, 상세 비트 정의와 판단 구분은 `design/full_pim_rtl_architecture.md`에 기록했다.

## 검증 결과

|검증|결과|
|---|---|
|FP16/INT8 ALU 및 특수값|PASS|
|DRAM 정상/타이밍 위반 경로|PASS|
|2-bank PIM/CRF lockstep|PASS|
|coalescer, epoch, buffer, reduction|PASS|
|16 PCU 동시 발행|PASS (16/16)|
|전체 top 직접 TSV + 로직 경로|PASS|
|랜덤 backpressure stress|PASS (40 batches, 320 results)|
|bank core 합성/구조 검사|PASS, 22,653 generic cells|
|2-PCU scheduler 합성/구조 검사|PASS, 28,786 generic cells|
|2-channel 전체 계층 구조 검사|PASS, 7,031 hierarchical cells|

검사 중 `0 × infinity`의 NaN 우선순위, stalled TSV lane 중복 선택, scheduler 조합 ready loop, 축소 폭 SRF 범위 초과, 공유버퍼 주소폭 고정 등 5개 결함을 발견해 수정했고 전 회귀를 재실행했다.

## 실행 방법과 한계

- 기능: `wsl bash rtl/run_full_pim_tests.sh`
- 합성/구조: `wsl bash rtl/run_full_pim_synthesis.sh`
- 결과: `experiment/results/full_pim_rtl/`

전체 64채널 기본 구성의 gate-level PPA나 실 DRAM PHY 검증까지 완료했다는 의미는 아니다. 대형 DRAM behavioral array는 합성 대상에서 제외했고, 전체 top 구조 검사는 자원 절약을 위해 2채널 축소 구성으로 수행했다. 실제 tape-out 단계에는 vendor DRAM macro/PHY, CDC, STA, DFT 및 물리 검증이 추가로 필요하다.
