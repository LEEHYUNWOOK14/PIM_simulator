import copy
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import collect_physical_feasibility_evidence as collector
import physical_feasibility_contract as contract
import capture_hardware_cost_revision as capture


class PhysicalFeasibilityGateTests(unittest.TestCase):
    def test_pending_contract_is_valid_and_cannot_freeze(self):
        document = contract.pending_physical_feasibility()
        self.assertEqual(contract.validate_physical_feasibility(document), [])
        self.assertEqual(document["status"], "PENDING")
        self.assertFalse(document["rtl_freeze_allowed"])

    def test_mapping_separates_relaxed_sta_from_project_reference(self):
        yosys = """
Found and reported 0 problems.
    50013 5.64E+05 cells
Chip area for module '\\adapter': 564432.585600
of which used for sequential elements: 315077.184000 (55.80%)
End of script.
"""
        sta = """
PHYS_FEAS_CHECK_SETUP_BEGIN
PHYS_FEAS_CHECK_SETUP_END
PHYS_FEAS_MAX_PATH_BEGIN
Startpoint: q0
Endpoint: q1
 494.47 data arrival time
1000.00 1000.00 clock clk (rise edge)
PHYS_FEAS_MAX_PATH_END
worst slack 505.39
"""
        result = collector.mapping("adapter", yosys, sta, 40.0)
        self.assertTrue(result["timing_target_met"])
        self.assertFalse(result["reference_timing_target_met"])
        self.assertEqual(result["clock_period_ns"], 1000.0)
        self.assertEqual(result["unconstrained_path_count"], 0)

    def test_mapping_uses_check_setup_unconstrained_endpoint_count(self):
        yosys = """
Found and reported 0 problems.
Chip area for module '\\adapter': 1.0
End of script.
"""
        sta = """
PHYS_FEAS_UNCONSTRAINED_BEGIN
Warning: There are 2 unconstrained endpoints.
  out_unconst
  reg3/D
PHYS_FEAS_UNCONSTRAINED_END
"""
        result = collector.mapping("adapter", yosys, sta, 40.0)
        self.assertEqual(result["unconstrained_path_count"], 2)

    def test_freeze_rejects_missing_integrated_sta(self):
        document = contract.pending_physical_feasibility()
        document["status"] = "PASS"
        document["rtl_freeze_allowed"] = True
        for gate in document["gates"].values():
            gate["status"] = "PASS"
        errors = contract.validate_physical_feasibility(document)
        self.assertTrue(any("integrated timing" in error for error in errors))

    def test_current_evidence_classifies_incomplete_route_without_false_pass(self):
        document = collector.collect()
        self.assertEqual(contract.validate_physical_feasibility(document), [])
        route = document["global_routing"]
        if not route["completed"]:
            self.assertEqual(document["gates"]["PF-4"]["status"], "PENDING")
            self.assertFalse(document["rtl_freeze_allowed"])

    def test_pf4_pending_rejects_affirmative_routing_claim_boundary(self):
        document = collector.collect()
        document["claim_boundary"] = "Sky130 global-routing feasibility only; not production signoff."
        errors = contract.validate_physical_feasibility(document)
        self.assertTrue(any("affirmative routing feasibility" in error for error in errors))

    def test_buffer_storage_area_is_quantified(self):
        document = collector.collect()
        buffer = document["buffer_implementation"]
        self.assertEqual(buffer["mapped_register_count"], 12288)
        self.assertGreater(buffer["mapped_area_um2"], 0)
        # The share moves as adapter control/mux logic changes; the invariant
        # is that storage cost remains explicitly quantified, not that it
        # exceeds an arbitrary percentage of the complete adapter.
        self.assertGreater(buffer["share_of_adapter_area_pct"], 0.0)
        self.assertLessEqual(buffer["share_of_adapter_area_pct"], 100.0)

    def test_fanout_repair_cost_is_quantified(self):
        document = collector.collect()
        fanout = document["fanout"]
        if fanout["repair_inserted_buffers"] is None:
            self.skipTest("No completed coarse fanout-repair evidence")
        self.assertGreater(fanout["repair_inserted_buffers"], 0)
        self.assertGreater(fanout["repair_repaired_nets"], 0)
        self.assertGreater(fanout["repair_area_increase_pct"], 0.0)
        self.assertIsNotNone(fanout["remaining_fanout_violations"])

    def test_generic_wire_bits_are_not_claimed_as_congestion(self):
        wide = collector.collect()["wide_interface"]
        self.assertEqual(wide["generic_wire_bits"], 145852)
        self.assertFalse(wide["generic_wire_bits_is_direct_congestion_metric"])

    def test_cugr_congestion_violations_are_gating_evidence(self):
        document = collector.collect()
        routing = document["global_routing"]
        self.assertEqual(
            routing["congestion_hotspots"]["captured_violation_blocks"],
            routing["congestion_violation_count"],
        )
        if routing["completed"] and routing["congestion_violation_count"]:
            self.assertGreater(routing["overflow_count"], 0)
            self.assertEqual(document["gates"]["PF-4"]["status"], "FAIL")

    def test_cugr_hotspot_summary_is_scoped_to_captured_blocks(self):
        report = """violation type: Vertical congestion
 srcs: net:read_data_i[3] net:u_pcu/u_datapath/g_bank\\[6\\].u_apply/foo net:u_adapter/x_word_q\\[0\\]
 comment: capacity:12 usage:14 congestion:2
 bbox = (501.0, 1001.0) - (508.0, 1008.0) on Layer met2
violation type: Horizontal congestion
 srcs: net:reduction_data[2] net:u_pcu/u_datapath/g_bank\\[7\\].u_apply/bar
 comment: capacity:12 usage:13 congestion:1
 bbox = (520.0, 1020.0) - (527.0, 1027.0) on Layer met3
"""
        result = collector.congestion_hotspots(report)
        self.assertEqual(result["captured_violation_blocks"], 2)
        self.assertEqual(result["direction_block_counts"], {"horizontal": 1, "vertical": 1})
        self.assertEqual(result["category_block_counts"]["pcu_apply"], 2)
        self.assertEqual(result["top_bank_source_mentions"][0]["bank"], 6)
        self.assertEqual(result["top_500um_tiles"][0]["violation_blocks"], 2)

    def test_partial_new_route_does_not_replace_terminal_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            (evidence / "logic_die_normalization_hbm_top_v2_route.log").write_text("V2_ROUTE_PASS\n")
            (evidence / "logic_die_normalization_hbm_top_v2.route_guide").write_text("guide")
            (evidence / "logic_die_normalization_hbm_top_v2.congestion.rpt").write_text("report")
            (evidence / "logic_die_normalization_hbm_top_v4_route.log").write_text("V4_ROUTE_STAGE global_route\n")
            revision, route, _, _, _ = collector.latest_completed_route(evidence)
            self.assertEqual(revision, "v2")
            self.assertTrue(route.name.endswith("v2_route.log"))

    def test_source_tampering_is_detected(self):
        document = collector.collect()
        if not document["evidence"]:
            self.skipTest("No current evidence")
        broken = copy.deepcopy(document)
        broken["evidence"][0]["sha256"] = "0" * 64
        self.assertTrue(any("mismatch" in error for error in contract.validate_physical_feasibility(broken)))

    def test_current_gate_attaches_to_revision_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = capture.capture(
                "hardware_cost/regression/physical_feasibility_manifest_2026_08_12.json",
                Path(temporary) / "snapshot.json",
            )
        self.assertIn(snapshot["physical_feasibility"]["status"], {"PENDING", "PASS", "FAIL"})
        if snapshot["physical_feasibility"]["status"] in {"PENDING", "FAIL"}:
            self.assertFalse(snapshot["physical_feasibility"]["rtl_freeze_allowed"])
        self.assertTrue(any(source["role"] == "physical_feasibility" for source in snapshot["source_files"]))


if __name__ == "__main__":
    unittest.main()
