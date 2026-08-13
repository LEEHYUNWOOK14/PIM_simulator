# GR00T workload 증거 정적 감사

작성일: 2026-08-13

## 판정

`PARTIAL_EVIDENCE — 저장 파일 무결성과 제한된 action-head 호출 증거는 확인, 실제 full-inference provenance 및 manifest 연결은 미충족`

이 감사는 기존 산출물만 읽었으며 GR00T 모델을 재실행하지 않았다. Trace의 정확한 분류는
`PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`이고 `not_full_groot_inference=true`다. 따라서 실제 robot 입력 기반 GR00T
full-inference trace로 사용할 수 없다.

## 검사 결과

| 검사 | 결과 | 증거 |
|---|---|---|
| `trace_scope_classification` | **PASS** | classification=PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT, not_full_groot_inference=True |
| `workload_runtime_scope` | **PASS** | runtime_status=NO_PRETRAINED_INFERENCE_CAPTURE |
| `trace_summary_copy` | **PASS** | summary manifest contains the same trace core fields |
| `model_revision_chain` | **PASS** | model=nvidia/GR00T-N1.7-3B, revision=2fc962b973bccdd5d8ce4f67cc63b264d6886495 |
| `workload_profile_coverage` | **PARTIAL** | trace covers 6/13 workload profiles; uncaptured=['backbone_language_final_rmsnorm', 'backbone_language_input_rmsnorm', 'backbone_language_k_rmsnorm', 'backbone_language_post_attention_rmsnorm', 'backbone_language_q_rmsnorm', 'backbone_visual_block_norm1', 'backbone_visual_block_norm2'] |
| `invocation_shape_dtype_epsilon` | **PASS** | all six captured action-head profiles agree across workload, invocation CSV, and trace files |
| `trace_input_output_checksums` | **PASS** | input/output BF16 HEX hashes agree with sample and invocation metadata |
| `gamma_beta_provenance` | **FAIL** | gamma/beta files have no manifest checksums or checkpoint tensor names; AdaLayerNorm dynamic modulation is represented by identity/zero placeholders |
| `bf16_trace_to_workload_manifest_link` | **PARTIAL** | profile_id joins 6 profiles, but explicit link fields are absent: ['invocation_id', 'trace_id', 'workload_manifest_sha256', 'workload_profile_tag'] |
| `persisted_trace_to_rtl_roundtrip` | **PASS** | independent readback of 477,312 persisted packets; mismatches=0 |
| `rtl_tag_consistency` | **PASS** | tag conflicts across profile/row owners=0; tags identify representative rows, not invocations |
| `mapping_manifest_sealing` | **FAIL** | mapping manifest omits packet-file SHA-256, source trace-manifest SHA-256, workload-manifest SHA-256, and converter revision |
| `reduction_apply_roundtrip_contract` | **NOT_EVIDENCED** | only one logical input packet set exists; separate reduction/apply manifests or production replay consumption evidence are absent |

## Workload invocation과 tensor provenance

| Profile | Calls | Sample shape | BF16 dtype | Epsilon | Gamma/beta provenance |
|---|---:|---|---|---|---|
| `action_vlln` | 1 | `[1, 280, 2048]` | PASS | PASS | `PRETRAINED_PARAMETER_IMPLIED_BY_CAPTURE_CODE_NOT_HASHED_IN_MANIFEST` |
| `action_vl_self_attention_norm1` | 4 | `[1, 280, 2048]` | PASS | PASS | `PRETRAINED_PARAMETER_IMPLIED_BY_CAPTURE_CODE_NOT_HASHED_IN_MANIFEST` |
| `action_vl_self_attention_norm3` | 4 | `[1, 280, 2048]` | PASS | PASS | `PRETRAINED_PARAMETER_IMPLIED_BY_CAPTURE_CODE_NOT_HASHED_IN_MANIFEST` |
| `action_dit_adaln_norm1` | 128 | `[1, 41, 1536]` | PASS | PASS | `PLACEHOLDER_NOT_DYNAMIC_MODULATION` |
| `action_dit_norm3` | 128 | `[1, 41, 1536]` | PASS | PASS | `PRETRAINED_PARAMETER_IMPLIED_BY_CAPTURE_CODE_NOT_HASHED_IN_MANIFEST` |
| `action_dit_norm_out` | 4 | `[1, 41, 1536]` | PASS | PASS | `SYNTHESIZED_IDENTITY_FOR_NON_AFFINE_LAYER` |

269회 호출, shape, BF16 dtype, epsilon은 workload manifest와 invocation CSV 사이에서 일치한다.
다만 이 일치는 synthetic boundary 조건의 action head 6개 profile에만 해당한다. Workload manifest의
13개 profile 중 backbone language/vision 7개는 activation이 없으며 manifest 자체도
`runtime_status=NO_PRETRAINED_INFERENCE_CAPTURE`로 표시한다.

Affine LayerNorm의 gamma/beta는 생성 코드상 pretrained module parameter에서 왔지만 manifest에
checkpoint tensor name이나 gamma/beta checksum이 없다. Non-affine 2개 profile은 생성 코드가 identity gamma와
zero beta를 합성한다. 특히 `action_dit_adaln_norm1`은 workload manifest에서 dynamic modulation으로
분류되지만 저장 gamma/beta는 모두 1/0이므로 timestep-dependent AdaLN scale/shift의 캡처 증거가 아니다.

## BF16 trace와 workload manifest 연결성

`profile_id` 문자열로 6개 action-head profile을 조인할 수 있고 model revision도 일치한다. 그러나 trace
manifest에는 workload manifest checksum, workload profile tag, invocation ID 또는 trace ID가 없다.
대표 sample도 각 profile의 첫 호출이라는 사실을 input/output checksum으로 추론할 수 있을 뿐,
sample 항목 자체에 invocation index가 없다. 따라서 연결성 판정은 `PARTIAL`이다.

## Trace-to-RTL round-trip

기존 converter의 in-memory 판정과 별도로 저장된 packet CSV 및 packed HEX 477,312개를
다시 읽어 원본 BF16 순서로 역변환했다. CSV/HEX metadata 오류 0, tag owner 충돌 0,
BF16 mismatch 0으로 기존 0-mismatch 결과는 파일 수준에서도 재현된다.

다만 mapping manifest에는 packet 파일 SHA-256, source trace/workload manifest SHA-256, converter revision이
없어 산출물 세트가 cryptographically sealed되어 있지 않다. Tag는 profile+row를 식별할 뿐 269개 invocation을
식별하지 않는다. 별도의 reduction/apply replay manifest나 production top의 소비 증거도 없어 보고서의
"동일 input checksum과 mapping manifest 사용"은 설계 의도 수준이며 round-trip 실행 증거가 아니다.

## 최종 사용 가능 범위

- 사용 가능: pinned pretrained action-head weight를 synthetic BF16 boundary 입력으로 실행한 제한적 trace,
  6개 대표 sample의 shape/dtype/epsilon 및 저장 packet bit-level 무결성.
- 사용 불가: 실제 GR00T full inference 또는 robot dataset activation, AdaLN dynamic gamma/beta capture,
  invocation-tag 기반 workload-to-RTL chain of custody, production reduction/apply replay 정합성.

Machine-readable 결과: `reports/groot_normalization/results/actual_groot/evidence_audit/static_evidence_audit.json`
