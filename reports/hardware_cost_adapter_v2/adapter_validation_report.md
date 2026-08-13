# Hardware-cost adapter v2 validation

Status: **PASS**

|Check|Pass|Detail|
|---|---|---|
|three candidates and fifteen adapters present|True|`{'candidates': ['synthetic_low_area', 'synthetic_balanced', 'synthetic_high_performance'], 'adapters': 15}`|
|all adapter schemas, calibration gates, hashes, and conservation rules pass|True|`{'synthetic_low_area:area': [], 'synthetic_low_area:timing': [], 'synthetic_low_area:power': [], 'synthetic_low_area:workload': [], 'synthetic_low_area:thermal': [], 'synthetic_balanced:area': [], 'synthetic_balanced:timing': [], 'synthetic_balanced:power': [], 'synthetic_balanced:workload': [], 'synthetic_balanced:thermal': [], 'synthetic_high_performance:area': [], 'synthetic_high_performance:timing': [], 'synthetic_high_performance:power': [], 'synthetic_high_performance:workload': [], 'synth`|
|three Evidence Contract v2 snapshots pass|True|`{'synthetic_low_area': [], 'synthetic_balanced': [], 'synthetic_high_performance': []}`|
|each snapshot retains all five adapter sources|True|`five unique adapter roles per snapshot`|
|architecture remains provisional|True|`['synthetic_low_area', 'synthetic_balanced', 'synthetic_high_performance']`|
|synthetic power does not produce Energy/op|True|`Energy/op is N/A`|
|comparison covers all three candidates|True|`['synthetic_low_area', 'synthetic_balanced', 'synthetic_high_performance']`|
|comparison table exposes all five axes|True|`('mapped_area_um2', 'critical_path_ns', 'total_power_W', 'throughput_ops_s', 'peak_temperature_K')`|
|known synthetic deltas reproduced|True|`{'area_vs_baseline_pct': '25.0', 'critical_path_vs_baseline_pct': '-25.0', 'throughput_vs_baseline_pct': '80.0'}`|
|Energy/op comparison is unavailable|True|`{'value': '', 'policy': 'unavailable'}`|
|all comparison and validation artifacts exist|True|`('paper_revision_table.csv', 'paper_category_table.csv', 'paper_delta_table.csv', 'paper_regression_report.md', 'paper_revision_overview.png', 'paper_category_power.png', 'paper_timing_throughput.png', 'regression_summary.json', 'validation_report.json')`|
