#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
py="${GROOT_PYTHON:-}";if [[ -z "$py"&&-x /home/chandler/.cache/stob-groot-runtime/bin/python ]];then py=/home/chandler/.cache/stob-groot-runtime/bin/python;elif [[ -z "$py" ]];then py=python3;fi
GROOT_MIXED_VARIANT=C11 "$py" tools/prepare_groot_mixed_precision_rtl_vectors.py
lr="${HOME}/.local/iverilog/usr";if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";base="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi;out="${TMPDIR:-/tmp}/groot_mixed_precision_c11_trace.out"
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer4_interleaved.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_bank_apply4_pipe.sv rtl/mixed_precision_normalization_datapath_c11.sv verification/groot_normalization/groot_mixed_precision_trace_tb.sv)
args=(-g2012 -Wall -I. -DGROOT_C11 -s groot_mixed_precision_trace_tb -o "$out");if [[ -n "$base" ]];then args=(-B "$base" "${args[@]}");fi
"$iv" "${args[@]}" "${src[@]}"
vectors=reports/groot_normalization/results/mixed_precision_c11_rtl_vectors;results=reports/groot_normalization/results/mixed_precision_c11_rtl_results;mkdir -p "$results";log="$results/rtl_runs.log";:>"$log"
run_case(){ local p="$1" rows="$2" h="$3" v="$4" invh="$5" eps="$6";cmd=("$vp");if [[ -n "$base" ]];then cmd+=( -M "$base" );fi;cmd+=("$out" "+PROFILE=$p" "+ROWS=$rows" "+HIDDEN=$h" "+VECTORS=$v" "+INVH=$invh" "+EPS=$eps" "+MEANS=$vectors/${p}_mean_fp32.hex" "+INVS=$vectors/${p}_inv_std_fp32.hex" "+X=$vectors/${p}_x.hex" "+GAMMA=$vectors/${p}_gamma.hex" "+BETA=$vectors/${p}_beta.hex" "+MIXED=$vectors/${p}_mixed_expected.hex" "+PYTORCH=$vectors/${p}_pytorch_expected.hex" "+ACTUAL=$results/${p}_actual.hex");"${cmd[@]}"|tee -a "$log";}
count=0
while IFS=, read -r p rows h v invh eps mean inv class;do p="${p//$'\r'/}";rows="${rows//$'\r'/}";h="${h//$'\r'/}";v="${v//$'\r'/}";invh="${invh//$'\r'/}";eps="${eps//$'\r'/}";[[ "$p" == profile_id ]]&&continue;[[ -n "${GROOT_PROFILE_FILTER:-}"&&"$p" != "$GROOT_PROFILE_FILTER" ]]&&continue;run_case "$p" "$rows" "$h" "$v" "$invh" "$eps";count=$((count+1));done<"$vectors/cases.csv"
"$py" tools/analyze_groot_mixed_precision_rtl.py --variant C11
echo "GROOT_MIXED_PRECISION_C11_TRACE_REGRESSION PASS cases=$count accuracy_gate=6/6"
