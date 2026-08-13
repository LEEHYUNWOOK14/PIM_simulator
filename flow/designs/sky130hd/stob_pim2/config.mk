export PLATFORM               = sky130hd

export DESIGN_NICKNAME        = stob_pim2
export DESIGN_NAME            = full_pim_system_top

# The repository path is supplied by flow/run_flow.ps1.  Keep the historical
# Resolve the repository from this config; callers may still override it.
STOB_REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
export STOB_REPO_ROOT

# The submitted physical instance is a reduced, fully integrated Full-PIM
# configuration. It retains bank-side PIM, logic PCU, shared weight buffer,
# epoch/coalescing control, cross-channel reduction, and result routing.
export VERILOG_TOP_PARAMS     = CHANNELS 1 BANKS 1 PIM_BLOCKS 1 PCUS 1 \
                                ROWS 1 COLS 1 DATA_WIDTH 16 CRF_DEPTH 2 \
                                WEIGHT_BUFFER_BYTES 16

STOB_RTL_SOURCES := $(sort $(wildcard $(STOB_REPO_ROOT)/rtl/*.sv))
# Ignore OneDrive conflict copies.  They define the same module under a host-
# suffixed filename and are not authoritative RTL inputs.
export VERILOG_FILES          = $(foreach file,$(STOB_RTL_SOURCES),$(if $(findstring -DESKTOP-,$(notdir $(file))),,$(file)))
export VERILOG_INCLUDE_DIRS   = $(STOB_REPO_ROOT)

export SDC_FILE               = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/constraint.sdc
export PRE_SYNTH_TCL          = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl
export PRE_FLOORPLAN_TCL      = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl
export PRE_GLOBAL_PLACE_SKIP_IO_TCL = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl
export PRE_GLOBAL_PLACE_TCL    = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl
export PRE_DETAIL_ROUTE_TCL    = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl
export POST_FINAL_REPORT_TCL   = $(STOB_REPO_ROOT)/flow/designs/sky130hd/stob_pim2/openroad_compat.tcl

export CORE_UTILIZATION       = 30
export CORE_ASPECT_RATIO      = 1
export CORE_MARGIN            = 2
export PLACE_DENSITY          = 0.35

# MATCH_CELL_FOOTPRINT is intentionally unset: the installed OpenROAD predates
# that optional repair_design/repair_timing flag.
export REMOVE_ABC_BUFFERS     = 1
export SKIP_REPORT_METRICS    = 1
export ENABLE_PLACE_REPAIR_TIMING = 0
export ENABLE_DPO              = 0
export SKIP_CTS_REPAIR_TIMING  = 1
export CTS_ARGS                = -sink_clustering_enable
export SKIP_INCREMENTAL_REPAIR = 1
export SKIP_ANTENNA_REPAIR     = 1
export RECOVER_POWER           = 0
