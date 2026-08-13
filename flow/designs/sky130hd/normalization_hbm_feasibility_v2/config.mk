export PLATFORM = sky130hd
export DESIGN_NICKNAME = normalization_hbm_feasibility_v2
export DESIGN_NAME = logic_die_normalization_hbm_top

STOB_REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
export STOB_REPO_ROOT

# Reuse the dedicated, fully technology-mapped PCU + HBM-adapter netlist.
export VERILOG_FILES = $(STOB_REPO_ROOT)/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_sky130.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc

# The first 40%-core / 45%-placement-density trial legalized but produced a
# capped congestion report.  33% core utilization gives an approximately
# 88.8 mm^2 floorplan from the 29.29 mm^2 pre-repair cell area, remaining
# inside the project's 91.8 mm^2 usable logic-die proxy while adding routing
# whitespace.  Post-repair cell utilization is expected near 34%.
export CORE_UTILIZATION = 33
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 10
export PLACE_DENSITY = 0.36

# Coarse feasibility gate: deterministic placement and a separate real-capacity
# global-route congestion audit.  Timing/routability-driven placement exceeds
# the available host memory for this multi-million-cell prototype.
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
