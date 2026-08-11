# Goal requirements audit

Audit date: 2026-08-06

Status meanings:

- `PROVED`: current artifact and verification directly satisfy the requirement.
- `PARTIAL`: useful evidence exists, but the full requirement is not yet proved.
- `PENDING_RTL`: requires the separately stabilized RTL or its new physical results.
- `MISSING_DATA`: requires manufacturer, foundry, package, or calibrated thermal data.

| Goal item | Status | Authoritative evidence | Remaining work |
|---|---|---|---|
| 1. GR00T identification | PARTIAL | `assumptions.json`, `sources.json`, `results/gr00t_workload_summary.json`, pinned revisions | Full-model inference or pretrained activation trace; quantitative whole-model coverage |
| 2. Source attribution | PROVED for current claims | `sources.json`, report 97 source-claim table | Add sources with every future physical/manufacturer input |
| 3. Preserve baseline GDS | PROVED | unchanged `output/output.gds`; reports 96/97 warnings | Re-run only after RTL is explicitly stabilized |
| 4. Quantified input assumptions | PARTIAL | `assumptions.json` low/base/high/distributions | Actual channel rate, PCU utilization, leakage, package stackup, vendor cost |
| 5. Cost function | PROVED for compact model | `analyze_placement.py`, `candidate_metrics.csv`, 13 unit tests | Replace proxies with routed/netlist/signoff metrics |
| 6. Weight profiles | PROVED | four profiles in `assumptions.json`; S7/S10 comparison | Stakeholder-approved weights after hardware constraints are known |
| 7. Sensitivity analysis | PROVED | OAT, 80 weight sweeps, 3 climate cases, 1,000 Monte Carlo, Spearman, Pareto, 8 PNG/SVG pairs | Latin hypercube is optional, not required after Monte Carlo |
| 8. Experiments | PARTIAL | GR00T normalization 2/2; 333-call LogicDieScheduler replay; compact thermal; existing OpenROAD results | VCD/SAIF, new OpenROAD/OpenSTA, calibrated 3D thermal |
| 9. Placement search | PARTIAL | 333 candidates, coarse/fine search, exclusions, baseline/provisional JSON | No final recommendation JSON or KLayout update until all gates pass |
| 10. Reports/reproducibility | PROVED for pre-RTL stage | reports 96/97, prompts, environment, manifest, logs, CSV/JSON, PNG/SVG | Final post-RTL report remains required |
| 11. Terminology | PROVED | report 97 section 10 covers all named terms | Keep definitions in final report |
| 12. Result gates | PROVED as failure, not final success | `summary.json/robustness_gate`; zero signoff-feasible candidates | Close timing, improve baseline, pass top-k stability, visually validate final placement |
| 13. Final artifacts | PARTIAL | assumptions, sources, code/tests, workload summary, 333-request GR00T scheduler trace, candidate CSV, sensitivity/Pareto/graphs, baseline/provisional JSON, reports | final recommendation JSON, updated KLayout config, manufacturer-data checklist refinement |

## Current gate evidence

- Candidate-model constraints: 293/333 pass; 40 fail the 10 ns MET1 delay proxy.
- Signoff hard constraints: 0/333 pass because local OpenROAD slack is `-35.650 ns`.
- Balanced improvement over center: 0%, below the required 1%.
- Provisional center top-5 rate: 97.2%, above the required 80%; the other gates still fail.
- Final recommendation flag: `false`.

The active goal is not complete. The current work proves that a final placement must be withheld; it
does not prove that the center or any other coordinate is the final optimum.
