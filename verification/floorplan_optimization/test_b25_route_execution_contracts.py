#!/usr/bin/env python3
from __future__ import annotations

import ast
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class B25RouteExecutionContracts(unittest.TestCase):
    def test_route_policy_is_b21_comparable_and_single_shot(self) -> None:
        text = (ROOT / "verification/groot_normalization/wbq_quad_local_b25_global_route.tcl").read_text()
        self.assertIn("set columns 25", text)
        self.assertIn("set pitch 300.0", text)
        self.assertIn("set x0 1500.0", text)
        self.assertIn("set y0 1000.0", text)
        self.assertIn("$iterations != 1", text)
        self.assertEqual(text.count("global_route \\\n"), 1)
        self.assertNotIn("B24", text)

    def test_route_runner_is_fail_closed(self) -> None:
        text = (ROOT / "verification/groot_normalization/run_wbq_quad_local_b25_global_route.sh").read_text()
        for marker in (
            "refusing duplicate",
            "global_route_invocations':1",
            "cugr_congestion_iterations':1",
            "trap 'on_signal INT' INT",
            "trap 'on_signal TERM' TERM",
            "write_fail_closed_manifest",
            "analyze_variant_residual_congestion.py",
            "--max-windows-in-output 0",
            "B25_STRICT_PHASE6_EVALUATION",
        ):
            self.assertIn(marker, text)
        self.assertNotIn("B24", text)

    def test_smoke_reopens_and_writes_checkpoint(self) -> None:
        runner = (ROOT / "verification/groot_normalization/run_wbq_b25_route_pin_smoke.sh").read_text()
        smoke = (ROOT / "verification/groot_normalization/wbq_b25_route_pin_smoke.tcl").read_text()
        audit = (ROOT / "verification/groot_normalization/audit_wbq_b25_route_pin_smoke.tcl").read_text()
        self.assertIn("write_db $::env(WBQ_B25_SMOKE_OUTPUT_ODB)", smoke)
        self.assertIn("WBQ_B25_SMOKE_INDEPENDENT_REOPEN PASS", audit)
        self.assertIn("audit_compute_pid", runner)
        self.assertIn("B25_GLOBAL_ROUTE_AUTHORIZATION", runner)

    def test_authorizer_and_strict_gate_are_parseable_and_pinned(self) -> None:
        authorizer = (ROOT / "tools/authorize_b25_global_route.py").read_text()
        strict = (ROOT / "tools/decide_b25_phase6_strict_gate.py").read_text()
        ast.parse(authorizer)
        ast.parse(strict)
        for marker in (
            "placement_outputs_match",
            "route_pin_smoke_output_matches",
            "one_cugr_iteration",
            "no_prior_route_artifact",
            "B25_SINGLE_GLOBAL_ROUTE",
        ):
            self.assertIn(marker, authorizer)
        for marker in (
            "residual_congestion_zero",
            "overflow_edges_zero",
            "input_artifact_hashes_match",
            "explicit_phase6_pass",
            "BLOCKED_RESIDUAL_CONGESTION",
        ):
            self.assertIn(marker, strict)


if __name__ == "__main__":
    unittest.main()
