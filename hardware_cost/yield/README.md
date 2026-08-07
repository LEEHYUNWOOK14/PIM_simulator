# Yield 파이프라인

## 목적

좋은 HBM 스택 하나를 얻을 확률과 상대적인 good-stack 비용을 계산한다. 제조사 실제 수율은 비공개이므로 `best/nominal/worst` 및 Monte Carlo 범위만 제공한다.

## 모델 근거

다이 수율에는 결함이 독립·균일하다고 보는 Poisson 모델과 결함 clustering을 허용하는 negative-binomial 모델을 모두 제공한다.

```text
Poisson:          Y_die = exp(-D0 × A)
Negative binomial:Y_die = (1 + D0×A/alpha)^(-alpha)
```

3D stack 연구에서는 개별 die뿐 아니라 interconnect/TSV 및 bonding 수율을 별도로 고려하고 known-good-die(KGD), pre-bond test와 redundancy가 중요하다고 설명한다. 이에 따라:

```text
Y_stack = Y_base × product(Y_DRAM_i)
          × Y_bond^N_interfaces
          × Y_TSV
          × Y_assembly

relative_good_stack_cost = accumulated_input_resource / Y_stack
```

TSV가 독립 실패한다고 가정하는 단순 모델은 큰 TSV 수에서 지나치게 비관적일 수 있으므로, 기본은 TSV 그룹 수율 또는 beta-binomial/cluster 범위를 사용한다. 독립 TSV 식을 선택하면 경고를 출력한다.

## KGD와 redundancy

KGD를 사용하면 불량 die가 적층 전에 제거되지만 테스트 비용과 escape probability가 생긴다. spare TSV/bank redundancy는 결함 허용도를 높이지만 면적과 테스트 비용을 증가시킨다. 기본 모델은 다음을 따로 보고한다.

- pre-bond screened die yield
- test escape probability
- bond/interface yield
- TSV group yield
- post-bond stack yield
- expected attempts per good stack `1/Y_stack`

## 입력 제한

결함밀도 `D0`, clustering `alpha`, bonding/assembly yield는 제조사 공개값이 아니다. 모든 기본값은 `illustrative`이며 넓은 범위를 갖는다. 이 모델로 특정 제조사의 실제 수율이나 원가를 주장해서는 안 된다.

## 검증

- 모든 확률은 `[0,1]`
- 수율이 0이면 비용을 무한대로 조용히 출력하지 않고 실패
- 완전수율 입력이면 `Y_stack=1`
- 다른 조건이 같으면 die/interface 증가에 따라 수율이 증가할 수 없음
- Poisson 식의 해석값과 구현 비교
- Monte Carlo 분위수 순서와 seed 재현성
