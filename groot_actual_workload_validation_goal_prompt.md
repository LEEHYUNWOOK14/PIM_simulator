# 목표: 실제 GR00T Workload 기반 Normalization 검증 및 Production PIM 통합

## 작업 디렉터리

`C:\Users\Admin\OneDrive\2026-summer\STOB_semiconductor_pim\STOB_PIM2`

기준 문서:

- `groot_normalization_rsqrt_goal_prompt.md`
- `groot_normalization_completion_tracker_goal_prompt.md`
- `reports/groot_normalization/29_phase5_completion_tracker_top_integration_report.md`

## 최종 목표

실제 NVIDIA GR00T 모델 또는 공식 모델 코드에서 LayerNorm/RMSNorm workload를 추출하고, 실제 또는 대표 BF16 activation을 현재 RTL·cycle simulator에 연결한다. PyTorch golden reference와 정확도를 비교하고 실제 traffic을 반영하여 다음 네 구조를 같은 조건으로 평가한다.

1. GPU baseline
2. Bank-only PIM
3. Logic-only PIM
4. Bank-PCU + Logic-PCU hierarchical PIM

계층형 PIM이 실제 GR00T workload에서 유리하다는 근거가 확보된 경우에만 activation replay와 DRAM write-back RTL을 production 수준으로 확장한다. 결과가 불리하거나 근거가 부족하면 그 사실과 break-even 조건을 그대로 보고한다.

## 현재 기준선

현재 구현된 경로:

```text
synthetic Bank activation
→ SUM/SUMSQ reduction
→ Logic-PCU parallel reduction
→ mean/variance 및 RSQRT
→ Bank-PCU scalar broadcast
→ RMSNorm/LayerNorm microprogram
→ Bank-PCU affine M_OUT
→ final write-back handshake 기반 row completion
```

현재 결과는 synthetic 축소 workload를 이용한 RTL 기능 검증이다. 실제 GR00T pretrained inference, 실제 activation trace 또는 실제 GPU normalization latency를 측정한 결과로 표현하지 않는다.

## 공통 작업 규칙

- 작업 전후 `git status --short`를 확인하고 기존 사용자 변경을 보존한다.
- 기존 결과를 삭제하거나 처음부터 반복하지 않는다.
- 수치는 반드시 `측정`, `코드에서 확인`, `모델 계산`, `가정`, `미검증`으로 분류한다.
- 실제 GR00T 실행이 불가능하면 원인을 기록하고 공식 모델 코드 분석과 synthetic fallback 결과를 분리한다.
- 실제 trace가 없는 상태에서 synthetic 입력을 실제 GR00T activation이라고 부르지 않는다.
- FP16 결과와 BF16 결과를 섞지 않는다.
- GPU latency, traffic, power 및 PPA 값을 근거 없이 생성하지 않는다.
- 모든 결과에 모델 버전, commit 또는 package version, tensor shape, dtype, device, batch/sequence 조건과 단위를 기록한다.
- 각 단계의 완료 조건을 만족한 후 다음 단계로 진행한다.

---

## Phase 1: 실제 GR00T Normalization Workload 추출

### 목표

실제 GR00T 실행 환경 또는 공식 모델 코드에서 LayerNorm/RMSNorm 모듈을 식별하고 invocation별 workload manifest를 만든다.

### 작업

1. 로컬 저장소와 설치된 Python 환경에서 GR00T 모델 코드, checkpoint 및 실행 스크립트를 찾는다.
2. 모델명과 버전을 확정한다. 가능하면 NVIDIA GR00T N1.7을 기준으로 한다.
3. 모델 코드에서 다음 연산을 탐색한다.

   - `torch.nn.LayerNorm`
   - RMSNorm 구현체
   - fused LayerNorm/RMSNorm
   - Transformer block 내부 normalization
   - vision encoder 또는 action head의 normalization

4. 실제 실행이 가능하면 PyTorch hook 또는 profiler를 이용해 invocation별 정보를 기록한다.

   - module path와 operation type
   - input/output shape
   - normalized dimension
   - batch, sequence, token 수
   - dtype
   - epsilon
   - affine 여부
   - gamma/beta shape
   - 호출 횟수
   - input/output byte
   - 실행 device

5. dynamic shape가 있으면 실제 범위와 빈도를 기록한다.
6. 실제 실행이 불가능하면 모델 코드와 config에서 정적으로 확인 가능한 항목만 기록하고 호출 횟수는 미검증으로 남긴다.

