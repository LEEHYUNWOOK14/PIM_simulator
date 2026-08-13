export PLATFORM = sky130hd
export DESIGN_NICKNAME = b0_bank_only_baseline
export DESIGN_NAME = full_pim_system_top

STOB_REPO_ROOT ?= /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2
export STOB_REPO_ROOT

export VERILOG_TOP_PARAMS = CHANNELS 1 BANKS 2 PIM_BLOCKS 1 PCUS 1 \
  ROWS 1 COLS 1 DATA_WIDTH 32 CRF_DEPTH 2 WEIGHT_BUFFER_BYTES 16 \
  ENABLE_LOGIC_DIE_PCU 0 ENABLE_NORMALIZATION_ENGINE 0

export VERILOG_FILES = \
  $(STOB_REPO_ROOT)/rtl/pim_command_decoder.sv \
  $(STOB_REPO_ROOT)/rtl/fp16_add.sv \
  $(STOB_REPO_ROOT)/rtl/fp16_mul.sv \
  $(STOB_REPO_ROOT)/rtl/fp16_vector_add.sv \
  $(STOB_REPO_ROOT)/rtl/pim_vector_alu.sv \
  $(STOB_REPO_ROOT)/rtl/pim_crf.sv \
  $(STOB_REPO_ROOT)/rtl/dram_bank_array_model.sv \
  $(STOB_REPO_ROOT)/rtl/bank_pim_core.sv \
  $(STOB_REPO_ROOT)/rtl/bank_side_pim_subsystem.sv \
  $(STOB_REPO_ROOT)/rtl/logic_die_link_arbiter.sv \
  $(STOB_REPO_ROOT)/rtl/channel_tsv_interconnect.sv \
  $(STOB_REPO_ROOT)/rtl/logic_epoch_barrier.sv \
  $(STOB_REPO_ROOT)/rtl/logic_shared_buffer.sv \
  $(STOB_REPO_ROOT)/rtl/logic_pcu.sv \
  $(STOB_REPO_ROOT)/rtl/logic_pcu_scheduler.sv \
  $(STOB_REPO_ROOT)/rtl/logic_command_coalescer.sv \
  $(STOB_REPO_ROOT)/rtl/logic_operand_context_buffer.sv \
  $(STOB_REPO_ROOT)/rtl/cross_channel_reduction_network.sv \
  $(STOB_REPO_ROOT)/rtl/logic_result_router.sv \
  $(STOB_REPO_ROOT)/rtl/logic_die_pim_top.sv \
  $(STOB_REPO_ROOT)/rtl/fp16_rsqrt_lut256.sv \
  $(STOB_REPO_ROOT)/rtl/logic_normalization_scalar_engine.sv \
  $(STOB_REPO_ROOT)/rtl/logic_normalization_reduction_engine.sv \
  $(STOB_REPO_ROOT)/rtl/full_pim_system_top.sv
export VERILOG_INCLUDE_DIRS = $(STOB_REPO_ROOT)

export SDC_FILE = $(STOB_REPO_ROOT)/b0_baseline_experiment/config/constraint.sdc
export PRE_SYNTH_TCL = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl
export PRE_FLOORPLAN_TCL = $(PRE_SYNTH_TCL)
export PRE_GLOBAL_PLACE_SKIP_IO_TCL = $(PRE_SYNTH_TCL)
export PRE_GLOBAL_PLACE_TCL = $(PRE_SYNTH_TCL)
export PRE_DETAIL_ROUTE_TCL = $(PRE_SYNTH_TCL)
export POST_FINAL_REPORT_TCL = $(PRE_SYNTH_TCL)

export CORE_UTILIZATION = 30
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.35

export REMOVE_ABC_BUFFERS = 1
export SKIP_REPORT_METRICS = 1
export ENABLE_PLACE_REPAIR_TIMING = 0
export ENABLE_DPO = 0
export SKIP_CTS_REPAIR_TIMING = 1
export CTS_ARGS = -sink_clustering_enable
export SKIP_INCREMENTAL_REPAIR = 1
export SKIP_ANTENNA_REPAIR = 1
export RECOVER_POWER = 0
