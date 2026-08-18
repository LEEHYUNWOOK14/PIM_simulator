#!/usr/bin/env python3
"""Static fail-closed checks for the B6-to-B7 one-variable recovery."""

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


class B7RecoveryContractTest(unittest.TestCase):
    def test_selector_seals_b6_and_changes_one_variable(self) -> None:
        text = (ROOT / "tools/select_b7_phi_recovery.py").read_text()
        for token in (
            "GPL-0307",
            '"global_route_invocations": 0',
            '"single_independent_variable": "global_placement.max_phi_coef"',
            '"before": 1.05',
            '"after": 1.01',
            '"authorizes": []',
            '"next_stage": "B7_SMOKE"',
        ):
            self.assertIn(token, text)

    def test_placement_tcl_changes_only_max_phi_command_parameter(self) -> None:
        b6 = (ROOT / "verification/groot_normalization/wbq_quad_local_b6_targeted_place.tcl").read_text()
        b7 = (ROOT / "verification/groot_normalization/wbq_quad_local_b7_phi_place.tcl").read_text()
        b6_global = block(b6, "global_placement")
        b7_global = block(b7, "global_placement")
        self.assertEqual(b6_global.replace("1.05", "1.01"), b7_global)
        self.assertEqual(block(b6, "detailed_placement"), block(b7, "detailed_placement"))
        self.assertEqual(b7.count("global_placement \\"), 1)
        self.assertIn("min_phi=0.95 max_phi=1.01", b7)
        self.assertNotIn("-max_phi_coef 1.05", b7)
        self.assertNotIn("-use_diamond_legalizer", b7)

    def test_smoke_reopens_input_writes_and_reopens_checkpoint(self) -> None:
        smoke = (ROOT / "verification/groot_normalization/run_wbq_b7_phi_smoke.sh").read_text()
        for token in (
            "WBQ_B7_SMOKE_STATIC_POLICY",
            "WBQ_B7_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS",
            "WBQ_B7_SMOKE_INDEPENDENT_REOPEN PASS anchors=2",
            "compute_pid",
            "audit_compute_pid",
            "trap 'on_signal TERM' TERM",
            "existing B7 smoke artifact prevents duplicate",
            "B7_PHYSICAL_AUTHORIZATION",
        ):
            self.assertIn(token, smoke)

    def test_authorizer_pins_smoke_sources_and_silence_tools(self) -> None:
        text = (ROOT / "tools/authorize_b7_physical_run.py").read_text()
        for token in (
            "fresh_smoke_inputs_match",
            "fresh_smoke_outputs_match",
            "only_global_placement_phi_changed",
            "detailed_placement_command_unchanged",
            "anchor_specs_unchanged",
            "silence_snapshot_tool",
            "silence_compare_tool",
            "no_prior_b7_placement_attempt",
            '["B7_PLACEMENT"]',
        ):
            self.assertIn(token, text)

    def test_placement_runner_is_one_shot_pid_exact_and_fail_closed(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b7_placement.sh").read_text()
        for token in (
            "B7 placement has already been attempted",
            '"${WBQ_RUNNER_SERVICE:-direct-cli}"',
            "launcher_pid",
            "compute_pid",
            "audit_compute_pid",
            "trap 'on_signal INT' INT",
            "trap 'on_signal TERM' TERM",
            "trap write_unexpected_fail EXIT",
            "WBQ_B7_PLACE_MAX_PHI_COEF=1.01",
            "GPL-0307",
            "protected_artifacts_preserved",
            "B7_TARGETED_PLACEMENT_REOPEN_AUDIT",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
