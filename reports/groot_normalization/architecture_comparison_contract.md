# GR00T Normalization Architecture Comparison Contract

## 1. 공통 workload 단위

모든 구조는 `gr00t_normalization_profile_manifest.csv`의 동일한 invocation을 처리한다. 한 invocation은 `rows × hidden_size` tensor 하나의 LayerNorm 또는 RMSNorm이다.

비교 단위는 세 단계로 구분한다.

1. `per_row`: 한 normalization row
2. `per_invocation`: 동일 shape의 모든 row
3. `per_model`: manifest의 invocation 수를 적용한 projected 합계

## 2. 공통 수치 계약

- canonical golden: FP32 accumulation 및 FP32 normalization
- 현재 simulator datapath: FP16
- 공식 GR00T dtype: BF16
- statistic scalar: 초기 비교 모델에서 FP32 4 byte
- LayerNorm 통계: row당 SUM, SUMSQ 두 개
- RMSNorm 통계: row당 SUMSQ 한 개
- RSQRT: row당 한 번
- epsilon: manifest 값 사용

FP16과 BF16 결과는 별도 case로 다룬다. dtype conversion이 필요한 case는 conversion cycle/traffic/energy를 0으로 숨기지 않는다.

## 3. 공통 latency 경계

```text
T_total = T_prepare
        + T_local_reduce
        + T_partial_transfer
        + T_global_reduce
        + T_finalize
        + T_rsqrt
        + T_broadcast_or_return
        + T_apply
        + T_queue_sync
        + T_mode_switch
```

- `T_finalize`: mean/variance 또는 mean-square와 epsilon 계산
- 겹쳐 실행할 수 있는 단계는 overlap 조건을 별도 기록한다.
- 기본 결과는 overlap 없는 보수적 합계와 허용된 overlap 결과를 모두 출력한다.
- projected model latency는 profile별 값을 계산한 뒤 invocation 수를 곱한다.

## 4. 공통 traffic 경계

```text
B_tensor = rows × hidden_size × dtype_bytes
B_global_stats = rows × statistic_count × scalar_bytes
B_bank_partials = rows × statistic_count × active_banks × scalar_bytes
```

traffic은 다음 링크별로 따로 기록한다.

- Bank local DRAM ↔ Bank-PCU
- Bank-PCU → Logic-PCU
- Logic-PCU → Bank-PCU
- HBM/PIM domain → GPU/host
- GPU/host → HBM/PIM domain

logical payload, padded/burst traffic 및 protocol overhead를 섞지 않는다.

## 5. Case A — GPU baseline

### A1. Full-tensor GPU offload

```text
HBM/PIM → GPU: input + affine parameter
GPU: reduction + finalize + RSQRT + apply
GPU → HBM/PIM: output
```

포함 비용:

- 양방향 tensor transfer
- queue 및 kernel launch
- GPU normalization kernel
- synchronization

### A2. Partial-statistic GPU offload

```text
Bank-PCU: local SUM/SUMSQ
Bank-PCU → GPU: bank partial statistics
GPU: global reduction + finalize + RSQRT
GPU → Bank-PCU: row scalar
Bank-PCU: apply
```

GPU 실측 환경이 없으면 A1/A2는 parameter sweep 결과로만 표시하고 `MEASURED`로 표기하지 않는다.

## 6. Case B — Bank-only PIM

```text
Bank-PCU: local reduction
host/GPU: global reduction + finalize + RSQRT
Bank-PCU: scalar 수신 + apply
```

Bank-only라는 이름은 host/GPU scalar fallback이 없다는 뜻이 아니다. 현재 ISA로 완전한 normalization이 불가능하므로 fallback 비용을 반드시 포함한다.

## 7. Case C — Logic-only PIM

```text
Bank/HBM → Logic-PCU: 원본 tensor 및 affine parameter
Logic-PCU: local/global reduction + finalize + RSQRT + apply
Logic-PCU → Bank/HBM: output tensor
```

Logic-only는 scalar만 이동하는 구조가 아니다. 원본 tensor 이동 비용과 Logic-PCU vector throughput을 포함한다.

## 8. Case D — Hierarchical PIM

```text
Bank-PCU: local SUM/SUMSQ
Bank-PCU → Logic-PCU: partial statistics
Logic-PCU: global reduction + finalize + RSQRT
Logic-PCU → Bank-PCU: mean/inv_std 또는 inv_rms
Bank-PCU: normalize/scale/bias apply
```

필수 모델 항목:

- bank mapping과 active bank 수
- partial FIFO 및 cross-bank contention
- reduction tree/accumulator latency
- row tag/epoch ordering
- RSQRT latency와 initiation interval
- broadcast latency
- Bank-PCU apply throughput

## 9. 보조 case

- `D_HOST_RSQRT`: hierarchical reduction 후 host/GPU RSQRT
- `D_LUT`: Logic-PCU LUT-only RSQRT
- `D_NR1`: LUT seed + Newton-Raphson 1회
- `D_NR2`: LUT seed + Newton-Raphson 2회
- `D_EXACT_PROXY`: 정확한 RSQRT IP 상당 latency/area parameter

## 10. 공정성 규칙

1. 네 case에서 workload, invocation, dtype 및 clock 가정을 동일하게 유지한다.
2. GPU kernel 시간만 PIM end-to-end 시간과 비교하지 않는다.
3. Bank/Logic 구조의 on-die transfer도 0 cycle/0 energy로 두지 않는다.
4. area가 없는 analytical unit은 `area unknown`으로 표시한다.
5. 실제 측정, RTL 측정, 공식 사양, derived 값과 가정을 구분한다.
6. 같은 profile을 한 번 실행하고 호출 수를 곱한 값은 `PROJECTED`로 표시한다.
7. GPU가 없는 현재 PC의 CPU PyTorch 값은 GPU baseline으로 사용하지 않는다.

## 11. 비교 출력 schema

각 결과 행은 최소 다음 필드를 갖는다.

```text
case, profile_id, dtype, rows, hidden_size, banks, bank_pcus, logic_pcus,
clock_mhz, latency_ns, cycles, tensor_bytes, partial_bytes, return_bytes,
queue_ns, energy_nj, area_um2, evidence_class, assumptions_id
```

`energy_nj`와 `area_um2`에 근거가 없으면 0 대신 null을 사용한다.
