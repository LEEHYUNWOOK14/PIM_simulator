# B4 minimum physical ECO decision

Generated: `2026-08-17T11:32:38.185412+00:00`

## Decision

`SELECT_B4_RUDY_ROUTABILITY_RESPREAD_ECO`

B3 is sealed at residual 5,641 / 2,988 overflow edges after exactly one global-route invocation. Extra RRR is therefore rejected. B4 keeps the B2 netlist and fences and changes only placement: a RUDY-based routability respread from the immutable B2 placed checkpoint, followed by legalization.

## Exact targets

- Central completion/context cluster: `(4878.3,4595.4)-(4995.6,4698.9)`
- Central scalar-return cluster: `(4367.7,4215.9)-(4761.0,4485.0)`
- Q1 bank3 reduction overflow=2: `(7445.1,1414.5)-(7452.0,1421.4)`

## Gates

B4 placement remains unauthorized until fresh cheap 9/9, mapped 20/20, workload 6/6, and comparator/locality checks all pass. B4 global route is limited to one invocation with one RRR iteration.

Current `authorizes=[]`.
