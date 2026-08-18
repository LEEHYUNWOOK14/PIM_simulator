export PLATFORM = sky130hd
export DESIGN_NICKNAME = normalization_hbm_quad_local_b3
# B3 is a route-effort/config ECO.  Its functional netlist is deliberately
# identical to B2; the variant identity is carried by this config, manifests,
# and isolated output paths.
export DESIGN_NAME = logic_die_normalization_hbm_quad_local_b2_top

STOB_REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
export STOB_REPO_ROOT

export VERILOG_FILES = $(STOB_REPO_ROOT)/reports/groot_normalization/quad_local_b3/logic_die_normalization_hbm_quad_local_b2_top_sky130.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc
export POST_FLOORPLAN_TCL = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_quad_local_ab/post_floorplan_quad_fences.tcl

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

# Consumed by the isolated B3 global-route script.  One global-route process
# is allowed; internal CUGR RRR effort is increased from B2's 1 to 10.
export WBQ_B3_CUGR_CONGESTION_ITERATIONS = 10
