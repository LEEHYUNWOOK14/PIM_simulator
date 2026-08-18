# B8 higher-DRC-penalty recovery

Generated: `2026-08-18T06:24:33.899122+00:00`

B7 is sealed as a pre-route placement-legality failure. Its global placement passed and its immutable post-RUDY checkpoint is retained, but seven movable buffers overlap fixed tapcells after the negotiation legalizer.

B8 reopens that exact B7 RUDY checkpoint and changes one independent variable: `detailed_placement -drc_penalty` from `20` to `100`. Max displacement, search windows, fences, anchors, SDC, netlist, RTL, and downstream route policy remain unchanged. Full-design diamond legalization remains forbidden.

A fresh input-reopen/checkpoint smoke and hash-pinned physical authorization are required before compute.