### 산출물

- `reports/groot_normalization/results/groot_actual_workload_manifest.csv`
- `reports/groot_normalization/results/groot_actual_workload_manifest.json`
- `reports/groot_normalization/30_phase1_actual_groot_workload_report.md`
- 재현 가능한 profiler 또는 hook 스크립트

### 완료 조건

- 사용한 GR00T 버전과 출처가 기록되어 있다.
- LayerNorm/RMSNorm module path와 shape가 추적 가능하다.
- dtype, epsilon, affine 여부와 호출 횟수의 근거가 구분되어 있다.
- 기존 4개 대표 synthetic profile과 실제 workload의 일치 여부가 비교되어 있다.

---

## Phase 2: 실제 BF16 Activation Trace 확보

### 진입 조건

Phase 1에서 최소 한 개 이상의 normalization invocation이 식별되어야 한다.

### 작업

1. 실제 GR00T inference 입력과 실행 조건을 고정한다.
2. normalization 입력과 필요한 경우 출력, gamma, beta를 BF16 bit pattern으로 캡처한다.
3. 각 trace에 다음 metadata를 연결한다.

   - invocation ID
   - module path
   - tensor shape와 stride
   - dtype
   - epsilon
   - RMSNorm/LayerNorm 구분
   - gamma/beta 포함 여부
   - 모델 입력 및 seed
   - capture device

4. 전체 tensor 저장이 과도하면 대표 invocation을 계층별로 sampling하되 선택 기준을 기록한다.
5. NaN, Inf, zero variance, subnormal, min/max, mean/std 등 activation 통계를 계산한다.
6. checkpoint 또는 입력 데이터의 라이선스와 재배포 가능 여부를 확인한다. 재배포할 수 없는 원본 trace는 커밋하지 않고 생성 절차와 checksum만 기록한다.

### 파일 형식

사람이 읽는 CSV와 RTL용 raw bit pattern을 분리한다.

- 원본/메타데이터: NPZ, PT 또는 safetensors
- RTL 입력: BF16 hexadecimal vector
- manifest: JSON/CSV
- 각 파일의 SHA-256 checksum 기록

### 산출물

- trace capture 스크립트
- `reports/groot_normalization/results/groot_bf16_trace_manifest.json`
- RTL 변환 전 실제 BF16 trace 또는 재현 절차
- `reports/groot_normalization/31_phase2_bf16_activation_trace_report.md`

### 완료 조건

- 최소 한 개의 실제 BF16 normalization 입력이 확보되어 있다.
- trace와 workload manifest invocation을 tag로 연결할 수 있다.
- gamma/beta와 epsilon을 포함해 PyTorch 연산을 재현할 수 있다.
- 실제 trace와 fallback synthetic trace가 명확히 구분되어 있다.

---

## Phase 3: GR00T Trace를 RTL 및 Cycle Simulator 입력으로 변환

### 진입 조건

Phase 2 trace와 metadata가 재현 가능한 상태여야 한다.

### 작업

1. PyTorch tensor를 BF16 raw bit pattern으로 변환한다.
2. 실제 hidden dimension을 bank, lane, vector address에 mapping한다.
3. 다음 mapping 정보를 manifest에 기록한다.

   - row/tag
   - bank ID
   - even/odd bank
   - vector address
   - lane index
   - valid element count와 padding
   - expected vectors per bank

4. reduction 입력과 apply replay 입력이 동일한 source tensor와 주소를 사용하도록 한다.
5. 현재 RTL이 처리할 수 없는 shape는 tile로 분할하고 partial reduction 결합 규칙을 명시한다.
6. RTL testbench용 hex와 cycle simulator용 trace를 동일 manifest에서 생성한다.
7. 변환 후 tensor를 역변환하여 원본 BF16 bit pattern과 일치하는지 확인한다.

### 산출물

- trace-to-RTL 변환 도구
- RTL용 BF16 vector/metadata 파일
- simulator용 trace 파일
- mapping round-trip 검증 결과
- `reports/groot_normalization/32_phase3_trace_to_rtl_mapping_report.md`

### 완료 조건

- 원본 trace에서 RTL/simulator 입력을 재현할 수 있다.
- round-trip BF16 bit mismatch가 0이다.
- padding과 bank mapping이 문서화되어 있다.
- reduction trace와 replay trace의 tag/address 정합성이 검증되어 있다.

---

## Phase 4: PyTorch Golden 대비 RTL 정확도 비교

### 진입 조건

