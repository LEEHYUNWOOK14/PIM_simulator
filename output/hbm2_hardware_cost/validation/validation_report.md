# Hardware cost validation

Status: **PASS**

|Check|Pass|Detail|
|---|---|---|
|poisson analytic|True|`0.8187307530779818`|
|negative-binomial analytic|True|`0.823974609375`|
|Samsung HBM2 bandwidth identity|True|`307.2 GB/s`|
|cumulative silicon monotonic|True|`[484.8, 868.8, 1252.8]`|
|bond count monotonic|True|`[4, 8, 12]`|
|stack yield nonincreasing|True|`[0.5443231198080322, 0.3655886772414155, 0.24554364138393456]`|
|all yields valid|True|`0 < Y <= 1`|
|baseline normalized|True|`{'area': 1.0, 'package': 1.0, 'yield': 1.0, 'energy': 1.0}`|
|physical/logical channels separated|True|`8 physical, 64 logical simulator partitions`|
|capacity gate rejects 4Hi for 8GB workload|True|`{'4Hi_GB': 4.0, 'required_GB': 8.0}`|
|perfect inputs yield one|True|`[1.0, 1.0, 1.0, 1.0, 1.0]`|
|all parameter sources resolve|True|`[]`|
|invalid probability rejected|True|`assembly_yield=1.5`|
|all pipeline READMEs exist|True|`['hardware_cost/README.md', 'hardware_cost/area/README.md', 'hardware_cost/package/README.md', 'hardware_cost/yield/README.md', 'hardware_cost/power_performance/README.md', 'hardware_cost/integration/README.md']`|
|required outputs exist|True|`['integrated_metrics.json', 'design_comparison.csv', 'pareto_frontier.csv', 'uncertainty_summary.csv', 'uncertainty_samples.csv', 'hardware_cost_report.md', 'parameter_provenance.json', 'source_traceability.md', 'cost_indices.png', 'uncertainty_performance_per_cost.png', 'area/area_report.md', 'pack`|
|seeded uncertainty reproducible|True|`[{'scenario': 'hbm2_4hi_1stack', 'p05': 1.3996366236935671, 'p50': 1.571175729876553, 'p95': 1.79380038465123, 'best_rank_probability': 0.0, 'samples': 2000}, {'scenario': 'hbm2_8hi_1stack', 'p05': 1.0, 'p50': 1.0, 'p95': 1.0, 'best_rank_probability': 0.547, 'samples': 2000}, {'scenario': 'hbm2_12hi`|
|rank probabilities sum to one|True|`[0.0, 0.547, 0.0, 0.4295, 0.0235]`|
