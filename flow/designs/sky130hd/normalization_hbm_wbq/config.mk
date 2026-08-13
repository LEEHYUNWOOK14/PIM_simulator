export PLATFORM = sky130hd
export DESIGN_NICKNAME = normalization_hbm_wbq
export DESIGN_NAME = logic_die_normalization_hbm_top

STOB_REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
export STOB_REPO_ROOT

# Phase-2-gated writeback-quad technology-mapped netlist.  This nickname keeps
# every checkpoint separate from the historical pre-slice V2/V4 experiments.
export VERILOG_FILES = $(STOB_REPO_ROOT)/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_sky130.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc

# Match the historical V2 capacity envelope for a controlled architectural A/B:
# 33% core utilization remains inside the 91.8 mm^2 logic-die research proxy.
export CORE_UTILIZATION = 33
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 10
export PLACE_DENSITY = 0.36

export GPL_TIMING_DRIVEN = 0
export GPL_ROUTABILITY_DRIVEN = 0
export DONT_BUFFER_PORTS = 1
export REMOVE_ABC_BUFFERS = 1
export TNS_END_PERCENT = 100
export RECOVER_POWER = 0
export SKIP_ANTENNA_REPAIR = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
export SKIP_INCREMENTAL_REPAIR = 1
export ENABLE_DPO = 0
export DETAILED_ROUTE_END_ITERATION = 0

