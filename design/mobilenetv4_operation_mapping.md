# MobileNetV4 연산 처리 기능표

## 1. 문서 목적

이 문서는 MobileNetV4 추론용 연산을 정리하고, 각 연산의 출처를 명시하며, bank-side PIM과 logic-die PIM 중 어디에 둘지 설계하기 위한 초안이다.

이 문서는 다음 두 종류의 근거를 분리해서 적는다.

- `논문/공식 구현 근거`: MobileNetV4 원문과 공식 구현에서 확인되는 연산
- `설계 해석`: PIM 시뮬레이터와 하이브리드 아키텍처를 위해 추가한 배치 판단

## 2. 출처

### 2.1 논문 근거

- MobileNetV4 원문: [MobileNetV4: Universal Models for the Mobile Ecosystem](https://arxiv.org/abs/2404.10518)

### 2.2 공식 구현 근거

- TensorFlow Model Garden: [tensorflow/models](https://github.com/tensorflow/models)

## 3. 출처 구분 규칙

| 표기 | 의미 |
|---|---|
| `논문` | MobileNetV4 원문에 근거한 항목 |
| `공식 구현` | TensorFlow 계열 공식 구현 확인이 필요한 항목 |
| `설계 해석` | 본 프로젝트의 PIM 구조를 위해 추가한 판단 |

## 4. MobileNetV4 연산 기능표

| 연산 | 출처 | MobileNetV4 내 역할 | 대표 위치 | bank-side 적합성 | logic-die 적합성 | 구현 우선순위 | 비고 |
|---|---|---|---|---:|---:|---|---|
| `1x1 CONV` | 논문, 공식 구현 | 채널 혼합, pointwise projection | `LOGIC_DIE_PIM` | 중 | 높음 | 예 | 핵심 MAC 연산 |
| `Depthwise 3x3 CONV` | 논문, 공식 구현 | 채널별 공간 필터링 | `BANK_SIDE_PIM` 또는 `HYBRID` | 높음 | 중 | 예 | locality가 좋음 |
| `Inverted Bottleneck` | 논문 | MobileNet 계열 핵심 블록 | `HYBRID` | 중 | 높음 | 예 | 내부에 conv, activation 포함 |
| `Universal Inverted Bottleneck` | 논문 | MobileNetV4 핵심 블록 | `HYBRID` | 중 | 높음 | 예 | 블록 단위 설계 필요 |
| `Residual Add` | 논문, 공식 구현 | skip connection 결합 | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` | 높음 | 높음 | 예 | element-wise |
| `ReLU` | 논문, 공식 구현 | activation | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` | 높음 | 높음 | 예 | 단순 비교/클리핑 |
| `H-Swish` | 논문, 공식 구현 | activation | `LOGIC_DIE_PIM` 우선 | 중 | 높음 | 조건부 | model variant에서 중요 가능 |
| `BatchNorm` | 논문, 설계 해석 | 정규화 | `FUSE` 또는 `HOST` | 낮음 | 중 | 아니오 | 추론 시 folding 권장 |
| `MaxPool` | 논문, 공식 구현 | downsampling | `LOGIC_DIE_PIM` 또는 `HOST` | 중 | 중 | 조건부 | 구현 난이도 검토 필요 |
| `AvgPool` | 논문, 공식 구현 | downsampling | `LOGIC_DIE_PIM` 또는 `HOST` | 중 | 중 | 조건부 | 구현 난이도 검토 필요 |
| `Clamp` | 설계 해석 | activation 후 제한 | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` | 높음 | 높음 | 조건부 | INT8 경로에서 유용 |
| `Shift` | 설계 해석 | quantization / rescale | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` | 높음 | 높음 | 조건부 | post-process 경로 |
| `Rescale` | 설계 해석 | quantization 후처리 | `LOGIC_DIE_PIM` | 중 | 높음 | 조건부 | accumulator 정리 |
| `Softmax` | 논문, 공식 구현 | classifier head | `HOST` | 낮음 | 낮음 | 아니오 | 초기 범위 제외 권장 |
| `GEMM` | 설계 해석 | 확장성 확보용 일반 행렬곱 | `LOGIC_DIE_PIM` | 중 | 높음 | 조건부 | 향후 모델 확장 대비 |

## 5. 연산별 상세 정의

### 5.1 `1x1 CONV`

| 항목 | 내용 |
|---|---|
| 출처 | 논문, 공식 구현 |
| 역할 | 채널 혼합, pointwise projection |
| 입력 | activation tensor, weight tensor |
| 출력 | activation tensor |
| 권장 위치 | `LOGIC_DIE_PIM` |
| 이유 | MAC 집약도가 높고 partial sum 누산 자원이 중요함 |

### 5.2 `Depthwise 3x3 CONV`

| 항목 | 내용 |
|---|---|
| 출처 | 논문, 공식 구현 |
| 역할 | 채널별 공간 필터링 |
| 입력 | per-channel activation, depthwise weight |
| 출력 | per-channel feature map |
| 권장 위치 | `BANK_SIDE_PIM` 우선 |
| 이유 | 채널 독립성이 높고 bank-local 처리에 적합함 |

### 5.3 `Inverted Bottleneck`

| 항목 | 내용 |
|---|---|
| 출처 | 논문 |
| 역할 | MobileNet 계열의 기본 블록 중 하나 |
| 구성 | 확장, depthwise conv, projection의 조합 |
| 권장 위치 | `HYBRID` |
| 이유 | 내부에 서로 다른 성격의 연산이 섞여 있기 때문 |

### 5.4 `Universal Inverted Bottleneck`

| 항목 | 내용 |
|---|---|
| 출처 | 논문 |
| 역할 | MobileNetV4에서 제안한 핵심 블록 계열 |
| 구성 | conv, depthwise, activation, residual 계열 조합 |
| 권장 위치 | `HYBRID` |
| 이유 | 블록 내부 연산을 위치별로 분리하는 편이 효율적임 |

### 5.5 `Residual Add`

| 항목 | 내용 |
|---|---|
| 출처 | 논문, 공식 구현 |
| 역할 | skip connection 결합 |
| 권장 위치 | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` |
| 이유 | 단순 element-wise 연산이라 데이터 이동 비용이 핵심 |

### 5.6 `ReLU`

| 항목 | 내용 |
|---|---|
| 출처 | 논문, 공식 구현 |
| 역할 | activation |
| 권장 위치 | 양쪽 모두 가능 |
| 이유 | sign-bit 검사와 clamping만 필요함 |

### 5.7 `H-Swish`

| 항목 | 내용 |
|---|---|
| 출처 | 논문, 공식 구현 |
| 역할 | 비선형 activation |
| 권장 위치 | `LOGIC_DIE_PIM` 우선 |
| 이유 | ReLU보다 산술과 제어가 복잡함 |

### 5.8 `BatchNorm`

| 항목 | 내용 |
|---|---|
| 출처 | 논문, 설계 해석 |
| 역할 | 정규화 |
| 권장 위치 | `FUSE` 또는 `HOST` |
| 이유 | 추론 시 folding이 일반적이며 별도 PIM 연산으로 둘 필요가 적음 |

## 6. 1차 구현 우선순위

| 순위 | 연산 | 출처 | 이유 |
|---|---|---|---|
| 1 | `Residual Add` | 논문, 공식 구현 | 단순하고 검증이 쉬움 |
| 2 | `ReLU` | 논문, 공식 구현 | 기능 확인용으로 적합 |
| 3 | `Depthwise 3x3 CONV` | 논문, 공식 구현 | MobileNetV4 구조상 핵심 |
| 4 | `1x1 CONV` | 논문, 공식 구현 | 성능 핵심, logic-die 대표 대상 |
| 5 | `H-Swish` | 논문, 공식 구현 | 모델 정확도 유지에 중요 |
| 6 | `Residual Add + Activation FUSE` | 설계 해석 | 메모리 이동 감소 효과가 큼 |
| 7 | `MaxPool / AvgPool` | 논문, 공식 구현 | 후속 확장 기능 |
| 8 | `Softmax` | 논문, 공식 구현 | 초기 범위 밖 |

## 7. 위치 선택 규칙

### 7.1 `BANK_SIDE_PIM`에 보낼 조건

- 연산이 단순 element-wise이다
- 동일 bank 내부에서 충분히 처리 가능하다
- 데이터 이동량이 적다
- 높은 제어 복잡도가 없다

### 7.2 `LOGIC_DIE_PIM`에 보낼 조건

- 연산이 MAC 집약적이다
- 여러 bank의 데이터를 모아야 한다
- partial sum 누산이 크다
- 더 큰 제어 로직이 필요하다

### 7.3 `HOST`로 보낼 조건

- 초기 구현이 복잡하다
- 정확도 검증을 먼저 하고 싶다
- 성능보다 기능 검증이 우선이다

## 8. MobileNetV4 블록 기준 실행 흐름 예시

| 블록 단계 | 연산 | 권장 위치 | 출처 |
|---|---|---|---|
| 입력 준비 | `LOAD / TILE` | `HOST` | 설계 해석 |
| 채널 확장 | `1x1 CONV` | `LOGIC_DIE_PIM` | 논문, 공식 구현 |
| 공간 필터 | `Depthwise 3x3 CONV` | `BANK_SIDE_PIM` | 논문, 공식 구현 |
| 활성화 | `ReLU` / `H-Swish` | 양쪽 가능 | 논문, 공식 구현 |
| 채널 혼합 | `1x1 CONV` | `LOGIC_DIE_PIM` | 논문, 공식 구현 |
| residual merge | `Residual Add` | `BANK_SIDE_PIM` 우선 | 논문, 공식 구현 |
| 후처리 | `Clamp`, `Shift`, `Rescale` | 양쪽 가능 | 설계 해석 |

## 9. 설계 메타데이터

각 연산은 아래 메타데이터를 가진다.

| 항목 | 설명 |
|---|---|
| `op_type` | 연산 종류 |
| `placement` | `BANK_SIDE_PIM`, `LOGIC_DIE_PIM`, `HOST` |
| `precision` | `INT8`, `FP16`, `FP32` |
| `input_shape` | 입력 텐서 크기 |
| `output_shape` | 출력 텐서 크기 |
| `reuse_factor` | 데이터 재사용 정도 |
| `bandwidth_need` | 필요한 대역폭 |
| `latency_model` | cycle 기반 지연 모델 |
| `fuse_group` | fuse 가능한 연산 묶음 |
| `fallback_policy` | PIM 미지원 시 대체 경로 |
| `source_type` | `논문`, `공식 구현`, `설계 해석` |

## 10. 문서용 결론 문구

> MobileNetV4의 연산 구성은 논문과 공식 구현을 기준으로 `1x1 CONV`, `Depthwise 3x3 CONV`, `Residual Add`, `ReLU`, `H-Swish`, `Pooling` 계열로 정리할 수 있다.  
> 본 프로젝트에서는 이를 바탕으로 `bank-side PIM`과 `logic-die PIM`을 분리한 하이브리드 구조를 설계하며, `BatchNorm`은 folding을 우선 적용하고 `Softmax`는 초기 범위에서 제외한다.  
> 단, `BANK_SIDE_PIM`과 `LOGIC_DIE_PIM`의 배치는 MobileNetV4 원문에 명시된 내용이 아니라 본 프로젝트의 설계 해석이다.



