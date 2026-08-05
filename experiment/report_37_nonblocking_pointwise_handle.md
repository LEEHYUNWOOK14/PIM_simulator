# 37차 실험 보고서: Nonblocking spatial pointwise handle과 halo 정확도

## 1. 실험 목적

기존 blocking spatial pointwise 실행을 enqueue, wait, readback 세 단계로 분리한다. Transaction이 참조하는 버퍼 lifetime을 handle로 보장하고, expand 출력 3개 row가 bank-side 3×3 depthwise의 앞 2개 output row를 정확히 생성하는지 검증한다.

## 2. 새 API

```cpp
auto handle = pim.enqueuePointwiseSpatialGroups(weights, input, outputChannels);

// 다른 독립 command를 enqueue할 수 있는 구간

pim.waitPointwiseSpatial(handle);
auto output = pim.readPointwiseSpatial(handle);
```

Blocking API는 이제 내부적으로 다음 순서를 호출한다.

```cpp
executePointwiseSpatialGroupsAndRead(...)
  = enqueuePointwiseSpatialGroups(...)
  + waitPointwiseSpatial(...)
  + readPointwiseSpatial(...)
```

## 3. Handle이 소유하는 데이터

`MultiChannelMemorySystem`의 transaction은 enqueue할 때 전달받은 `BurstType*`를 실행이 끝날 때까지 사용한다. 지역 변수를 반환과 동시에 파괴하면 dangling pointer가 된다. 이를 막기 위해 `PointwiseSpatialHandle`이 다음 데이터를 소유한다.

- Compact physical weight tensor
- Position별 input burst tensor
- Position별 raw physical output burst
- Logical output dimension과 batch size
- Wait/consume 상태

Channel 주소는 enqueue 시점에 이미 생성되므로, enqueue 완료 후 PIMKernel의 active channel 목록은 즉시 원래 값으로 복구한다.

## 4. 현재 상태 계약

| 동작 | 결과 |
|---|---|
| Enqueue 후 pending transaction | 존재해야 함 |
| Wait 전 read | 예외 |
| Handle이 outstanding인 동안 두 번째 enqueue | 예외 |
| Wait 두 번 | 두 번째 호출은 no-op |
| Read 후 재read | 예외 |
| 기존 blocking API | 동일 wrapper 동작 |

한 PIMKernel에서 동시에 허용되는 spatial handle은 현재 1개다. Shared weight-buffer layer와 CRF 상태가 전역이기 때문에 다중 handle은 아직 안전하지 않다.

## 5. 재현 명령

```bash
bash experiment/run_nonblocking_pointwise_test.sh
```

스크립트는 hybrid spatial 설정을 적용하고 테스트 후 설정 파일을 원래 bank-side 기본값으로 복구한다.

## 6. 기본 handle 결과

| 항목 | 값 |
|---|---:|
| Position | 2 |
| 입력/출력 channel | 3/3 |
| Enqueue cycle | 82 |
| Wait cycle | 782 |
| 검증 출력 | 6 |
| 총 cycle | 864 |

Enqueue가 0 cycle이 아닌 이유는 shared weight fill과 ready barrier가 enqueue 준비 단계에 포함되기 때문이다. Pointwise compute와 read transaction은 pending 상태로 반환되며 wait에서 drain된다.

## 7. 2개 tile-row halo 검증

| 항목 | 값 |
|---|---:|
| Expand input row | 3 |
| Width | 14 |
| Input/expanded channel | 96/192 |
| Depthwise kernel | 3×3, same padding |
| 검증 output row | 2 |
| 검증 원소 | 5,376 |
| 총 cycle | 37,478 |

Expand weight는 output channel마다 `output % 96` 입력을 선택하도록 구성했다. 따라서 expand 출력은 모두 1이고, depthwise weight 9개도 모두 1이다. Nonblocking pointwise 출력으로 depthwise tap layout을 만든 뒤 bank-side PIM에서 실행했고, 앞 2개 output row의 5,376개 값을 CPU reference와 모두 비교해 통과했다.

## 8. 전체 UIB 회귀

기존 `ActualShapeUibRunsEndToEnd`를 새 blocking wrapper로 다시 실행한 결과는 다음과 같이 유지됐다.

- 전체 정확도 통과
- 총 cycle 214,228
- Expand 88,048 cycle
- Depthwise 20,360 cycle
- Project 103,288 cycle
- Add 1,659 cycle
- ReLU/read 873 cycle

따라서 API 분리가 기존 기능과 timing을 변경하지 않았다.

## 9. 현재 한계

이번 handle은 전체 spatial batch를 enqueue한 뒤 전체 완료를 기다린다. Halo 검증도 expand wait 후 depthwise를 실행했으므로 실제 overlap 성능은 아직 발생하지 않는다. 실제 wavefront에는 다음 추가 분리가 필요하다.

1. Tile-row별 pointwise enqueue
2. Tile-row completion token
3. 최소 3개 expand row를 보관하는 line buffer
4. 특정 row만 기다리는 `waitPointwiseRows`
5. 준비된 output row만 depthwise에 넘기는 partial readback
6. 여러 handle 사이의 CRF와 shared-weight layer ownership

## 10. 다음 단계

다음 구현은 하나의 weight/CRF session 안에서 row range를 반복 enqueue하는 `PointwiseSpatialSession`이다. `enqueueRows(0,3)` 완료 token으로 depthwise output row 0~1을 release하고, 다음 expand row를 enqueue하면서 이전 depthwise row를 실행하는 방식으로 확장한다.