Phase 3의 RTL 입력과 mapping 검증이 통과해야 한다.

### Golden reference

실제 GR00T에서 사용하는 연산 순서와 dtype 정책을 우선한다. 별도로 FP32 canonical golden과 BF16 staged reference를 만든다.

```text
FP32 canonical PyTorch reference
BF16/RTL-equivalent staged reference
RTL output
```

### 작업

1. 실제 trace에 대해 LayerNorm/RMSNorm PyTorch golden output을 생성한다.
2. SUM/SUMSQ, mean/variance, epsilon, RSQRT, gamma/beta, affine 각 단계의 중간값을 비교한다.
3. 다음 metric을 invocation별·shape별로 기록한다.

   - maximum/mean absolute error
   - maximum/mean relative error
   - RMSE 또는 NRMSE
   - ULP 차이
   - NaN/Inf 발생 수
   - bit-exact mismatch 수
   - top-k worst element와 위치

4. FP16 RTL 결과와 BF16 RTL 결과를 별도로 보고한다.
5. 실제 trace 외에도 constant, zero variance, 작은 variance, 큰 offset, NaN/Inf/subnormal stress를 실행한다.
6. 오차가 큰 경우 reduction 방식, rounding, accumulation width, RSQRT LUT 또는 affine 순서 중 원인을 분리한다.

### 산출물

- PyTorch golden 생성 및 비교 도구
- invocation별 정확도 CSV/JSON
- worst-case sample과 단계별 mismatch 분석
- RTL testbench 및 재현 스크립트
- `reports/groot_normalization/33_phase4_actual_trace_accuracy_report.md`

### 완료 조건

- 실제 BF16 trace가 RTL 또는 RTL-equivalent path를 통과한다.
- PyTorch 대비 정확도 metric과 worst case가 기록되어 있다.
- 허용 오차 기준과 통과 여부가 사전에 명시되어 있다.
- NaN/Inf 및 corner-case 정책이 문서화되어 있다.

---

## Phase 5: 실제 Traffic 기반 Architecture 비교

### 진입 조건

Phase 1 workload manifest와 Phase 3 mapping이 완료되어야 한다. 정확도 기준을 통과하지 못했다면 성능 결과와 함께 정확도 실패를 명시한다.

### 비교 구조

- GPU baseline
- Bank-only PIM: local reduction/apply, global reduction 및 RSQRT offload
- Logic-only PIM: 원본 tensor를 Logic-PCU로 이동
- Hierarchical PIM: Bank partial reduction, Logic global reduction/RSQRT, Bank apply

### 공통 입력

- 실제 invocation shape 및 호출 횟수
- 실제 BF16 byte 수
- bank/vector mapping
- gamma/beta load 및 reuse traffic
- activation read/replay traffic
- partial statistic traffic
- scalar broadcast traffic
- final write-back traffic
- queue, synchronization 및 mode-switch 비용

### 작업

1. 각 architecture의 traffic을 byte와 transaction 수로 분해한다.
2. 현재 RTL에서 측정한 reduction, scalar, broadcast, apply, tracker latency를 모델에 반영한다.
3. replay와 DRAM write-back 미구현 비용은 명시적 parameter로 포함한다.
4. GPU가 있으면 실제 LayerNorm/RMSNorm latency와 memory traffic을 측정한다.
5. GPU가 없으면 공식 문서 또는 명시적 parameter 모델을 사용하고 실측으로 표현하지 않는다.
6. 실제 invocation별 결과와 전체 GR00T normalization projected 결과를 분리한다.
7. 다음 sensitivity를 수행한다.

   - bank 수
   - hidden dimension과 row 수
   - interconnect latency/bandwidth
   - replay 및 write-back latency
   - gamma/beta reuse
   - scalar engine 수
   - bank skew와 contention

8. hierarchical PIM의 승리·패배 조건과 break-even을 계산한다.

### 산출물

- 공통 parameter 파일 업데이트
- 실제 workload 기반 architecture comparison CSV/JSON
- latency 및 traffic breakdown
- sensitivity 및 break-even 결과
- `reports/groot_normalization/34_phase5_actual_traffic_architecture_comparison.md`

### Architecture decision gate

다음 조건을 평가한다.

- 실제 GR00T normalization workload에서 hierarchical PIM이 GPU 또는 다른 PIM 구조보다 유리한가?
- replay와 write-back 비용을 포함해도 이득이 유지되는가?
- 정확도 기준을 만족하는가?
- 이득이 특정 shape에만 국한되는가?
- 예상 area/energy 증가를 감수할 근거가 있는가?

