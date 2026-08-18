# B5 minimum legalization ECO

Generated: `2026-08-17T13:43:05.333034+00:00`

## Decision

`SELECT_B5_DIAMOND_LEGALIZER_ECO`

B4 is sealed before routing: negotiation legalization left four illegal cells and two actual tapcell overlaps. B5 preserves the same RUDY respread and changes only detailed placement to the region-aware diamond legalizer.

Targets: `load_slew427175` vs `TAP_TAPCELL_ROW_916_299625`, and `wire440835` vs `TAP_TAPCELL_ROW_573_187675`.

Current `authorizes=[]`; fresh cheap gates are required.
