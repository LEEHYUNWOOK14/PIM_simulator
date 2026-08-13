export PLATFORM = sky130hd
export DESIGN_NICKNAME = normalization_hbm_adapter_feasibility
export DESIGN_NAME = normalization_hbm_boundary_adapter

STOB_REPO_ROOT ?= /mnt/c/orfs
export STOB_REPO_ROOT
export VERILOG_FILES = $(STOB_REPO_ROOT)/reports/groot_normalization/physical_feasibility/normalization_hbm_boundary_adapter_sky130.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_adapter_feasibility/constraint.sdc

export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 10
export PLACE_DENSITY = 0.45
export GPL_TIMING_DRIVEN = 0
export GPL_ROUTABILITY_DRIVEN = 1
export DONT_BUFFER_PORTS = 1
export RECOVER_POWER = 0
export ENABLE_DPO = 0
export SKIP_ANTENNA_REPAIR = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
export SKIP_INCREMENTAL_REPAIR = 1
