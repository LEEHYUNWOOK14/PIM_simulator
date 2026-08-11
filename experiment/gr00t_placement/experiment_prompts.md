# Experiment prompts

## User request that initiated the experiment

> 입력 가정, 가중치, 민감도 분석을 정량적으로 실시해주고 필요한 순간에는 실험도 진행해.
> 실험 모델은 일단 엔비디아에서 나온 그루트로 하고, 모델 정보는
> `C:\Users\Chandler\OneDrive\2026-하계\STOB 반도체 경진대회\STOB_PIM_pure_layornorm`에서 확인해.
> 모든 작업의 출처를 정확히 표기하고, 실험을 다시 수행할 수 있도록 프롬프트와 상세 용어 설명,
> 그래프 및 도표를 포함한 보고서를 남겨.

## Scope control prompt

> RTL 구조 안정 작업은 따로 하고 있으니 그 전 작업까지만 진행해줘.

## Deterministic experiment note

The numerical experiment does not call a generative model and has no hidden model prompt.
`analyze_placement.py`, `assumptions.json`, fixed random seed `1701`, and the commands in
`tools/reproduce_gr00t_placement_pre_rtl.ps1` fully specify the computation.

## Reproduction command

```powershell
.\tools\reproduce_gr00t_placement_pre_rtl.ps1
```
