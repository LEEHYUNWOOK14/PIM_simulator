import json
import math
import unittest
from pathlib import Path

import analyze_placement as analysis


ROOT = Path(__file__).resolve().parent


class PlacementAnalysisTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg = analysis.load_config(ROOT / "assumptions.json")

    def test_weight_profiles_sum_to_one(self):
        for name, weights in self.cfg["cost_profiles"].items():
            self.assertAlmostEqual(sum(weights.values()), 1.0, places=12, msg=name)
            self.assertEqual(set(weights), set(analysis.METRICS))

    def test_center_is_feasible(self):
        self.assertEqual(analysis.candidate_is_feasible(0.0, 0.0, self.cfg), (True, ""))

    def test_die_boundary_is_rejected(self):
        feasible, reason = analysis.candidate_is_feasible(4.0, 0.0, self.cfg)
        self.assertFalse(feasible)
        self.assertEqual(reason, "die_boundary")

    def test_channel_width_is_hbm2_1024_bits(self):
        geom = self.cfg["package_geometry"]
        total = int(analysis.value(geom, "hbm_channel_count") *
                    analysis.value(geom, "channel_data_width_bits"))
        self.assertEqual(total, 1024)

    def test_elmore_delay_is_nonnegative_and_grows_with_distance(self):
        center = analysis.electrical_metrics((0.0, 0.0), self.cfg)
        offset = analysis.electrical_metrics((2.0, 0.0), self.cfg)
        self.assertGreaterEqual(center["delay_ps"], 0.0)
        self.assertGreater(offset["delay_ps"], center["delay_ps"])

    def test_reliability_proxy_monotonic_with_temperature(self):
        low = {"max_temp_c": 50.0, "mean_temp_c": 40.0,
               "max_gradient_c_per_mm": 1.0, "wire_um": 1.0,
               "delay_ps": 1.0, "wire_skew_um": 1.0, "tsv_distance_um": 1.0,
               "tsv_count": 1024, "tsv_keepout_area_mm2": 1.0,
               "tsv_violation_penalty": 0.0, "congestion_ratio": 0.5,
               "wire_power_mw": 1.0, "area_proxy_mm2": 1.0}
        high = dict(low, max_temp_c=70.0)
        self.assertGreater(analysis.raw_costs(high, self.cfg)["reliability"],
                           analysis.raw_costs(low, self.cfg)["reliability"])

    def test_thermal_limit_exceedance_has_explicit_penalty(self):
        limit = analysis.value(self.cfg["thermal"], "temperature_limit_c")
        base = analysis.electrical_metrics((0.0, 0.0), self.cfg)
        below = dict(base, max_temp_c=limit - 1.0, mean_temp_c=60.0,
                     max_gradient_c_per_mm=2.0)
        above = dict(below, max_temp_c=limit + 1.0)
        self.assertGreater(analysis.raw_costs(above, self.cfg)["thermal"],
                           analysis.raw_costs(below, self.cfg)["thermal"])

    def test_tsv_cost_preserves_count_keepout_and_violation(self):
        base = analysis.electrical_metrics((0.0, 0.0), self.cfg)
        base.update(max_temp_c=50.0, mean_temp_c=40.0, max_gradient_c_per_mm=1.0)
        violated = dict(base, tsv_violation_penalty=1.0)
        self.assertGreater(analysis.raw_costs(violated, self.cfg)["tsv"],
                           analysis.raw_costs(base, self.cfg)["tsv"])

    def test_source_ids_resolve(self):
        with (ROOT / "sources.json").open(encoding="utf-8") as stream:
            sources = json.load(stream)
        ids = {source["id"] for source in sources["sources"]}
        self.assertTrue({"S1", "S3", "S4", "S5", "S6", "L1", "L2",
                         "A1", "A4", "A5", "A6"}.issubset(ids))

    def test_fixed_normalization_is_not_candidate_minmax(self):
        row = {"raw": {metric: 0.0 for metric in analysis.METRICS}}
        row["raw"]["wire"] = 3000.0
        analysis.normalize_rows([row], self.cfg)
        self.assertAlmostEqual(row["norm"]["wire"], 0.5)

    def test_workload_traffic_is_derived_from_profile(self):
        summary = analysis.workload_summary(self.cfg)
        self.assertEqual(summary["projected_cycles"], 2040382)
        self.assertEqual(summary["minimum_input_plus_output_bytes"], 232939520)
        self.assertFalse(summary["full_model_inference"])

    def test_cost_model_is_explicitly_partial_and_scenario_ordered(self):
        records = analysis.manufacturing_cost_scenarios(self.cfg)
        costs = [record["partial_logic_plus_package_cost_usd"] for record in records]
        self.assertLess(costs[0], costs[1])
        self.assertLess(costs[1], costs[2])
        self.assertTrue(all("HBM_DRAM_die_cost" in record["excludes"] for record in records))

    def test_negative_openroad_slack_blocks_signoff_gate(self):
        thermal = analysis.ThermalModel(self.cfg)
        row = analysis.evaluate_candidates([(0.0, 0.0)], self.cfg, thermal)[0]
        self.assertTrue(row["candidate_constraints_satisfied"])
        self.assertFalse(row["hard_constraints_satisfied"])
        self.assertIn("global_rtl_timing_not_closed", row["hard_constraint_violations"])

    def test_input_table_has_units_distributions_and_sources(self):
        records = analysis.input_assumption_records(self.cfg)
        expected = sum(
            isinstance(entry, dict) and "base" in entry
            for group in ("workload", "package_geometry", "electrical", "thermal",
                          "reserved_areas", "manufacturing_cost")
            for entry in self.cfg[group].values()
        )
        self.assertEqual(len(records), expected)
        for record in records:
            self.assertTrue(record["unit"])
            self.assertTrue(record["distribution_or_sweep"])
            self.assertTrue(record["source_ids"])

    def test_signal_delay_uses_platform_met1_rc(self):
        electrical = self.cfg["electrical"]
        met1 = self.cfg["routing_layer_rc"]["met1"]
        self.assertEqual(analysis.value(electrical, "signal_resistance_kohm_per_um"),
                         met1["resistance_kohm_per_um"])
        self.assertEqual(analysis.value(electrical, "signal_capacitance_pf_per_um"),
                         met1["capacitance_pf_per_um"])


if __name__ == "__main__":
    unittest.main()
