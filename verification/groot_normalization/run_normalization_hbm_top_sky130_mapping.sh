#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
platform=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd
lib="$platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
yosys=/home/chandler/.local/oss-cad-suite/bin/yosys
results=reports/groot_normalization/physical_feasibility
mkdir -p "$results"
top=logic_die_normalization_hbm_top
variant="${MAPPING_VARIANT:-}"
suffix="${variant:+_${variant}}"
netlist="$results/${top}${suffix}_sky130.v"
log="$results/${top}${suffix}_sky130_yosys.log"
src=(
  rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv
  rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv
  rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv
  rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv
  rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv
  rtl/logic_die_normalization_pcu_top.sv rtl/normalization_hbm_boundary_adapter.sv
  rtl/normalization_writeback_quad_slice.sv
  rtl/logic_die_normalization_hbm_top.sv
)

# Keep hierarchy during ABC. The previous flat full-PCU experiment timed out;
# module-wise mapping is still a complete technology-mapped integrated netlist
# and prevents unrelated replicated arithmetic cones from becoming one ABC job.
"$yosys" -Q -l "$log" -p "
  read_liberty -lib -ignore_miss_func $lib;
  read_verilog -sv -I. ${src[*]};
  hierarchy -check -top $top;
  synth -noabc -top $top;
  opt_clean;
  dfflibmap -liberty $lib;
  abc -liberty $lib -D 100000 \
    -dont_use sky130_fd_sc_hd__lpflow_* \
    -dont_use sky130_fd_sc_hd__probe*;
  clean -purge;
  hilomap -singleton \
    -hicell sky130_fd_sc_hd__conb_1 HI \
    -locell sky130_fd_sc_hd__conb_1 LO;
  check -assert;
  stat -liberty $lib -top $top;
  write_verilog -noattr $netlist
"
grep -q "Found and reported 0 problems" "$log"
if grep -Eq '\$_(DFF|AND|OR|XOR|MUX|NOT)' "$netlist"; then
  echo "unmapped internal cells remain" >&2
  exit 1
fi
echo "NORMALIZATION_HBM_TOP_SKY130_MAPPING PASS"
