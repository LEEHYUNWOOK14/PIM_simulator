# 프로젝트 출처 및 증거 인덱스

이 폴더는 STOB PIM2 프로젝트에서 웹·논문·공개 저장소를 통해 참고한 자료와, 해당 자료가 사용된 provenance 및 실행 로그를 한곳에서 찾기 위한 중앙 인덱스입니다.

원본 evidence 파일은 기존 도구와 보고서가 참조하므로 이동하거나 삭제하지 않습니다. `archive/`에는 핵심 source registry와 출처 포함 로그를 동일 내용으로 복사해 두었고, [`source_artifact_inventory.md`](source_artifact_inventory.md)에 원본 경로와 SHA-256을 기록합니다.

## 출처 사용 원칙

- 표준·제조사 공개자료·논문·공개 모델·프로젝트 가정을 구분합니다.
- 공개자료의 수치를 현재 RTL 또는 실제 HBM 제조 공정의 실측값으로 확대 해석하지 않습니다.
- commit이 알려진 공개 저장소는 revision을 고정합니다.
- local tool output은 실행 Git SHA, 입력 hash, tool version과 연결합니다.
- 출처가 없는 값은 `project_assumption`, `estimated`, `illustrative` 또는 `unknown`으로 표시합니다.

## HBM2와 PIM

