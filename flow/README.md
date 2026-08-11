# OpenROAD sky130hd Full-PIM integration flow

이 디렉터리는 `full_pim_system_top`의 RTL-to-GDS 통합 검증 설정을 포함한다.

물리 증명 인스턴스는 다음 최소 파라미터 구성을 사용한다.

- 1 channel, 1 bank, 1 bank-PIM block, 1 logic PCU
- FP16 16-bit datapath
- 1 row, 1 column, CRF depth 2, shared weight buffer 16 bytes
- bank-side PIM, logic PCU, epoch/coalescer, shared weight, cross-channel reduction,
  bank/host result router 계층은 모두 유지

Windows에서 다음 명령으로 실행한다.

```powershell
.\flow\run_flow.ps1
```

기본 환경은 WSL `Ubuntu`, ORFS
`/home/chandler/OpenROAD-flow-scripts`, Yosys
`/home/chandler/.local/oss-cad-suite/bin/yosys`, OpenROAD
`/home/chandler/.local/openroad-pi/usr/bin/openroad`이다. 로컬 OpenROAD와 최신 ORFS의
Tcl API 차이는 `openroad_compat.tcl`에서 제한적으로 처리한다.

런처는 최종 `6_final.gds`를 `output/output.gds`로 복사하고 KLayout batch 검사로
top cell `full_pim_system_top`과 non-empty bbox를 확인한다.

기본값 `DetailedRouteEndIteration=0`은 통합 검증 시간을 제한하기 위한 설정이다.
따라서 생성된 GDS는 DRC-clean/signoff 산출물이 아니다. 배선 최적화를 계속하려면
해당 값을 늘리고 DRC·antenna·timing closure를 별도로 수행해야 한다.
