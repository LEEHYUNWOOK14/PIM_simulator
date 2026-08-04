# MobileNetV4 블록별 PIM 배치표

## 1. 목적

이 문서는 MobileNetV4를 구성하는 대표 블록을 기준으로, 각 블록을 `BANK_SIDE_PIM`, `LOGIC_DIE_PIM`, `HYBRID`, `HOST` 중 어디에 배치할지 정리한 설계 초안이다.

이 표는 다음 작업의 기준이 된다.

- 시뮬레이터에서 연산 경로 분리
- Verilog RTL 모듈 분할
- bank-side / logic-die 성능 비교
- MobileNetV4 추론 블록 단위 기능 검증

## 2. 출처

- MobileNetV4 논문: [MobileNetV4: Universal Models for the Mobile Ecosystem](https://arxiv.org/abs/2404.10518)
- 공식 구현 참고: [tensorflow/models](https://github.com/tensorflow/models)
- 배치 판단은 본 프로젝트의 PIM 아키텍처 설계 해석이다.

## 3. 배치 기준

| 기준 | 의미 |
|---|---|
| `BANK_SIDE_PIM` | bank-local 처리에 적합한 단순 연산 또는 locality 중심 연산 |
| `LOGIC_DIE_PIM` | MAC 집약형, 누산 중심, 제어가 큰 연산 |
| `HYBRID` | 블록 내부에 둘 이상의 성격이 섞여 있어 분리 배치가 유리한 경우 |
| `HOST` | PIM으로 옮기는 이득이 적거나 초기 범위에서 제외할 경우 |

## 4. 블록별 배치표

| MobileNetV4 블록 | 구성 연산 | 대표 배치 | 보조 배치 | 배치 근거 | 1차 구현 여부 |
|---|---|---|---|---|---|
| Stem Conv | `3x3 CONV`, `BN`, `ACT` | `LOGIC_DIE_PIM` | `HOST` | 입력부에서 채널 확장과 초기 특징 추출이 중요하며 MAC 비중이 큼 | 예 |
| Inverted Bottleneck | `1x1 EXPAND`, `DW 3x3`, `1x1 PROJECT`, `ACT`, `RESIDUAL` | `HYBRID` | `BANK_SIDE_PIM`, `LOGIC_DIE_PIM` | 블록 내부에 MAC 집약형과 locality형 연산이 섞여 있음 | 예 |
| Universal Inverted Bottleneck | `CONV`, `DW CONV`, `ACT`, `ADD` 계열 | `HYBRID` | `BANK_SIDE_PIM`, `LOGIC_DIE_PIM` | MobileNetV4 핵심 블록이며 연산 성격이 혼합됨 | 예 |
| Depthwise Separable Stage | `DW 3x3`, `ACT`, `PROJECTION` | `BANK_SIDE_PIM` 우선 | `LOGIC_DIE_PIM` | depthwise는 채널별 독립성이 높아 bank-local 처리에 유리 | 예 |
| Pointwise Projection Stage | `1x1 CONV`, `BN`, `ACT` | `LOGIC_DIE_PIM` | `BANK_SIDE_PIM` | 채널 혼합과 누산이 핵심이라 logic-die가 유리 | 예 |
| Residual Path | `ADD` | `BANK_SIDE_PIM` | `LOGIC_DIE_PIM` | 단순 element-wise라 데이터 이동 비용이 중요 | 예 |
| Activation Path | `RELU`, `H-SWISH`, `CLAMP` | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` | `HYBRID` | 연산이 가볍고 fuse 가능성이 높음 | 예 |
| Downsampling Block | `POOL`, `STRIDE CONV` | `LOGIC_DIE_PIM` | `HOST` | 초기에는 logic-die에서 일괄 처리하는 편이 단순함 | 조건부 |
| Classifier Head | `1x1 CONV`, `AVGPOOL`, `SOFTMAX` | `HOST` 또는 `LOGIC_DIE_PIM` | `HOST` | 초기 범위에서는 host fallback이 안전함 | 조건부 |

## 5. 블록별 상세 설명

### 5.1 Stem Conv

| 항목 | 내용 |
|---|---|
| 역할 | 네트워크 입력에서 저수준 특징 추출 |
| 주요 연산 | `3x3 CONV`, `BN`, `ACT` |
| 권장 배치 | `LOGIC_DIE_PIM` |
| 이유 | 입력 초기단에서 채널 수를 조정하고 MAC 집약도가 높기 때문 |

### 5.2 Inverted Bottleneck

| 항목 | 내용 |
|---|---|
| 역할 | 채널 확장 후 depthwise 처리와 projection을 결합한 핵심 블록 |
| 주요 연산 | `1x1 EXPAND`, `DW 3x3`, `1x1 PROJECT`, `ACT`, `RESIDUAL` |
| 권장 배치 | `HYBRID` |
| 이유 | logic-die가 잘하는 1x1 conv와 bank-side가 잘하는 depthwise/element-wise가 함께 존재함 |

### 5.3 Universal Inverted Bottleneck

| 항목 | 내용 |
|---|---|
| 역할 | MobileNetV4의 대표적 통합 블록 |
| 주요 연산 | `CONV`, `DW CONV`, `ADD`, `ACT` |
| 권장 배치 | `HYBRID` |
| 이유 | 연산 성격이 섞여 있으므로 블록 단위보다 연산 단위 분리가 유리함 |

### 5.4 Depthwise Separable Stage

| 항목 | 내용 |
|---|---|
| 역할 | 채널별 공간 필터링 |
| 주요 연산 | `DW 3x3`, `ACT`, `PROJECTION` |
| 권장 배치 | `BANK_SIDE_PIM` 우선 |
| 이유 | 채널별 독립성이 높아 local data path를 살리기 좋음 |

### 5.5 Pointwise Projection Stage

| 항목 | 내용 |
|---|---|
| 역할 | 채널 혼합 및 차원 축소 |
| 주요 연산 | `1x1 CONV`, `BN`, `ACT` |
| 권장 배치 | `LOGIC_DIE_PIM` |
| 이유 | partial sum 누산과 데이터 재배치가 핵심이라 logic-die가 유리함 |

### 5.6 Residual Path

| 항목 | 내용 |
|---|---|
| 역할 | skip connection 결합 |
| 주요 연산 | `ADD` |
| 권장 배치 | `BANK_SIDE_PIM` |
| 이유 | 단순 element-wise라 이동 비용을 최소화하는 것이 중요함 |

### 5.7 Activation Path

| 항목 | 내용 |
|---|---|
| 역할 | 비선형성 부여 |
| 주요 연산 | `RELU`, `H-SWISH`, `CLAMP` |
| 권장 배치 | `BANK_SIDE_PIM` 또는 `LOGIC_DIE_PIM` |
| 이유 | fuse 여부에 따라 어느 쪽에 두어도 성능상 이점이 있음 |

### 5.8 Downsampling Block

| 항목 | 내용 |
|---|---|
| 역할 | feature map 축소 |
| 주요 연산 | `POOL`, `STRIDE CONV` |
| 권장 배치 | `LOGIC_DIE_PIM` 또는 `HOST` |
| 이유 | 초기에는 별도 제어가 쉬운 쪽으로 두는 것이 구현 안정성이 높음 |

### 5.9 Classifier Head

| 항목 | 내용 |
|---|---|
| 역할 | 최종 클래스 점수 산출 |
| 주요 연산 | `1x1 CONV`, `AVGPOOL`, `SOFTMAX` |
| 권장 배치 | `HOST` 우선 |
| 이유 | 초기 PIM 범위에서 제외해도 전체 구조 검증이 가능함 |

## 6. 1차 구현 우선순위

| 순위 | 블록 | 이유 |
|---|---|---|
| 1 | Residual Path | 구현이 쉽고 정확도 검증이 빠름 |
| 2 | Activation Path | 단순하고 bank-side 비교가 쉬움 |
| 3 | Depthwise Separable Stage | MobileNetV4 구조의 핵심 |
| 4 | Pointwise Projection Stage | logic-die 성능 차이를 보기 좋음 |
| 5 | Inverted Bottleneck | 블록 단위 통합 검증 필요 |
| 6 | Universal Inverted Bottleneck | 가장 중요한 통합 블록 |
| 7 | Stem Conv | 입력단 처리 검증 |
| 8 | Classifier Head | 초기에는 host fallback으로 충분 |

## 7. 배치 결정 규칙

### 7.1 `BANK_SIDE_PIM` 우선 조건

- 연산이 element-wise이다
- 채널 독립성이 높다
- 같은 bank에 머무르며 처리하기 쉽다
- 데이터 이동보다 단순 연산이 중요하다

### 7.2 `LOGIC_DIE_PIM` 우선 조건

- MAC 집약도가 높다
- 여러 bank에서 모은 데이터를 누산해야 한다
- partial sum 관리가 중요하다
- 제어와 누산 자원이 더 필요하다

### 7.3 `HYBRID` 조건

- 블록 내부에 bank-side와 logic-die 성격이 함께 있다
- 단일 위치로 고정하면 손해가 크다
- 연산별 분할이 가능하다

### 7.4 `HOST` 조건

- 초기 구현 복잡도가 높다
- 추론 정확도만 먼저 보고 싶다
- PIM 효과가 크지 않다

## 8. 설계 메타데이터

각 블록은 아래 메타데이터를 가져야 한다.

| 항목 | 설명 |
|---|---|
| `block_name` | 블록 이름 |
| `op_list` | 포함된 연산 목록 |
| `placement` | `BANK_SIDE_PIM`, `LOGIC_DIE_PIM`, `HYBRID`, `HOST` |
| `precision` | `INT8`, `FP16`, `FP32` |
| `input_shape` | 입력 텐서 크기 |
| `output_shape` | 출력 텐서 크기 |
| `fuse_policy` | fusion 허용 여부 |
| `fallback_policy` | host fallback 여부 |
| `source_type` | `논문`, `공식 구현`, `설계 해석` |

## 9. 문서용 결론 문구

> MobileNetV4는 stem, inverted bottleneck, universal inverted bottleneck, depthwise separable stage, pointwise projection, residual path, activation path, classifier head로 나눌 수 있다.  
> 본 프로젝트에서는 depthwise와 element-wise 계열은 bank-side PIM에, 1x1 convolution과 누산 중심 블록은 logic-die PIM에 우선 배치하고, 혼합 블록은 HYBRID로 처리한다.  
> Classifier head와 복잡한 후처리는 초기에는 host fallback으로 두어 기능 검증과 아키텍처 검증을 분리한다.



