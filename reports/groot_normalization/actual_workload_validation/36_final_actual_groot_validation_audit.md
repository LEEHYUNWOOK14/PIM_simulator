# 실제 GR00T Normalization 검증 최종 감사

## 최종 상태

목표 문서의 Phase 1~5를 순서대로 수행했고, Phase 5 decision gate는 **`NO-GO`**다. 따라서 Phase 6 production replay/write-back RTL은 gate 규칙에 따라 구현하지 않았다.

핵심 결과:

- 공식 GR00T N1.7 source/checkpoint에서 normalization workload 13개 profile 정적 감사 완료
- 공개 pretrained action head를 RTX 4060에서 BF16으로 실행해 269 normalization invocations 캡처
- 증거 분류: `PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`; full GR00T inference가 아님
- 6개 대표 tensor를 16 banks × 4 lanes에 변환: 477,312 packets, padding 0, BF16 round-trip mismatch 0
- 실제 BF16 RTL replay: 6/6 정상 완료, protocol error 0
- PyTorch 정확도: 기존 `max_abs <= 0.025` 기준 1/6 PASS, overall **FAIL**
- 단계별 RTL software emulation: mean/inv_std 6/6 bit-exact, output 10,240/10,240 bit-exact
- RTX 4060 BF16 LayerNorm microbenchmark의 269-call serial projection: 3.121 ms
- 40 MHz hierarchical PIM model: 21.225 ms, GPU 대비 0.147×
- modeled latency break-even: 약 275.0 MHz, 현재 timing evidence 밖
- 최종 architecture decision: **NO-GO**

## Phase별 완료 감사

| Phase | 결과 | 주요 증거 |
|---|---|---|
| 1 workload 추출 | COMPLETE | 13 profiles, official source/config/checkpoint header 감사 |
| 2 BF16 trace | COMPLETE WITH SCOPE LIMIT | pretrained action head + synthetic boundary input, 269 hooks |
| 3 RTL mapping | COMPLETE | 16×4 mapping, 477,312 packets, mismatch 0 |
| 4 정확도 | COMPLETE / GATE FAIL | 6 profiles 실행, 1 PASS·5 FAIL, 단계별 원인 분리 |
| 5 architecture 비교 | COMPLETE / NO-GO | GPU measured, 3 PIM modeled, traffic/transaction/sensitivity |
| 6 production RTL | GATED SKIP | NO-GO이므로 목표 규칙에 따라 미구현 |

## 재현 회귀 결과

최종 재실행에서 다음을 확인했다.

- Python 도구 8개 `py_compile` PASS
- official workload audit PASS
- pretrained action-head capture PASS: 269 invocations, 6 profiles, BF16 CUDA
- trace converter PASS: 477,312 packets, round-trip mismatch 0
- actual trace BF16 RTL: 6/6 functional completion PASS
- stage analyzer: scalar match `True`, apply match `True`
- normalization foundation tests: 28/28 PASS
- special values: FP16/BF16 각각 7 cases PASS
- scalar vectors: FP16/BF16 각각 2,048 vectors PASS
- 기존 full-PIM tests: 9 functional gates PASS, random stress 40 batches/320 results PASS
- `git diff --check`: whitespace error 없음

`run_groot_actual_trace_bf16_test.sh`의 최종 `REGRESSION PASS`는 protocol·completion·output 생성 성공을 의미한다. 같은 로그의 `GROOT_RTL_ACCURACY_ANALYSIS result=FAIL`이 PyTorch accuracy gate 판정이며 둘을 혼동하면 안 된다.

## 재현 명령

WSL CUDA 환경:

```bash
cd /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2

/home/chandler/.cache/stob-groot-runtime/bin/python \
  tools/capture_pretrained_groot_action_head_trace.py \
  --source ../STOB_PIM_pure_layornorm/references/Isaac-GR00T \
  --checkpoint /home/chandler/.cache/huggingface/hub/models--nvidia--GR00T-N1.7-3B/snapshots/2fc962b973bccdd5d8ce4f67cc63b264d6886495 \
  --output reports/groot_normalization/results/actual_groot/action_head_trace \
  --device cuda

python3 tools/convert_groot_trace_to_rtl.py \
  --trace reports/groot_normalization/results/actual_groot/action_head_trace \
  --output reports/groot_normalization/results/actual_groot/rtl_mapping \
  --banks 16 --lanes 4

bash verification/groot_normalization/run_groot_actual_trace_bf16_test.sh
python3 tools/analyze_groot_rtl_accuracy_stages.py

/home/chandler/.cache/stob-groot-runtime/bin/python \
  tools/benchmark_groot_normalization_gpu.py
python3 tools/compare_actual_groot_architectures.py

bash verification/groot_normalization/run_foundation_regression.sh --tests-only
bash rtl/run_full_pim_tests.sh
```

