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


if __name__ == "__main__":
    unittest.main()
