#!/usr/bin/env python3
"""Static fail-closed checks for the B7-to-B8 one-variable recovery."""

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


class B8RecoveryContractTest(unittest.TestCase):
    def test_selector_seals_b7_and_changes_one_variable(self) -> None:
        text = (ROOT / "tools/select_b8_drc_penalty_recovery.py").read_text()
        for token in (
            "design_legality_failure",
            '"global_route_invocations": 0',
            '"single_independent_variable": "detailed_placement.drc_penalty"',
            '"before": 20',
            '"after": 100',
            '"authorizes": []',
            '"next_stage": "B8_SMOKE"',
        ):
            self.assertIn(token, text)

    def test_placement_tcl_changes_only_drc_penalty(self) -> None:
        b7 = (ROOT / "verification/groot_normalization/wbq_quad_local_b7_phi_place.tcl").read_text()
        b8 = (ROOT / "verification/groot_normalization/wbq_quad_local_b8_drc_place.tcl").read_text()
        self.assertEqual(block(b7, "detailed_placement").replace("-drc_penalty 20", "-drc_penalty 100"), block(b8, "detailed_placement"))
        self.assertEqual(b8.count("detailed_placement \\"), 1)
        self.assertIn("drc_penalty=100", b8)
        self.assertNotIn("-drc_penalty 20", b8)
        self.assertNotIn("global_placement", b8)
        self.assertNotIn("-use_diamond_legalizer", b8)

    def test_smoke_reopens_b7_rudy_and_independently_reopens_checkpoint(self) -> None:
        runner = (ROOT / "verification/groot_normalization/run_wbq_b8_drc_smoke.sh").read_text()
        for token in (
            "WBQ_B7_RUDY_ODB",
            "WBQ_B8_SMOKE_STATIC_POLICY",
            "WBQ_B8_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS",
            "WBQ_B8_SMOKE_INDEPENDENT_REOPEN PASS",
            "compute_pid",
            "audit_compute_pid",
            "trap 'on_signal TERM' TERM",
            "existing B8 smoke artifact prevents duplicate",
            "B8_PHYSICAL_AUTHORIZATION",
        ):
            self.assertIn(token, runner)

    def test_authorizer_pins_checkpoint_sources_and_silence_tools(self) -> None:
        text = (ROOT / "tools/authorize_b8_physical_run.py").read_text()
        for token in (
            "fresh_smoke_inputs_match",
            "fresh_smoke_outputs_match",
            "only_detailed_placement_drc_penalty_changed",
            "sealed_b7_rudy_checkpoint_matches",
            "silence_snapshot_tool",
            "silence_compare_tool",
            "no_prior_b8_placement_attempt",
            '["B8_PLACEMENT"]',
        ):
            self.assertIn(token, text)

    def test_placement_runner_is_one_shot_pid_exact_and_fail_closed(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b8_placement.sh").read_text()
        for token in (
            "B8 placement has already been attempted",
            '"${WBQ_RUNNER_SERVICE:-direct-cli}"',
            "launcher_pid",
            "compute_pid",
            "audit_compute_pid",
            "trap 'on_signal INT' INT",
            "trap 'on_signal TERM' TERM",
            "trap write_unexpected_fail EXIT",
            "WBQ_B8_PLACE_DRC_PENALTY=100",
            "design_legality_failure",
            "protected_artifacts_preserved",
            "B8_TARGETED_PLACEMENT_REOPEN_AUDIT",
        ):
            self.assertIn(token, text)

    def test_frozen_hashes_remain_exact(self) -> None:
        combined = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b8_placement.sh").read_text()
        for digest in (
            "964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad",
            "ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235",
            "2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d",
        ):
            self.assertIn(digest, combined)


if __name__ == "__main__":
    unittest.main()
