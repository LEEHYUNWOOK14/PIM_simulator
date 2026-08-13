# Phase 2 BF16 Activation Trace Report

작성일: 2026-08-11

## 판정

`PARTIAL PASS — 공개 pretrained action-head 내부 BF16 trace 확보, full GR00T input-to-output trace 미확보`

공개 `nvidia/GR00T-N1.7-3B` checkpoint의 실제 action-head weight를 로드하고 BF16으로 4-step denoising 경로를 실행했다. normalization hook으로 269개 invocation을 기록하고 profile별 대표 입력·출력 tensor와 raw BF16 hex를 저장했다.

다만 action-head 경계의 backbone/state 입력은 seed 1701의 deterministic synthetic BF16이다. 따라서 이 trace의 증거 분류는 다음과 같다.

```text
PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT
```

이를 full pretrained GR00T inference activation이라고 표현하지 않는다.

## 실행 환경

- GPU: NVIDIA GeForce RTX 4060, 8,585,216,000 bytes VRAM
- CUDA: 12.8
- PyTorch: 2.9.0+cu128
- Python: 3.12.13, isolated WSL environment
- GPU BF16 support: true
- checkpoint revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- checkpoint dtype: BF16
- sequence length: 280 representative
- image-mask tokens: 256 representative
- action horizon: 40
- denoising steps: 4

공식 NVIDIA hardware guide는 N1.7 inference에 16GB 이상 VRAM을 요구한다. 현재 GPU는 8GB이고 gated `nvidia/Cosmos-Reason2-2B`에 인증되어 있지 않으므로 전체 backbone inference는 실행하지 않았다. 공개 GR00T checkpoint 자체는 다운로드하여 pretrained action head 3.02GiB를 저메모리 방식으로 로드했다.

## 실제 실행 결과

```text
PRETRAINED_GROOT_ACTION_HEAD_TRACE PASS
invocations=269 profiles=6 dtype=BF16 device=cuda
classification=PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT
```

| Profile | Runtime calls | Sample shape |
|---|---:|---|
| action_vlln | 1 | `[1,280,2048]` |
| action_vl_self_attention_norm1 | 4 | `[1,280,2048]` |
| action_vl_self_attention_norm3 | 4 | `[1,280,2048]` |
| action_dit_adaln_norm1 | 128 | `[1,41,1536]` |
| action_dit_norm3 | 128 | `[1,41,1536]` |
| action_dit_norm_out | 4 | `[1,41,1536]` |

269 calls는 checkpoint config에서 계산한 action-head call count와 정확히 일치한다.

## 저장 형식

각 profile의 첫 invocation에 대해 다음을 저장했다.

- PyTorch BF16 tensor와 gamma/beta/epsilon: `*.pt`
- RTL 입력 BF16 bit pattern: `*_input_bf16.hex`
- PyTorch output BF16 bit pattern: `*_output_bf16.hex`
- invocation별 shape, dtype, epsilon, 통계, checksum: `invocations.csv`
- 전체 trace metadata와 SHA-256: `trace_manifest.json`

Trace 위치:

`reports/groot_normalization/results/actual_groot/action_head_trace`

대표 checksum:

| Profile | Input SHA-256 | Output SHA-256 |
|---|---|---|
| action_vlln | `fed1a911...ac93ac88` | `d14a46c6...56866effc` |
| action_dit_adaln_norm1 | `a15b9423...ea728a6` | `bc5b10a5...477e75c2` |
| action_dit_norm3 | `d4776086...0ed8ed251` | `d7e3e4f8...006e98e6` |
| action_dit_norm_out | `0a605eeb...9b21ec03` | `1be4ce50...bab41f55` |

전체 checksum은 `trace_manifest.json`에 저장했다.

## 재현 명령

격리 환경 준비 후 다음 명령을 WSL에서 실행한다.

```bash
python tools/capture_pretrained_groot_action_head_trace.py \
  --source ../STOB_PIM_pure_layornorm/references/Isaac-GR00T \
  --checkpoint <HF_CACHE>/nvidia/GR00T-N1.7-3B/<revision> \
  --output reports/groot_normalization/results/actual_groot/action_head_trace \
  --device cuda
```

## Activation 통계 및 corner 상태

모든 invocation에 대해 min, max, mean, standard deviation, zero, NaN, Inf 수를 기록했다. 생성된 trace에서 hook 실행과 tensor 저장은 정상 완료됐으며 nonfinite 여부는 `invocations.csv`에서 invocation별로 추적 가능하다.

## 남은 한계

- 실제 camera/language/state dataset sample을 입력한 전체 GR00T trace가 아니다.
- backbone language RMSNorm과 vision LayerNorm activation은 캡처되지 않았다.
- sequence length 280과 image token 256은 실제 runtime profiler 측정이 아니라 기존 대표 조건이다.
- 실제 full inference trace를 위해서는 16GB 이상 GPU와 gated Cosmos-Reason2-2B 접근 인증이 필요하다.

Phase 3에서는 이 증거 등급을 유지한 채 BF16 sample을 bank/lane/vector mapping으로 변환하고 bit-exact round trip을 검증한다.
