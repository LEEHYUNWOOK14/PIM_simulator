# 통합 비용·효율 파이프라인

## 목적

서로 다른 단위의 area, package, yield, power/performance, thermal 다섯 분석 결과를 잃지 않고 비교표, 정규화 지수, Pareto frontier 및 불확실성 범위로 통합한다.

## 기준 설계

기준 설계는 기본 `1-stack 8Hi HBM2, PIM off 또는 지정 baseline`이다. candidate와 baseline은 같은 workload, 공정 가정, 전력 범위를 사용해야 한다. 그렇지 않으면 비교를 거부하거나 `non_comparable`로 표시한다.

## 통합 규칙

- 원 물리량을 항상 보존한다.
- 작은 값이 좋은 비용축만 cost index로 사용한다.
- 성능은 큰 값이 좋으므로 별도 normalized performance로 둔다.
- yield는 수율 자체가 아니라 good-stack resource multiplier `1/Y`를 비용축으로 사용한다.
- thermal은 온도상승/허용 온도상승으로 정의한 냉각부담을 기준 설계 대비 정규화한다.
- energy와 thermal은 상관된 축이므로 개별 결과와 가중치 민감도를 반드시 함께 본다.
- 열 제한을 넘은 설계는 순위는 보이되 feasible frontier에서 제외한다.
- workload 최소 메모리 용량을 만족하지 못한 설계도 같은 방식으로 feasible frontier와 최상위 순위 확률에서 제외한다.
- 기본 가중치는 정책 선택이지 논문/제조사 사실이 아님을 표시한다.

## 불확실성

각 추정 입력의 범위에서 seeded Monte Carlo를 수행한다. 독립 가정이 부적절할 수 있는 die/bond/TSV 수율은 correlation group을 둘 수 있다. 출력은 평균만이 아니라 P5/P50/P95, 최악/최선, 순위 역전 확률을 포함한다.

## Pareto 판정

설계 A가 B보다 모든 비용축에서 작거나 같고 성능에서 크거나 같으며 최소 한 축에서 엄격히 우수하면 A가 B를 지배한다. 비지배 설계만 Pareto frontier에 포함한다.

## 출력

- `integrated_metrics.json`
- `design_comparison.csv`
- `pareto_frontier.csv`
- `uncertainty_samples.csv`
- `hardware_cost_report.md`
- `parameter_provenance.json`

보고서는 각 결론 바로 옆에 source ID 또는 입력 classification을 표시하며, 공개 사실과 프로젝트 추정의 결합으로 만들어진 derived 결과를 제조사 사실로 표현하지 않는다.