Phase 1 정적 감사:

```bash
python tools/audit_actual_groot_normalization.py
```

GPU benchmark를 다시 실행하면 공유/display GPU 상태에 따라 측정값이 달라지므로 새 JSON/CSV를 기준으로 architecture comparison과 문서 수치를 함께 갱신해야 한다.

## 사용할 수 있는 주장

다음 주장은 현재 산출물로 직접 뒷받침된다.

- pinned official GR00T N1.7 코드/config/checkpoint tensor metadata에서 normalization module, hidden shape, dtype/epsilon/affine 특성을 추출했다.
- 공개 pretrained action head를 BF16 CUDA로 실행했고 synthetic boundary input 조건에서 269개 normalization invocation을 hook으로 캡처했다.
- 캡처한 BF16 bit pattern은 현재 bank/lane mapping을 왕복해 mismatch 0이다.
- 현재 BF16 hierarchical RTL은 6개 representative row를 실행하지만 사전 PyTorch 정확도 기준은 1/6만 통과한다.
- 오차는 mapping 오류가 아니라 현재 BF16 accumulation/scalar/LUT/apply arithmetic에서 재현된다.
- RTX 4060에서 해당 shape의 PyTorch BF16 LayerNorm microbenchmark를 CUDA event로 측정했다.
- 명시한 40 MHz/traffic/replay assumptions 아래 hierarchical 모델은 GPU measured projection보다 느리다.
- 이 증거에서는 production replay/write-back 확장이 `NO-GO`다.

## 사용할 수 없는 주장

다음은 현재 결과로 주장하면 안 된다.

- full NVIDIA GR00T N1.7 pretrained inference를 성공적으로 실행했다.
- 실제 robot observation/language/action dataset에서 activation을 캡처했다.
- language/vision backbone의 dynamic invocation count와 full-model BF16 activation을 측정했다.
- 논리 payload byte가 실제 HBM transaction, row-buffer hit, bank conflict 또는 bandwidth 측정값이다.
- PIM latency가 silicon, FPGA 또는 timing-closed post-layout 실측값이다.
- hierarchical PIM이 GPU보다 energy/area에서 우수하다.
- production activation replay와 DRAM write-back이 구현·검증됐다.
- 현재 BF16 RTL 정확도가 GR00T deployment에 허용 가능하다.

## 알려진 제한

Full model 실행은 RTX 4060 8 GB가 공식 최소 16 GB VRAM 요구보다 작고, checkpoint가 참조하는 gated `nvidia/Cosmos-Reason2-2B` dependency에 인증이 없어 완료하지 못했다. 공개 action-head weight만 실행한 이유와 fallback 범위는 Phase 2 보고서에 기록했다.

GPU profile 간 동일 shape 측정에도 WSL/display GPU 변동이 있다. median과 raw repeats를 보존했지만 전용 GPU에서 재측정하는 것이 바람직하다. PIM 비교는 명시적 cycle/traffic 모델이며 queueing, DRAM timing, contention 및 physical energy는 실측되지 않았다.

## 보고서 및 주요 산출물

- `30_phase1_actual_groot_workload_report.md`
- `31_phase2_bf16_activation_trace_report.md`
- `32_phase3_trace_to_rtl_mapping_report.md`
- `33_phase4_actual_trace_accuracy_report.md`
- `34_phase5_actual_traffic_architecture_comparison.md`
- `35_phase6_production_replay_writeback_report.md`
- `results/groot_actual_workload_manifest.csv/json`
- `results/groot_bf16_trace_manifest.json`
- `results/actual_groot/action_head_trace/`
- `results/actual_groot/rtl_mapping/`
- `results/actual_groot/rtl_accuracy_results/`
- `results/actual_groot/gpu_benchmark/`
- `results/actual_groot/architecture_comparison/`

모든 보고서는 `reports/groot_normalization/actual_workload_validation/`에 있고, machine-readable 결과는 `reports/groot_normalization/results/actual_groot/` 아래에 단계별 폴더로 분리했다.
