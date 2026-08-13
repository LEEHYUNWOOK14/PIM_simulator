# Phase 4 — OpenROAD 물리 검증

## 판정

두 종류의 OpenROAD 근거를 분리했다.

1. 후보 좌표 비교는 8개 conceptual macro와 8개 channel TSV endpoint를 고정 배치한 **manifest-driven global-routed modeled proxy**다.
2. 현재 dirty RTL snapshot은 reduced `full_pim_system_top`을 Sky130HD로 **synthesized → floorplanned/PDN → placed → CTS → global-routed**했다. 후보 conceptual block과 RTL hierarchy가 1:1 대응하지 않으므로 이 결과를 후보별 RTL timing/route 근거로 사용하지 않는다.

둘 다 공개 PDK 연구 흐름이며 HBM 제조 signoff가 아니다.

## 후보별 동일 조건 global route

OpenROAD `26Q3-1080-gab6fd26351`, Sky130HD routing layer `met2–met5`, die 축척 0.1, 동일 manifest connectivity로 다섯 strategy를 실행했다. DEF의 16개 fixed instance 좌표와 orientation을 metadata에 대해 round-trip 검증했고 최대 오차는 모든 후보에서 `0.0 µm`였다.

| 후보 | Global-route WL (µm) | Overflow 합 | 위반 bin | 최대 overflow | 결과 |
|---|---:|---:|---:|---:|---|
| manual_baseline | 59,781.6 | 0 | 0 | 0 | global-routed, no reported overflow |
| wirelength_first | 56,297.1 | 0 | 0 | 0 | global-routed, no reported overflow |
| thermal_first | 58,567.2 | 225 | 221 | 2 | global-routed with overflow |
| balanced | 55,827.9 | 358 | 350 | 2 | global-routed with overflow |
| cost_first | 55,827.9 | 358 | 350 | 2 | balanced와 동일 좌표 |

초기 collector가 congestion report의 내용을 읽지 않고 로그 단어 부재를 overflow 0으로 해석하던 결함을 수정했다. 현재 CSV는 `congestion.rpt`의 capacity/usage를 직접 집계한다.

후보 macro에는 Liberty model이 없고 proxy PDN이 없으므로 setup/hold와 static IR-drop은 `not_available`이다. fixed macro이므로 standard-cell global placement/legalization 결과도 아니다. 산출 DEF, ODB, route guide와 raw congestion report는 `output/floorplan_optimization/openroad_proxy/<strategy>/`에 있다.

## 현재 RTL snapshot의 독립 물리 구현

| 단계 | 결과 | 핵심 수치 | 분류 |
|---|---|---|---|
| Yosys synth | PASS | 75,925 cells, 836,200.733 µm², check 0 problems | synthesized |
| floorplan/PDN | PASS | die 1,673.53 µm square, core util 30.1%, tapcell 36,900 | placed/floorplanned |
| global+detailed placement | PASS | illegal cell/site 0, post-mirror HPWL 4,809,426.8 µm | placed |
| CTS | PASS | 14,459 sinks, 1,696 clock buffers, illegal cells 0 | placed |
| global route | PASS | 102,932 nets, 7,914,921 µm, congestion 0/0/0 | global-routed |
| detailed route | FAIL | 90%에서 45,913 violations; peak 6.55 GB 후 WSL unclean restart, output ODB 없음 | failed/not routed |

Global-route STA log는 10 ns constraint에 clock slack `-45.853 ns`를 보고했다. 또한 input delay 미지정 554 ports, output delay 미지정 407 ports, unconstrained endpoints 13,481개가 있으므로 timing closed가 아니다. PDN geometry는 생성했지만 static IR-drop은 실행하지 않았다.

## 기존 흐름 강화

- `flow/run_flow.ps1`이 현재 저장소를 WSL path로 자동 변환하고 새 OpenROAD/Yosys 설치 경로를 사용한다.
- `config.mk`의 `/mnt/c/orfs` 하드코딩을 `STOB_REPO_ROOT`로 일반화했다.
- OneDrive conflict copy `*-DESKTOP-*`는 합성 입력 목록에서만 제외하며 파일 자체를 삭제하지 않는다.
- ORFS 공식 `do-floorplan`, `do-place`, `do-cts`, `do-route`, `do-finish` stage target을 지원해 변동 중 RTL을 불필요하게 재합성하지 않는다.

## 재현 명령

```powershell
.\tools\run_floorplan_openroad_proxies.ps1
.\flow\run_flow.ps1 -Target synth
.\flow\run_flow.ps1 -Target do-floorplan
.\flow\run_flow.ps1 -Target do-place
.\flow\run_flow.ps1 -Target do-cts
.\flow\run_flow.ps1 -Target do-route
```

`do-*` 명령은 이전 단계 ODB snapshot을 소비한다. RTL이 변경되면 먼저 `synth`를 다시 실행해야 한다. 상세 수치와 ODB SHA-256은 `reports/floorplan_optimization/results/current_rtl_openroad_snapshot.json`에 있다.