결론을 다음 중 하나로 명시한다.

- `GO`: production replay/write-back RTL 확장
- `CONDITIONAL GO`: 명시된 break-even 조건에서만 확장
- `NO-GO`: 현 구조 확장 중단 또는 architecture 변경
- `INSUFFICIENT EVIDENCE`: 실측/trace 부족으로 판단 보류

---

## Phase 6: Production Activation Replay 및 DRAM Write-back RTL

### 진입 조건

Phase 5 architecture decision이 `GO` 또는 `CONDITIONAL GO`여야 한다. 그렇지 않으면 production RTL을 구현하지 않고 원인과 다음 대안을 보고한다.

### 작업

1. 외부 고정 `activation_data_i`를 tag/address 기반 replay buffer로 교체한다.
2. reduction에 사용한 activation과 apply activation의 동일성을 보장한다.
3. even/odd bank와 vector address를 실제 mapping 순서로 순회한다.
4. bank별 여러 final vector를 처리하도록 completion tracker를 count 또는 packet identity 기반으로 확장한다.
5. gamma/beta preload 및 layer reuse scheduler를 연결한다.
6. 최종 normalized vector를 DRAM write command/data 경로에 연결한다.
7. row completion을 단순 top-level ready가 아니라 실제 DRAM write acceptance 또는 response 정책에 연결한다.
8. read/replay/write-back contention과 bank별 backpressure를 검증한다.
9. 여러 row, bank, vector address의 out-of-order completion을 stress한다.
10. cycle simulator를 실제 replay/write-back RTL latency로 재보정한다.

### 필수 검증

- 실제 GR00T trace 기반 multi-vector row
- even/odd bank 순회
- vector padding과 hidden-size tail
- replay tag/address mismatch 검출
- gamma/beta GRF index 충돌
- DRAM read/write backpressure
- 여러 row와 bank의 out-of-order completion
- duplicate, missing, stale packet
- reset과 context 재사용
- PyTorch golden 정확도 유지
- 기존 normalization 전체 회귀 유지

### 산출물

- production replay buffer 및 scheduler RTL
- DRAM read/replay/write-back 통합 RTL
- count/packet 기반 completion tracker
- 실제 trace 기반 E2E testbench
- 합성 및 구조 검증 결과
- 재보정된 system simulator 결과
- `reports/groot_normalization/35_phase6_production_replay_writeback_report.md`

### 완료 조건

- 실제 GR00T BF16 trace가 production RTL 경로를 통과한다.
- reduction과 apply가 동일 activation tag/address를 사용한다.
- 모든 final vector의 실제 write-back 이후에만 row completion이 발생한다.
- 여러 row·bank·vector의 out-of-order와 backpressure에서 누락·중복이 없다.
- PyTorch 정확도 기준과 RTL 전체 회귀가 통과한다.
- 실제 traffic을 반영한 architecture 비교가 다시 계산되어 있다.

---

## 최종 산출물

- 실제 GR00T normalization workload manifest
- 실제 BF16 activation trace 또는 재현 가능한 capture 절차
- trace-to-RTL/simulator converter
- PyTorch golden 및 RTL 정확도 비교
- 실제 traffic 기반 4개 architecture 비교
- break-even 및 GO/NO-GO 결정
- 조건 충족 시 production replay/write-back RTL
- 전체 재현 명령, 환경, raw log, CSV/JSON 및 알려진 한계
- 대회 제출에 사용할 수 있는 주장과 사용할 수 없는 주장 구분

## 최종 완료 조건

- 실제 GR00T 코드 또는 실행에서 normalization workload가 추출되어 있다.
- 최소 한 개의 실제 BF16 activation trace가 검증 경로에 연결되어 있다.
- PyTorch와 RTL 결과의 정확도가 정량적으로 비교되어 있다.
- 네 architecture가 동일 workload와 traffic 조건으로 비교되어 있다.
- hierarchical PIM의 승리·패배 및 break-even 조건이 명시되어 있다.
- architecture decision gate 결과가 근거와 함께 기록되어 있다.
- `GO` 또는 `CONDITIONAL GO`인 경우 production replay/write-back RTL과 실제 trace E2E가 완료되어 있다.
- `NO-GO` 또는 `INSUFFICIENT EVIDENCE`인 경우 근거 없는 RTL 확장을 하지 않고 대안과 추가 필요 증거를 제시한다.
