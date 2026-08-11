# Phase 2 보고서: 네 구조의 공통 비교 계약

- 수행일: 2026-08-11
- 산출물: `architecture_comparison_contract.md`, `common_model_parameters.json`
- 판정: **PASS — 공통 비용 경계와 parameter schema 확정**

## 1. 결과

GPU baseline, Bank-only PIM, Logic-only PIM, Hierarchical PIM을 같은 workload로 비교하기 위한 데이터 이동 경계, latency 식, traffic 식 및 결과 schema를 확정했다.

가장 중요한 변경은 GPU baseline을 두 종류로 나눈 것이다.

- full-tensor offload: input/output tensor 전체가 GPU 경계를 왕복
- partial-statistic offload: Bank-PCU가 reduction하고 partial statistic과 row scalar만 왕복

이 구분 없이 “GPU를 갔다 온다”고 표현하면 traffic이 tensor 크기인지 row 수인지 불명확하여 공정한 비교가 불가능하다.

## 2. 로컬 GPU 측정 가능성

2026-08-11 현재 환경 확인 결과:

- `nvidia-smi`: 명령 없음
- PyTorch: `2.8.0+cpu`
- `torch.cuda.is_available()`: `False`
- CUDA runtime: 없음

따라서 현재 PC에서 얻는 CPU PyTorch latency를 GPU baseline으로 사용할 수 없다. GPU case는 Phase 3에서 명시적 bandwidth/latency/kernel parameter sweep으로 분석하며 결과 evidence를 `ASSUMED`로 표시한다. 실제 CUDA GPU를 사용할 수 있게 되면 동일 schema에 `MEASURED` 행을 추가한다.

## 3. RSQRT 배치 관점의 핵심

RSQRT 작업량은 element 수가 아니라 row 수에 비례한다.

- `[280,2048]`: 573,440 elements, RSQRT 280회
- `[8960,64]`: 573,440 elements, RSQRT 8,960회

두 tensor는 byte가 같지만 두 번째 profile은 RSQRT 호출과 row scheduling이 32배다. 따라서 Logic-PCU RSQRT의 throughput은 latency뿐 아니라 initiation interval로 모델링해야 한다.

## 4. 확정한 비용식

```text
T_total = T_prepare + T_local_reduce + T_partial_transfer
        + T_global_reduce + T_finalize + T_rsqrt
        + T_broadcast_or_return + T_apply
        + T_queue_sync + T_mode_switch
```

```text
B_tensor = rows × hidden_size × dtype_bytes
B_global_stats = rows × statistic_count × scalar_bytes
B_bank_partials = rows × statistic_count × active_banks × scalar_bytes
```

Phase 3에서는 모든 결과를 위 구성요소로 분해한다. 특정 case에 없는 항목만 0이며, 구현되지 않았거나 근거가 없는 값은 0 대신 null/unknown으로 둔다.

## 5. Case별 경계

| Case | Bank-PCU | Logic-PCU | GPU/host | 주요 이동량 |
|---|---|---|---|---|
| GPU full tensor | 없음 | 없음 | 전체 norm | input/affine + output tensor |
| GPU partial | local reduction/apply | 없음 | global reduce/RSQRT | bank partial + row scalar |
| Bank-only | local reduction/apply | 없음 | global reduce/RSQRT fallback | bank partial + row scalar |
| Logic-only | 없음 | 전체 norm | 없음 | input/affine + output tensor |
| Hierarchical | local reduction/apply | global reduce/RSQRT | 없음 | bank partial + row scalar |

## 6. 공통 parameter

`common_model_parameters.json`은 다음 sweep을 고정한다.

- hidden size 64~8192
- bank 2/4/8/16
- Bank-PCU 및 Logic-PCU 1/2/4/8/16
- clock 100/250/500/1000 MHz
- offload one-way latency 250 ns~10 us
- offload bandwidth 16~512 Gbps
- RSQRT latency/II 1~64 cycle 범위

100 MHz reference clock은 기존 physical flow의 10 ns constraint에서 가져온 **가정값**이며 timing-closed 실측값이 아니다. GPU 관련 reference 값도 sensitivity 실행용 가정이고 측정값이 아니다.

## 7. 아직 결정하지 않은 값

다음 값은 근거가 생기기 전까지 null이다.

- 실제 GPU normalization kernel latency/energy
- Logic-PCU RSQRT 합성 area/power
- BF16 conversion cycle/energy
- Bank/Logic apply cycles per element

Phase 3 cycle model은 알려진 simulator cycle과 parameter sweep을 이용하되, null 값을 임의의 0으로 치환하지 않는다. 필요한 proxy를 도입하면 별도 assumptions ID와 근거를 붙인다.

## 8. 완료 판정

네 구조의 역할, 이동 경계, 공통 수치 계약, latency/traffic 식, evidence 분류 및 결과 schema를 확정했다. 따라서 Phase 2를 완료한다.
