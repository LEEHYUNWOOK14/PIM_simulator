# 00. 저장소 목록과 감사 기준 상태

## 기준 상태

- 감사 시작: 2026-08-06 16:49:09 +09:00
- 저장소: `C:\Users\Chandler\OneDrive\2026-하계\STOB 반도체 경진대회\STOB_PIM2`
- Git branch: `PIM_Simulator`
- Git commit: `8534693d528742d52b9329b4a1feed3b4831dddb`
- 감사 프롬프트 SHA-256: `D8EBE8D31F28AF19F961FAEA12FEA31D2826DABF597E81D084DC828ECC2D0BC6`
- 작업 트리: dirty. 기존 tracked 수정 9개 이상, Full-PIM RTL 대부분과 여러 설계·flow 파일이 untracked다.
- production RTL 수정: 없음
- 감사용 신규 파일: `verification/rtl_audit/`, `reports/rtl_audit/`에만 생성

이 감사의 가장 큰 baseline 제한은 Full-PIM RTL이 commit에 고정되지 않았다는 점이다. 따라서 결과는 위 시점의 working tree에만 적용된다.

## 도구

|도구|버전|상태|
|---|---|---|
|Icarus Verilog/VVP|12.0 stable|사용 가능|
|Yosys|0.52, git `fee39a3284c90249e1d9684cf6944ffbbcbb8f90`|사용 가능|
|Verilator|미설치|TOOL UNAVAILABLE|
|SymbiYosys (`sby`)|미설치|TOOL UNAVAILABLE|
|OpenROAD|기본 shell PATH에 없음|현재 감사에서 재실행하지 않음|

## RTL 계열

현재 저장소에는 서로 다른 두 계열이 공존한다.

1. 기존 reduction/physical 계열: `logic_die_64ch_reduction_top`, `bank_local_reduction_buffer`, shared FP16 pipeline 및 dual-link arbiter
2. 신규 Full-PIM 계열: `full_pim_system_top`, bank-side subsystem, CRF, PCU scheduler, coalescer, epoch, shared buffer 및 TSV

`flow/synth.ys`와 현재 GDS는 첫 번째 계열을 대상으로 한다. 신규 Full-PIM top은 해당 물리 flow에 포함되지 않는다.

## 권위 자료 상태

- 명령 encoding: `src/PIMCmd.h/.cpp`
- bank PIM 동작: `src/PIMBlock.h/.cpp`, `src/PIMRank.cpp`
- logic scheduler/config: `src/LogicDieScheduler.h`, `system_hbm_64ch.ini`
- HBM timing: `ini/HBM2_samsung_2M_16B_x64.ini`
- 설계 문서 다수가 mojibake 상태다. C++ 원문과 정상적으로 읽히는 설정을 우선했다.

## 물리 산출물 baseline

- `output/output.gds`: 11,224,570 bytes
- SHA-256: `3A4DC01ED044FD2B2BCAD17786EF175F404EC1D969D1B6AFE90F8189E5117628`
- 문서상 top: `logic_die_64ch_reduction_top_pwrwrap`
- 문서상 die: 334.660 µm × 334.660 µm
- 문서상 detailed-route violation: 0
- 문서상 antenna violation: 3

## Baseline 위험

- `flow/designs/sky130hd/stob_pim2/config.mk`의 `VERILOG_FILES`는 `/mnt/c/orfs/rtl/*.sv` 절대경로 wildcard를 사용한다. 문서상 repository junction이지만 감사 시점의 workspace와 동일한 내용을 가리킨다는 hash manifest는 없다.
- GDS 생성 당시 RTL hash 또는 source commit manifest가 없다.
- Full-PIM RTL과 물리 산출물의 동일성을 증명할 수 없고, top 이름으로는 명백히 서로 다르다.