| 출처 | 프로젝트에서 참고하는 내용 |
|---|---|
| [SAITPublic/PIMSimulator](https://github.com/SAITPublic/PIMSimulator/tree/3703d1f19c8f027360cc33a3243eb271e3bb6898) | HBM2 PIM simulator 기준 구조, timing/config, PIM command 모델 |
| [DRAMSim2](https://github.com/umd-memsys/DRAMSim2) | 현재 C++ cycle simulator의 기반 |
| [DRAMsim3 HBM2](https://github.com/umd-memsys/DRAMsim3/tree/29817593b3389f1337235d63cac515024ab8fd6e) | HBM2 channel/bank/timing/refresh 설정 교차 확인 |
| [JEDEC HBM2 JESD235](https://www.jedec.org/standards-documents/docs/jesd235) | HBM 계열의 표준 범위와 stack/channel organization |
| [Samsung Aquabolt HBM2](https://semiconductor.samsung.com/news-events/news/samsung-starts-producing-8-gigabyte-high-bandwidth-memory-2-with-highest-data-transmission-speed/) | HBM2 제품 대역폭·전압·용량 공개 정보 |
| [Samsung Flashbolt HBM2E](https://semiconductor.samsung.com/news-events/news/samsung-to-advance-high-performance-computing-systems-with-launch-of-industrys-first-3rd-generation-16gb-hbm2e/) | 8Hi, TSV/micro-bump, HBM2E 제품 맥락 |
| [SK hynix TSV/HBM2](https://news.skhynix.com/creating-new-values-in-dram-using-through-silicon-via-technology-for-continued-scaling-in-memory-system-performance-and-capacity/) | TSV scaling, 1024 data pin, 4Hi/8Hi 구조 설명 |
| [Samsung HBM-PIM](https://semiconductor.samsung.com/news-events/news/samsung-develops-industrys-first-high-bandwidth-memory-with-ai-processing-power/) | 산업계 HBM-PIM 연구 방향의 공개 근거 |

## AI workload와 normalization

| 출처 | 프로젝트에서 참고하는 내용 |
|---|---|
| [MobileNetV4](https://arxiv.org/abs/2404.10518) | UIB 구조와 범용 mobile workload |
| [TensorFlow MobileNet 구현](https://github.com/tensorflow/models/blob/master/official/vision/modeling/backbones/mobilenet.py) | MobileNetV4 block 구성 교차 확인 |
| [NVIDIA Isaac GR00T N1.7](https://github.com/NVIDIA/Isaac-GR00T/tree/b9955401d50c92a29258732e3ad6ccd579f1bdc0) | 실제 embodied-AI model normalization inventory |
| [GR00T N1.7 release](https://github.com/NVIDIA/Isaac-GR00T/releases/tag/n1.7-release) | 평가 대상 release provenance |
| [GR00T N1.7-3B config](https://huggingface.co/nvidia/GR00T-N1.7-3B/blob/2fc962b973bccdd5d8ce4f67cc63b264d6886495/config.json) | model dimension과 normalization 구성 교차 확인 |
| [RMSNorm 논문](https://arxiv.org/abs/1910.07467) | RMSNorm 정의와 LayerNorm 비교 |
| [PyTorch RMSNorm](https://docs.pytorch.org/docs/stable/generated/torch.nn.RMSNorm.html) | framework 연산 정의 교차 확인 |
| [Qwen3-VL normalization source](https://github.com/huggingface/transformers/blob/v4.57.1/src/transformers/models/qwen3_vl/modeling_qwen3_vl.py) | 실제 transformer normalization 구현 비교 |

## RTL과 물리 설계

| 출처 | 프로젝트에서 참고하는 내용 |
|---|---|
| [OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/56496f3980fb6e9e58f10c8aea4a98949c0fe5f2) | Sky130HD synthesis·floorplan·placement·route flow |
| [OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD/tree/ab6fd26351dc449e69059684dc6aa9ae9046eb36) | placement, CTS, routing, GDS 물리 구현 도구 |
| [Yosys](https://github.com/The-OpenROAD-Project/yosys/tree/a5af9d690a43744bf6b2cc3dea2717c16b54621c) | SystemVerilog logic synthesis와 technology mapping |
| [SkyWater SKY130 PDK](https://github.com/google/skywater-pdk) | 공개 연구용 process design kit |
| [KLayout](https://www.klayout.de/) | GDS stream-out 결과의 독립 readback과 시각화 |

## PPA, 비용과 수율

| 출처 | 프로젝트에서 참고하는 내용 |
|---|---|
| [CACTI](https://github.com/HewlettPackard/cacti) | memory area/power/timing co-modeling 방법론 |
| [McPAT](https://dl.acm.org/doi/10.1145/1669112.1669172) | architecture 수준 power·area·timing 모델링 |
| [3D-stacked IC yield review](https://www.cse.cuhk.edu.hk/~qxu/xu-aspdac12.pdf) | die·bonding·TSV yield 분리와 KGD/TSV redundancy |
| [3D stacked memory yield](https://link.springer.com/article/10.1007/s10836-012-5314-3) | stacked die와 interconnect yield 모델 |
| [Negative-binomial yield](https://www.sciencedirect.com/science/article/abs/pii/S0360835202000086) | clustered defect 기반 수율 식 |
| [Roofline](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2008/EECS-2008-134.pdf) | operational intensity와 bandwidth/compute ceiling 분리 |
| [Micron HBM2E white paper](https://assets.micron.com/adobe/assets/urn:aaid:aem:275edf31-79e3-4b6c-8bbd-a233babe9281/renditions/original/as/micron-hbm2e-memory-wp.pdf) | HBM2E package와 TSV 맥락 교차 확인 |

## 열 분석

| 출처 | 프로젝트에서 참고하는 내용 |
|---|---|
| [HotSpot](https://github.com/uvahotspot/HotSpot/tree/f18831e48cef5d62580585cca0d7fab6c71bc3cc) | architecture-level compact thermal solver 기준 |
| [3D-ICE](https://github.com/esl-epfl/3d-ice/tree/4953952a1ef6d38807ff307212a6f15e5b2ef935) | 3D stacked IC transient thermal 모델 기준 |
| [3D-ICE paper](https://www.epfl.ch/labs/esl/wp-content/uploads/2018/12/3D-ICE_ICCAD2010.pdf) | 3D thermal simulation 방법론 |
| [HBM thermal study](https://jsts.org/jsts/XmlViewer/f436715) | HBM stack thermal resistance와 hotspot 맥락 |
| [NIST thermal conductivity monograph](https://nvlpubs.nist.gov/nistpubs/Legacy/MONO/nbsmonograph131.pdf) | 금속 물성 교차 확인 |
| [NIST metal conductivity data](https://www.nist.gov/publications/thermal-conductivity-aluminum-copper-iron-and-tungsten-temperatures-1-k-melting-point) | Al/Cu/W 열전도도 provenance |

## 중앙에 수집한 파일

| 수집본 | 원본 역할 |
|---|---|
| `archive/hbm2_sources.json` | HBM2 simulator·표준 출처 registry |
| `archive/thermal_sources.md` | thermal source registry |
| `archive/hardware_cost_sources.json` | 제조사·논문·cost/yield 출처 registry |
| `archive/groot_placement_sources.json` | GR00T·HBM·thermal·OpenROAD 출처 registry |
| `archive/normalization_source_evidence.csv` | 실제 normalization workload source evidence |
| `archive/normalization_reference_architecture_comparison.csv` | normalization architecture 비교 근거 |
| `archive/rtl_to_3d_source_log.log` | RTL-to-3D orchestration의 출처 포함 실행 로그 |
| `archive/reference_thermal_source_log.log` | reference thermal orchestration의 출처 포함 실행 로그 |

전체 원본 경로와 hash는 [`source_artifact_inventory.md`](source_artifact_inventory.md)를 확인합니다.

## 저장소의 canonical provenance

수집본은 탐색 편의를 위한 snapshot이고 다음 원본이 canonical evidence입니다.

- [`references/hbm2/SOURCES.json`](../../references/hbm2/SOURCES.json)
- [`references/thermal/SOURCES.md`](../../references/thermal/SOURCES.md)
- [`hardware_cost/sources.json`](../../hardware_cost/sources.json)
- [`experiment/gr00t_placement/sources.json`](../../experiment/gr00t_placement/sources.json)
- [`output/hbm2_arch/parameter_provenance.json`](../../output/hbm2_arch/parameter_provenance.json)
- [`output/hbm2_hardware_cost/source_traceability.md`](../../output/hbm2_hardware_cost/source_traceability.md)
- [`reports/groot_normalization/results/full_normalization_inventory/source_evidence.csv`](../../reports/groot_normalization/results/full_normalization_inventory/source_evidence.csv)
- [`reports/groot_normalization/results/reference_architecture_comparison.csv`](../../reports/groot_normalization/results/reference_architecture_comparison.csv)

도구가 자동 출력한 문서 링크, JSON Schema 식별자, 저장소 내부 URL, vendored `half.h`의 C++ reference 링크는 연구 근거 목록과 구분합니다.

