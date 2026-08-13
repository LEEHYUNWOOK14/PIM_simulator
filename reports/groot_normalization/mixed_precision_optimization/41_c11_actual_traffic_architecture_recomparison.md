# C11 Actual-traffic Architecture Recomparison

## Decision

현재 구현된 단일-row, 4-lane/bank C11은 **NO-GO**다. 정확도는 해결했지만 GPU보다 빠르지 않으므로 production replay/DRAM write-back 확장 조건을 충족하지 못한다.

| architecture | latency | speedup vs GPU | logical traffic | accuracy evidence |
|---|---:|---:|---:|---|
| GPU | 3.121ms | 1.000x | 86,212,608B | PyTorch golden, CUDA event 측정 |
| Bank-only PIM | 62.394ms | 0.050x | 130,969,088B | bank arithmetic 검증, scalar offload 모델 |
| Logic-only PIM | 12.564ms | 0.248x | 172,425,216B | 기존 throughput 모델, 정확도 미검증 |
| Hierarchical PIM C11 | 59.534ms | 0.052x | 130,969,088B | C11 full RTL 6/6, 1,909,248 elements 통과 |

현재 C11의 weighted total은 269 calls, 2,136,209 cycles다. apply 임계경로 27.85ns에서 35.907MHz를 적용했고 on-die partial/scalar link 40.08µs를 더했다. 같은 직렬 구조의 GPU break-even clock은 약 693.3MHz이므로 연산기 stage만 미세 최적화해서는 도달할 수 없다.

## 왜 정확도 향상만으로 성능이 오르지 않는가

C11 scalar는 정확한 FP32 NR2를 위해 dependent operation을 순차 수행한다. 파이프라인은 clock period를 줄이지만 한 row의 cycle latency는 늘어난다. 현재 top은 다음 row를 이전 row가 끝날 때까지 시작하지 않으므로 이 latency를 숨기지 못한다.

따라서 다음 성능 단계는 arithmetic 미세 최적화보다 아래 구조가 우선이다.

1. 여러 row context를 동시에 유지해 reduce/scalar/apply를 겹친다.
2. scalar engine을 복제해 NR2 service throughput을 높인다.
3. bank당 lane을 4에서 8 또는 16으로 늘려 reduction/apply vector 수를 줄인다.
4. 그 뒤 FP32 multiplier를 추가 분할해 목표 clock을 timing-close한다.

## Multi-row projection

아래는 아직 구현되지 않은 projection이다. 실제 C11 trace에서 얻은 startup 111 cycles를 유지하고, steady-state row II를

```text
max(vectors_per_bank, ceil(60 scalar service cycles / scalar engines))
```

로 모델링했다. traffic과 on-die link는 현재 비교와 동일하다.

| lanes/bank | scalar engines | clock | projected latency | speedup vs GPU | 판정 |
|---:|---:|---:|---:|---:|---|
| 4 | 4 | 100MHz | 3.769ms | 0.828x | NO-GO |
| 8 | 4 | 100MHz | 2.366ms | 1.319x | projected GO |
| 8 | 8 | 100MHz | 2.054ms | 1.520x | projected GO |
| 16 | 8 | 35.9MHz | 3.839ms | 0.813x | NO-GO |
| 16 | 8 | 50MHz | 2.768ms | 1.127x | projected GO |
| 16 | 16 | 50MHz | 2.352ms | 1.327x | projected GO |

가장 현실적인 다음 후보는 **16 lanes/bank + 8 scalar engines + multi-row overlap + 50MHz**다. 현재 27.85ns apply 경로를 20ns 이하로 줄여야 하며, lane 4배 복제로 인한 면적·전력·routing 비용을 반드시 함께 검증해야 한다. 대안은 8 lanes/bank + 4 scalar engines + 100MHz지만 현재 Sky130 arithmetic timing과 거리가 더 크다.

## 설계로 키울 수 있는 것과 없는 것

- 설계로 정확도를 키울 수 있다: accumulation precision, rounding 위치, NR 횟수, variance clamp가 직접 결정한다.
- 설계로 핵심 연산 처리량을 키울 수 있다: lane 폭, row overlap, scalar replication, pipeline/FIFO가 결정한다.
- 모델 자체의 학습 정확도를 RTL이 높이는 것은 아니다. 여기서 정확도는 PyTorch normalization 결과를 보존하는 numerical fidelity다.
- end-to-end 이득은 연산기만으로 보장되지 않는다. replay, write-back, bank conflict, link, area/power가 포함되어야 한다.

## Gate

production replay/write-back RTL 확장은 다음을 모두 만족할 때만 시작한다.

1. 6개 actual tensor full RTL accuracy PASS — **완료**
2. multi-row/lane/scalar 구조의 RTL cycle 검증
3. 목표 clock timing closure
4. actual traffic 포함 GPU 대비 speedup > 1
5. 면적·전력 budget 수용

현재는 1번만 완료됐고 2~5번은 미완료다. 따라서 production 확장은 보류한다.

## 산출물

- `reports/groot_normalization/results/mixed_precision_c11_architecture_comparison/architecture_comparison.csv`
- `reports/groot_normalization/results/mixed_precision_c11_architecture_comparison/c11_workload_cycles.csv`
- `reports/groot_normalization/results/mixed_precision_c11_architecture_comparison/multirow_parallelism_dse.csv`
- `reports/groot_normalization/results/mixed_precision_c11_architecture_comparison/comparison.json`

재현:

```bash
python tools/compare_c11_actual_groot_architectures.py
```
