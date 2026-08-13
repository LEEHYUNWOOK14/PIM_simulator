# Parameterized Multi-row Throughput Prototype: Architecture Contract

## 목표

정확도 검증이 완료된 C11 FP32 mixed-precision arithmetic을 유지하면서 다음 설계공간을 실제 RTL로 판정한다.

- `LANES_PER_BANK = 4, 8, 16`
- `SCALAR_ENGINES = 4, 8, 16`
- 여러 row가 reduction, scalar, apply stage에 동시에 존재하는 multi-row overlap
- actual GR00T 6-profile bit-exact 검증
- component 및 가능한 full-top Sky130 합성/STA/면적 비교

production replay/DRAM write-back은 이 prototype의 범위가 아니다.

## 기존 C11의 병목

기존 trace driver는 row마다 다음 순서를 직렬 실행한다.

```text
begin/reduce → scalar configured 대기 → apply/output 완료 → 다음 row
```

하지만 RTL 포트는 reduce와 apply가 분리되어 있어 다음 파이프라인이 가능하다.

```text
row n+1: reduce
row n  : global/scalar
row n-1: apply/output
```

기존 top의 실제 제약은 단일 `mode_q`와 단일 scalar, tag별 metadata 저장 부재다. bank reducer 전체를 row 수만큼 복제하는 것은 최소 구조가 아니다.

## Prototype 구조

### Bank reducer

- `LANES=4/8/16` elaboration-time parameter
- lane tree는 FP32 balanced order
- vector partial 뒤 4-way interleaved accumulator 유지
- 한 bank에서 row 하나를 reduce하지만 partial이 global stage로 handoff된 즉시 다음 row 시작 가능

### Global reducer

- 기존 16-bank four-level FP32 pipelined tree 재사용
- tag를 보존
- bank partial row interval보다 짧은 service latency를 목표로 유지

### Row context table

tag별 다음 metadata 저장:

- RMSNorm/LayerNorm mode
- `inv_hidden`
- `epsilon`
- allocation validity

global result가 scalar engine에 accepted될 때 context를 consume한다. 동일 tag 중복과 lookup miss는 protocol error다.

### Scalar engine array

- C11 `mixed_precision_scalar_nr2_pipe`를 4/8/16개 복제
- request는 ready engine에 round-robin dispatch
- response는 apply-config readiness에 맞춰 arbitrate
- engine output backpressure 지원

### Bank apply

- `LANES=4/8/16` parameter
- C11의 FP32 center/norm/scale/shift와 final BF16 RNE 유지
- 한 bank apply context는 한 row지만, 마지막 vector가 accepted되면 다음 scalar context를 받을 수 있음
- reservation FIFO로 arbitrary output backpressure 유지

## Numerical contract

lane 폭이 바뀌면 FP32 reduction tree의 association 순서도 바뀐다. 따라서 다음을 구분한다.

1. 각 lane 구성 RTL은 해당 lane-order numerical model과 bit-exact해야 한다.
2. 각 lane 구성 numerical result는 기존 `max_abs <= 0.025` PyTorch gate를 6/6 통과해야 한다.

4-lane C11 expected output을 8/16-lane RTL의 bit-exact golden으로 재사용하지 않는다.

## 외부 prototype interface

prototype은 메모리 controller 대신 독립 stream을 사용한다.

- row allocation/begin stream
- bank-parallel reduction stream
- bank-parallel apply stream
- bank-parallel output stream

testbench scheduler가 tag별 dependency를 지키며 reduce와 apply를 동시에 구동한다. 이 cycle은 arithmetic/control core throughput이며 DRAM timing이 아니다.

## 판정 기준

### Accuracy gate

- 6/6 profiles PASS
- RTL vs lane-specific model mismatch 0
- PyTorch `max_abs <= 0.025`

### RTL gate

- reset/backpressure/tag protocol PASS
- no duplicate/lost output
- parameter 4/8/16 elaboration PASS

### Performance gate

- actual trace cycle 측정
- full-top 또는 hierarchy-preserving component PPA evidence
- actual traffic 포함 GPU 대비 projected/measured speedup 최소 1.30x

`1.0 < speedup < 1.3`은 불확실성 여유가 부족하므로 production GO로 인정하지 않는다.

## 우선 구현 순서

1. generic reducer/apply
2. FP32 scalar engine array
3. metadata context table
4. overlap integration top
5. synthetic multi-row protocol test
6. actual trace driver/model
7. 4/8/16 × scalar-engine DSE

