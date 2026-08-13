# Phase 5 — 정규화 스칼라 Bank-PCU 브로드캐스트 RTL

## 이번 작업의 범위

Logic PCU가 계산한 `mode/tag/mean/inv_std`를 활성 Bank-PCU 집합에 전달하는 ready/valid 브로드캐스트 블록을 구현했다. 이 단계는 raw activation→scalar 경로와 기존 Bank-PCU affine microprogram 사이를 잇기 위한 첫 번째 반환 경로다.

## 구현

- RTL: `rtl/normalization_scalar_broadcast.sv`
- 은행별 `pending` 비트로 독립적인 backpressure를 지원한다.
- 각 대상 은행은 정확히 한 번 handshake한 뒤 pending 집합에서 제거된다.
- 가장 느린 대상 은행이 받을 때까지 입력을 backpressure하고 payload를 유지한다.
- target mask가 0인 요청은 출력하지 않고 sticky `zero_target_error_o`를 설정한다.
- 현재 구현은 마지막 은행 전달 다음 cycle에 새 입력을 받을 수 있어 연속 요청 사이에 1-cycle bubble이 있다.

## 기능 검증

실행:

```sh
bash verification/groot_normalization/run_normalization_scalar_broadcast_test.sh
```

결과:

```text
NORMALIZATION_SCALAR_BROADCAST_TB PASS banks=4 independent_stalls=1 exactly_once=1 cycles=16
```

검증 항목은 source backpressure, 서로 다른 은행 준비 시점, stall 중 payload 안정성, 대상 은행별 정확히 1회 전달, 비대상 은행 0회 전달, zero-mask 오류다.

## generic synthesis

실행:

```sh
bash verification/groot_normalization/run_normalization_scalar_broadcast_synthesis.sh
```

| Banks | Generic cells | Wire bits | Port bits | Yosys strict check |
|---:|---:|---:|---:|:---:|
| 4 | 75 | 335 | 262 | PASS |
| 8 | 99 | 567 | 470 | PASS |
| 16 | 147 | 1,031 | 886 | PASS |

16-bank 기준 raw-to-scalar top의 953,623 generic cells와 비교하면 이 독립 블록은 147 cells다. 단, 이는 generic cell proxy이며 배선 fanout·buffering·물리 배치 비용을 나타내지 않는다.

## 판정과 제한

- **RTL_MEASURED:** 독립 지연을 갖는 은행들에 scalar payload를 손실·중복 없이 배포할 수 있다.
- **아직 E2E 아님:** 현재 raw-to-scalar top의 응답에는 해당 row의 target mask가 동반되지 않는다. 여러 scalar engine이 응답 순서를 바꿀 수 있으므로 config 순서만으로 mask를 재결합하면 안 된다.
- 다음 연결 단계에서는 `tag→target mask` context를 보존하거나 mask를 reduction/scalar pipeline에 직접 전달해야 한다.
- scalar를 Bank-PCU SRF에 쓰는 명령 변환, activation replay, gamma/beta 공급, affine 결과 수집은 아직 연결되지 않았다.

## 다음 작업

row context mask를 응답 tag와 안전하게 재결합하는 context table을 구현한 뒤, raw-to-scalar top과 본 브로드캐스트를 통합한다. 그 다음 각 bank의 scalar SRF write 및 기존 affine normalization microprogram으로 연결한다.
