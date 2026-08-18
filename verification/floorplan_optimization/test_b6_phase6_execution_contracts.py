#!/usr/bin/env python3
"""Static fail-closed contract tests for the B6 placement-to-CTS transition."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class B6RouteContractTest(unittest.TestCase):
    def test_tcl_contains_one_route_and_one_iteration_guard(self) -> None:
        text = (ROOT / "verification/groot_normalization/wbq_quad_local_b6_global_route.tcl").read_text()
        self.assertEqual(text.count("global_route \\"), 1)
        self.assertIn("$iterations != 1", text)
        self.assertIn("WBQ_B6_SINGLE_GLOBAL_ROUTE PASS", text)
        self.assertNotIn("WBQ_B5", text)

    def test_runner_is_one_shot_pid_exact_and_compact(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b6_global_route.sh").read_text()
        for token in (
            "refusing duplicate",
            "global_route_invocations\": 1",
            "compute_pid",
            "wrapper_pid",
            "trap 'on_signal INT' INT",
            "trap 'on_signal TERM' TERM",
            "analyze_variant_residual_congestion.py",
            "--max-hotspots-in-output 500",
            "--max-windows-in-output 0",
            "targeted_placement_reopen_audit",
            "B6 targeted placement reopen audit is not PASS",
        ):
            self.assertIn(token, text)
        self.assertNotIn("quad_local_b5", text)

    def test_authorizer_pins_runner_parser_gate_and_diagnostics(self) -> None:
        text = (ROOT / "tools/authorize_b6_global_route.py").read_text()
        for token in (
            "route_runner",
            "route_tcl",
            "direct_numeric_parser",
            "strict_phase6_gate",
            "silence_snapshot_tool",
            "silence_compare_tool",
            "no_prior_route_artifact",
            "targeted_placement_reopen_audit",
            "targeted_reopen_anchor_count",
            "targeted_reopen_legality",
        ):
            self.assertIn(token, text)

    def test_targeted_reopen_audit_rechecks_both_anchors_and_legality(self) -> None:
        tcl = (ROOT / "verification/groot_normalization/audit_wbq_b6_targeted_placement.tcl").read_text()
        runner = (ROOT / "verification/groot_normalization/run_wbq_b6_targeted_placement_audit.sh").read_text()
        self.assertEqual(tcl.count("status={$actual_status}"), 1)
        self.assertIn('actual_status ne "LOCKED"', tcl)
        self.assertIn("anchors_verified != 2", tcl)
        self.assertIn("outside != 0", tcl)
        self.assertIn("unplaced != 0", tcl)
        self.assertIn('violations ne ""', tcl)
        for token in ("compute_pid", "refusing concurrent", "placement_violations", "B6_GLOBAL_ROUTE_AUTHORIZATION"):
            self.assertIn(token, runner)

    def test_strict_gate_has_all_four_release_conditions(self) -> None:
        text = (ROOT / "tools/decide_b6_phase6_strict_gate.py").read_text()
        for token in (
            "residual_congestion_zero",
            "overflow_edges_zero",
            "input_artifact_hashes_match",
            "explicit_phase6_pass",
            "BLOCKED_RESIDUAL_CONGESTION",
        ):
            self.assertIn(token, text)


class B6CtsContractTest(unittest.TestCase):
    def test_config_and_audit_are_b6_specific(self) -> None:
        config = (ROOT / "flow/designs/sky130hd/normalization_hbm_quad_local_b6/config.mk").read_text()
        audit = (ROOT / "verification/groot_normalization/audit_wbq_b6_phase6_cts.tcl").read_text()
        self.assertIn("DESIGN_NICKNAME = normalization_hbm_quad_local_b6", config)
        self.assertIn("WBQ_B6_PHASE6_CTS_AUDIT PASS", audit)
        self.assertIn("clock_net_count < 1", audit)
        self.assertIn('violations ne ""', audit)

    def test_cts_runner_records_exact_processes_and_traps_signals(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_b6_phase6_cts.sh").read_text()
        for token in (
            "do-4_1_cts",
            "repair_clock_nets",
            "launcher_pid",
            "compute_pid",
            "audit_compute_pid",
            "trap 'on_signal INT' INT",
            "trap 'on_signal TERM' TERM",
            "refusing concurrent B6 Phase 6 CTS",
        ):
            self.assertIn(token, text)
        self.assertNotIn("WBQ_B5", text)

    def test_cts_authorizer_pins_execution_and_monitoring_inputs(self) -> None:
        text = (ROOT / "tools/authorize_b6_phase6_cts.py").read_text()
        for token in (
            "strict_phase6_gate",
            "pre_cts_route_execution_report",
            "placement_hashes_match",
            "runner_has_signal_traps",
            "silence_snapshot_tool",
            "silence_compare_tool",
            "no_prior_cts_artifact",
        ):
            self.assertIn(token, text)


class SilenceDiagnosticContractTest(unittest.TestCase):
    def test_comparison_never_authorizes_termination(self) -> None:
        text = (ROOT / "tools/compare_openroad_stage_snapshots.py").read_text()
        self.assertIn('"termination_authorized": False', text)
        self.assertIn("cpu_seconds_delta", text)
        self.assertIn("io_delta", text)
        self.assertIn("artifact_delta", text)
        self.assertIn("thread_comparison", text)


class B6PostCtsRouteContractTest(unittest.TestCase):
    def test_post_cts_tcl_has_one_route_and_clock_aware_audit(self) -> None:
        tcl = (ROOT / "verification/groot_normalization/wbq_b6_phase6_post_cts_global_route.tcl").read_text()
        audit = (ROOT / "verification/groot_normalization/audit_wbq_b6_phase6_post_cts_route.tcl").read_text()
        self.assertEqual(tcl.count("global_route \\"), 1)
        self.assertIn("$iterations != 10", tcl)
        self.assertIn("WBQ_B6_PHASE6_POST_CTS_GLOBAL_ROUTE PASS", tcl)
        self.assertIn("clock_net_count < 1", audit)
        self.assertIn("!$has_routes", audit)
        self.assertIn('violations ne ""', audit)

    def test_post_cts_runner_is_single_shot_zero_only_and_pid_exact(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_b6_phase6_post_cts_global_route.sh").read_text()
        for token in (
            "global_route_invocation_limit\": 1",
            "refusing duplicate",
            "launcher_pid",
            "compute_pid",
            "audit_compute_pid",
            "refresh_compute_pid",
            "wait \"$launcher_pid\"",
            "--max-windows-in-output 0",
            'totals.get("rrr_residual") == 0',
            'totals.get("overflow_edges") == 0',
            "and not skipped",
            "trap 'on_signal TERM' TERM",
        ):
            self.assertIn(token, text)

    def test_post_cts_authorization_pins_every_execution_input(self) -> None:
        text = (ROOT / "tools/authorize_b6_phase6_post_cts_route.py").read_text()
        for token in (
            "cts_execution_report",
            "runner_records_exact_pids",
            "direct_numeric_compact_parser",
            "audit_requires_clock_and_routes",
            "silence_snapshot_tool",
            "silence_compare_tool",
            "no_prior_route_artifact",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
