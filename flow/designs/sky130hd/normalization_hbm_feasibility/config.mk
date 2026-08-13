export PLATFORM = sky130hd
export DESIGN_NICKNAME = normalization_hbm_feasibility
export DESIGN_NAME = logic_die_normalization_hbm_top

STOB_REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
export STOB_REPO_ROOT

# Reuse the fully technology-mapped hierarchical netlist produced by the
# dedicated mapping gate. This bypasses the historically failing flat ABC job.
export VERILOG_FILES = $(STOB_REPO_ROOT)/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_sky130.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = $(STOB_REPO_ROOT)/flow/designs/sky130hd/normalization_hbm_feasibility/constraint.sdc

# 26.8 mm^2 mapped cell area at 40% core utilization gives a roughly 67 mm^2
# floorplan, below the project's 91.8 mm^2 usable logic-die proxy budget.
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 10
export PLACE_DENSITY = 0.45

# This target is a coarse physical-feasibility gate, not a sign-off timing run.
# Timing/routability-driven Nesterov placement on this 3.3 M-cell prototype
# exceeds the available WSL memory.  Keep placement deterministic and let the
# separate global-router congestion report be the routability gate.
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
