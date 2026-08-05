# 36차 실험 보고서: UIB spatial-tile overlap 상한 분석

## 1. 실험 목적

현재 전체 stage barrier로 직렬 실행되는 MobileNetV4 UIB를 spatial tile 단위 wavefront로 바꿨을 때 가능한 overlap 상한을 계산한다. 모델 입력은 추정 latency가 아니라 실제 simulator의 stage별 측정 cycle을 사용한다.

## 2. 실제 stage cycle 계측

`ActualShapeUibRunsEndToEnd`의 다음 경계에서 `PIMKernel::getCycle()`을 기록했다.

| Stage | Placement | 실제 cycle | 비율 |
|---|---|---:|---:|
| Expand pointwise | Logic die | 88,048 | 41.10% |
| Depthwise 3×3 | Bank side | 20,360 | 9.50% |
| Project pointwise | Logic die | 103,288 | 48.21% |
| Residual add | Bank side | 1,659 | 0.77% |
| ReLU + output read | Bank side | 873 | 0.41% |
| 합계 | | 214,228 | 100% |

Stage 합계가 전체 cycle과 정확히 같으므로 계측 경계에서 누락되거나 중복된 simulator cycle은 없다.

## 3. Tile pipeline dependency

입력은 14×14, 총 196 tile이다. 각 stage 총 cycle을 196개 tile에 균등 분배하되 나머지 cycle을 앞 tile부터 1 cycle씩 배분해 stage 합계를 보존했다.

Dependency는 다음과 같다.

```text
expand(y-1..y+1, x-1..x+1)
          ↓ halo ready
depthwise(y,x)
          ↓
project(y,x)
          ↓
add(y,x)
          ↓
relu(y,x)
```

3×3 same-padding depthwise tile은 유효 범위 안의 3×3 expand tile이 모두 끝난 후 시작한다. Expand/project는 같은 logic resource, depthwise/add/ReLU는 같은 bank resource에서 직렬화한다. Stage 내부 tile 순서는 raster order다.

## 4. 재현 명령

```bash
bash experiment/run_uib_tile_pipeline_analysis.sh
```

이 명령은 실제 UIB stage cycle을 다시 측정하고 같은 build의 tile pipeline 단위 테스트를 실행해 CSV를 생성한다.

## 5. 결과

| 항목 | Cycle |
|---|---:|
| 현재 sequential 실행 | 214,228 |
| Tile pipeline 상한 모델 | 191,348 |
| 겹친 cycle | 22,880 |
| 예상 감소율 | 10.68% |
| Logic resource 총 일 | 191,336 |
| Bank resource 총 일 | 22,892 |

첫 depthwise tile은 cycle 7,200에 시작할 수 있다. 마지막 expand tile은 cycle 88,048에 끝나므로 depthwise의 대부분을 expand와 겹칠 수 있다. 첫 project는 stage-order 정책 때문에 cycle 88,048에 시작한다.

최종 191,348 cycle은 logic resource work 191,336보다 12 cycle만 크다. 따라서 이 schedule에서는 bank-side가 아니라 두 pointwise stage가 critical path다.

## 6. 출력 예시와 주석

```text
HIERARCHY_TILE_PIPELINE_RESULT
sequential_cycles[214228]
pipelined_cycles[191348]
overlap_gain_cycles[22880]
first_depthwise_start[7200]
last_expand_end[88048]
first_project_start[88048]
logic_resource_cycles[191336]
bank_resource_cycles[22892]
```

- `pipelined_cycles`: 정의된 dependency와 자원 제약에서 계산한 마지막 tile 완료 cycle이다.
- `overlap_gain_cycles`: sequential cycle에서 pipeline cycle을 뺀 값이다.
- `first_depthwise_start < last_expand_end`: logic expand와 bank depthwise overlap이 실제 schedule에 존재한다는 뜻이다.
- `logic_resource_cycles`: expand와 project cycle 합이다.
- `bank_resource_cycles`: depthwise, add, ReLU cycle 합이다.

## 7. 해석

### 7.1 현재 전체 barrier의 잠재 비용

현재 PIMKernel adapter는 expand 전체를 `runPIM()`으로 drain한 뒤 depthwise를 시작한다. Tile halo가 준비되는 cycle 7,200부터 depthwise를 내보낼 수 있다면 bank resource의 22,880 cycle 대부분을 logic execution 뒤에 숨길 수 있다.

### 7.2 Logic PCU가 overlap 후 critical path다

Bank-side stage를 완전히 겹쳐도 logic work가 191,336 cycle 남는다. 이후 성능 개선은 queue bypass보다 logic PCU 수, logic bandwidth, project mapping 개선의 영향이 더 크다.

### 7.3 이 값은 구현 전 상한이다

191,348 cycle은 실제 simulator 실행 결과가 아니다. 다음 비용을 아직 포함하지 않는다.

- Tile별 command enqueue 및 barrier 비용
- Logic↔bank 중간 tensor buffer 포트와 용량
- 3×3 line buffer 또는 halo storage
- Interconnect에서 weight/input/output가 동시에 이동할 때의 경합
- Tile별 stage 비용의 실제 불균형
- Refresh와 DRAM row-state 변화

따라서 10.68%는 보장 성능이 아니라 nonblocking tile scheduler가 도달해야 할 구현 목표선이다.

## 8. 구현 요구사항

1. `executePointwise...AndRead`를 enqueue와 wait/readback 단계로 분리한다.
2. Tile 또는 tile-row completion event를 제공한다.
3. Depthwise는 필요한 세 input row의 expand completion을 기다린다.
4. 전체 tensor barrier 대신 tile dependency token을 사용한다.
5. 중간 activation은 최소 3개 expand row를 보관할 line buffer가 필요하다.
6. Bank/logic command가 함께 ready이면 `HIERARCHY_READY_BYPASS` 정책을 적용한다.
7. 실제 실행에서 source별 wait, bypass, buffer occupancy와 최종 정확도를 검증한다.

## 9. 다음 단계

다음 기술 구현은 PIMKernel의 pointwise spatial 실행을 `enqueuePointwiseTile`, `waitPointwiseTile`, `readPointwiseTile`로 분리하는 nonblocking API 설계다. 첫 구현은 14×14 전체가 아니라 2개 tile-row만 사용해 halo dependency와 출력 정확도를 검증한 뒤 전체 UIB로 확장한다.
