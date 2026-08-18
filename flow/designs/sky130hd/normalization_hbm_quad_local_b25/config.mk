export PLATFORM = sky130hd
export DESIGN_NICKNAME = normalization_hbm_quad_local_b25
export DESIGN_NAME = logic_die_normalization_hbm_quad_local_b2_top

STOB_REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
export STOB_REPO_ROOT

export VERILOG_FILES = $(STOB_REPO_ROOT)/reports/groot_normalization/quad_local_b25/logic_die_normalization_hbm_quad_local_b2_top_sky130.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc
export POST_FLOORPLAN_TCL = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_quad_local_ab/post_floorplan_quad_fences.tcl

# Preserve the established die/fence contract; B25 changes only the internal
# completion-descriptor transport structure.
export CORE_UTILIZATION = 33
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 10
export PLACE_DENSITY = 0.39
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
