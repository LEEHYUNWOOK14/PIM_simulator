# HBM2 PIM Architecture Model

> **HBM2 PIM architectural visualization - not signoff layout**

Generated: 2026-08-06T07:56:39.609508+00:00

## Structure

- HBM2 stacks: 1
- DRAM dies per stack: 8
- Physical channels per stack: 8 x 128-bit = 1024-bit
- Pseudo-channel mode: False (0 pseudo-channels/stack when enabled)
- Logical simulator partitions: 64 (`simulator_only_logical_partition`)
- Banks per physical channel: 16
- Bank-side PIM blocks per physical channel: 8
- Bank-to-PIM mapping: [{"pim_block": 0, "banks": [0, 8]}, {"pim_block": 1, "banks": [1, 9]}, {"pim_block": 2, "banks": [2, 10]}, {"pim_block": 3, "banks": [3, 11]}, {"pim_block": 4, "banks": [4, 12]}, {"pim_block": 5, "banks": [5, 13]}, {"pim_block": 6, "banks": [6, 14]}, {"pim_block": 7, "banks": [7, 15]}]
- TSV groups: 8
- RTL functional blocks detected: 8

The 64 logical simulator channels are **not** represented as 64 physical HBM2 channels. The default model retains the standard eight physical channels and records the 64-way simulator partition separately.

## Evidence boundaries

- Standard-derived: stack interface organization (8 physical channels, 128-bit/channel, 1024-bit total).
- SAIT/project-derived: bank, row/column, timing and PIM block parameters.
- DRAMsim3: independent open-source cross-check for organization, timing, refresh and address mapping.
- RTL-derived: module names and parameter expressions only; no gate placement or routed wire is claimed.
- Estimated/illustrative: all package dimensions, die thicknesses, bump/TSV sizes and floorplan placement.

No public manufacturing HBM2 DRAM-cell GDS, PHY GDS, exact TSV floorplan, or signoff layout is used. See `parameter_provenance.json` and `cross_validation_report.md`.
