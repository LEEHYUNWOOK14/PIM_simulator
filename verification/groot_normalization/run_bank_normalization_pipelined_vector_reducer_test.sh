#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; local_root="${HOME}/.local/iverilog/usr"
if command -v iverilog >/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";base="";else iv="${local_root}/bin/iverilog";vp="${local_root}/bin/vvp";base="$(find "${local_root}/lib" -type d -name ivl -print -quit)";fi
cd "${root}"
for format in 0 1;do
 for lanes in 2 4 8 16;do
  out="${TMPDIR:-/tmp}/bank_norm_pipe_f${format}_l${lanes}.out";args=(-g2012 -Wall -s bank_normalization_pipelined_vector_reducer_tb -Pbank_normalization_pipelined_vector_reducer_tb.LANES="${lanes}" -Pbank_normalization_pipelined_vector_reducer_tb.DATA_FORMAT="${format}" -o "${out}");
  if [[ -n "${base}" ]];then args=(-B "${base}" "${args[@]}");fi
  "${iv}" "${args[@]}" rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/bank_normalization_pipelined_vector_reducer.sv verification/groot_normalization/bank_normalization_pipelined_vector_reducer_tb.sv
  if [[ -n "${base}" ]];then "${vp}" -M "${base}" "${out}";else "${vp}" "${out}";fi
 done
done
