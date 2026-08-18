# B7 lower-max-phi recovery

Generated: `2026-08-18T03:32:43.571502+00:00`

B6 is sealed as a pre-route `GPL-0307` tool failure. It produced no placement checkpoint, invoked no audit or global route, and preserved every frozen artifact hash.

B7 changes exactly one independent variable: `global_placement -max_phi_coef` from `1.05` to `1.01`. This directly follows the installed OpenROAD diagnostic. RTL, mapped netlist, SDC, fences, RUDY parameters, anchor locks, detailed-placement policy, and route policy remain unchanged.

B7 requires a fresh input-reopen/checkpoint smoke and a fresh hash-pinned physical authorization before compute.
