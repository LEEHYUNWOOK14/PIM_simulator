# B6 targeted anchor-lock ECO

Generated: `2026-08-18T01:57:43.973041+00:00`

## Root cause

The live B5 stack was inside `dpl::Opendp::anneal()`. OpenROAD's legacy diamond path performs 100 random swaps per grouped cell; 3,676,196 grouped cells therefore request 367,619,600 attempts per pass on one active thread (up to three passes).

## Recovery

B6 forbids full-design diamond legalization. Before the deterministic RUDY respread it locks only the two known tap-overlap buffers at their sealed, legal B2 origins and orientations. RUDY and the bounded negotiation legalizer then place all surrounding movable cells around those anchors. Post-RUDY and post-legalization checkpoints are retained.

B5 ended before routing and all protected A/B/B2 artifacts remain unchanged.
