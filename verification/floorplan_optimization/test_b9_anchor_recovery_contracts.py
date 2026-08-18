#!/usr/bin/env python3
"""Static fail-closed checks for the B8-to-B9 anchor recovery."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def block(text: str, command: str) -> str:
    match = re.search(rf"^{command} \\\n(.*?)(?=^puts )", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"missing {command}")
    return command + " \\\n" + match.group(1)


class B9AnchorRecoveryContractTest(unittest.TestCase):
    def test_selector_seals_b8_and_selects_seven_added_anchors(self) -> None:
        text = (ROOT / "tools/select_b9_seven_anchor_recovery.py").read_text()
        for token in (
            "design_legality_failure",
            '"single_independent_variable": "locked_anchor_targets"',
            '"before": 2',
            '"after": 9',
            '"next_stage": "B9_SMOKE"',
            "WBQ_B9_B2_ANCHOR_CANDIDATES PASS count=7",
        ):
            self.assertIn(token, text)

    def test_dpl_command_is_unchanged_and_anchor_set_is_nine(self) -> None:
        b8 = (ROOT / "verification/groot_normalization/wbq_quad_local_b8_drc_place.tcl").read_text()
        b9 = (ROOT / "verification/groot_normalization/wbq_quad_local_b9_anchor_place.tcl").read_text()
        self.assertEqual(block(b8, "detailed_placement"), block(b9, "detailed_placement"))
        self.assertEqual(len(re.findall(r"^  \{u_b2_implementation/", b9, re.MULTILINE)), 9)
        self.assertIn("anchor_targets=9 added_targets=7", b9)
        self.assertNotIn("global_placement", b9)
        self.assertNotIn("-use_diamond_legalizer", b9)

    def test_smoke_is_fresh_two_process_and_nine_anchor(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_b9_anchor_smoke.sh").read_text()
        for token in (
            "SELECT_B9_SEVEN_ADDITIONAL_ANCHORS_ECO",
            "anchor_targets=9",
            "anchors=9 offenders=7",
            "compute_pid",
            "audit_compute_pid",
            "trap 'on_signal TERM' TERM",
            "B9_PHYSICAL_AUTHORIZATION",
        ):
            self.assertIn(token, text)

    def test_authorizer_pins_b8_failure_anchor_evidence_and_runner(self) -> None:
        text = (ROOT / "tools/authorize_b9_physical_run.py").read_text()
        for token in (
            "b8_sealed_legality_failure_before_route",
            "b8_same_seven_offenders_at_penalty_100",
            "independent_b2_anchor_measurement_pinned",
            "detailed_placement_command_unchanged",
            "only_anchor_target_set_changed",
            "fresh_smoke_inputs_match",
            "no_prior_b9_placement_attempt",
            '["B9_PLACEMENT"]',
        ):
            self.assertIn(token, text)

    def test_placement_runner_is_one_shot_pid_exact(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b9_placement.sh").read_text()
        for token in (
            "B9 placement has already been attempted",
            "WBQ_B9_PLACE_SINGLE_CHANGE=locked_anchor_targets",
            "WBQ_B9_PLACE_LOCKED_ANCHOR_TARGETS=9",
            "WBQ_B9_PLACE_DRC_PENALTY=100",
            "launcher_pid",
            "compute_pid",
            "audit_compute_pid",
            "trap write_unexpected_fail EXIT",
            "B9_TARGETED_PLACEMENT_REOPEN_AUDIT",
        ):
            self.assertIn(token, text)

    def test_numeric_and_targeted_reopen_require_nine_locked_anchors(self) -> None:
        analyzer = (ROOT / "tools/analyze_b9_placement_log.py").read_text()
        audit_tcl = (ROOT / "verification/groot_normalization/audit_wbq_b9_targeted_placement.tcl").read_text()
        audit_runner = (ROOT / "verification/groot_normalization/run_wbq_b9_targeted_placement_audit.sh").read_text()
        for token in (
            "nine_anchor_runtime_marker",
            "nine_verified_locked_anchors",
            "negotiation_pre_mirroring_remaining_violations",
            "B9_TARGETED_PLACEMENT_REOPEN_AUDIT",
        ):
            self.assertIn(token, analyzer)
        self.assertEqual(len(re.findall(r"^  \{u_b2_implementation/", audit_tcl, re.MULTILINE)), 9)
        for token in ('actual_status ne "LOCKED"', "anchors_verified != 9", "outside != 0", "unplaced != 0", 'violations ne ""'):
            self.assertIn(token, audit_tcl)
        for token in (
            "placement_numeric_analysis",
            "compute_pid",
            "anchors_locked':9",
            "B9_GLOBAL_ROUTE_AUTHORIZATION",
        ):
            self.assertIn(token, audit_runner)

    def test_global_route_is_single_shot_one_iteration_and_b9_only(self) -> None:
        tcl = (ROOT / "verification/groot_normalization/wbq_quad_local_b9_global_route.tcl").read_text()
        runner = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b9_global_route.sh").read_text()
        self.assertEqual(tcl.count("global_route \\"), 1)
        self.assertIn("$iterations != 1", tcl)
        self.assertIn("WBQ_B9_SINGLE_GLOBAL_ROUTE PASS", tcl)
        for token in (
            "refusing duplicate",
            'global_route_invocations": 1',
            "compute_pid",
            "wrapper_pid",
            "trap 'on_signal INT' INT",
            "trap 'on_signal TERM' TERM",
            "analyze_variant_residual_congestion.py",
            "--max-hotspots-in-output 500",
            "--max-windows-in-output 0",
            "targeted_placement_reopen_audit",
        ):
            self.assertIn(token, runner)

    def test_route_authorizer_and_strict_gate_are_fail_closed(self) -> None:
        authorizer = (ROOT / "tools/authorize_b9_global_route.py").read_text()
        gate = (ROOT / "tools/decide_b9_phase6_strict_gate.py").read_text()
        for token in (
            "SELECT_B9_SEVEN_ADDITIONAL_ANCHORS_ECO",
            'anchors_verified") == 9',
            "no_prior_route_artifact",
            "route_runner",
            "route_tcl",
            "silence_snapshot_tool",
            "silence_compare_tool",
        ):
            self.assertIn(token, authorizer)
        for token in (
            "residual_congestion_zero",
            "overflow_edges_zero",
            "input_artifact_hashes_match",
            "explicit_phase6_pass",
            "BLOCKED_RESIDUAL_CONGESTION",
            "create B10",
        ):
            self.assertIn(token, gate)


if __name__ == "__main__":
    unittest.main()
