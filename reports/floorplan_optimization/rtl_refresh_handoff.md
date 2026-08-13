# 최종 RTL 확정 후 재실행 handoff

현재 결과는 dirty reduced `full_pim_system_top` 스냅샷과 estimated 4 W power model을 조합한 provisional recommendation이다. GR00T workload·BF16 trace·RTL 구조가 확정되면 아래 입력만 교체하고 공통 좌표 및 분석 흐름은 유지한다.

## 교체 입력

1. 최종 RTL source list/top/parameter와 SHA-256
2. Yosys/OpenROAD 합성 면적, hierarchy, placement DEF/ODB, STA constraint
3. 대표 GR00T trace에서 산출한 toggle/activity 및 clock/voltage/시간창
4. leakage·dynamic power report와 block/module mapping
5. 확정 PHY/channel/package pin map, TSV pitch/diameter/keep-out, PDN rule
6. calibration 가능한 material·boundary·TIM·cooling 조건

## 재실행

```powershell
.\flow\run_flow.ps1 -Target synth
.\flow\run_flow.ps1 -Target do-floorplan
.\flow\run_flow.ps1 -Target do-place
.\flow\run_flow.ps1 -Target do-cts
.\flow\run_flow.ps1 -Target do-route
.\tools\run_logic_die_floorplan_analysis.ps1 -IncludeCurrentRtlPhysical
```

상세배선은 현재 90%에서 약 6.55 GB를 사용한 뒤 WSL이 비정상 재시작되어 기본 orchestration에서 제외했다. 메모리 상한·swap·route 설정을 먼저 확정한 뒤 별도 실행한다. 최종 판단 전에는 STA input/output delay, unconstrained endpoints, Liberty, PDN/IR 분석 및 DRC/LVS를 반드시 닫아야 한다.
