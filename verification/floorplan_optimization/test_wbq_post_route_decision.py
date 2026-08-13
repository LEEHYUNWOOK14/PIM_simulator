from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from decide_wbq_post_route import ARTIFACT_KEYS, decide  # noqa: E402


class WbqPostRouteDecisionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        artifacts = {}
        for name in ARTIFACT_KEYS:
            path = self.directory / name
            path.write_text(name, encoding="utf-8")
            artifacts[name] = {
                "path": str(path), "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        self.manifest = {
            "schema_version": 1, "top": "logic_die_normalization_hbm_top",
            "variant": "wbq_v4_control", "verdict": "PASS_PF4",
            "same_metric_definition": True, "placement_gate_pass": True,
            "placement_input_hashes_match": True, "clean_completion": True,
            "current_wbq": {"residual_congestion": 0, "overflow_edges": 0,
                            "all_skipped_nets_allowlisted": True},
            "artifacts": artifacts,
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_case(self, document: dict) -> dict:
        path = self.directory / "manifest.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return decide(path)

    def test_pass_pf4_selects_phase6(self) -> None:
        result = self.run_case(self.manifest)
        self.assertTrue(result["evidence_valid"])
        self.assertEqual(result["decision"], "PHASE6_CLOCK_AND_DETAILED_ROUTE")

    def test_nonzero_valid_route_selects_phase5(self) -> None:
        document = copy.deepcopy(self.manifest)
        document["verdict"] = "IMPROVED_NOT_CLOSED"
        document["current_wbq"]["residual_congestion"] = 1
        document["current_wbq"]["overflow_edges"] = 1
        self.assertEqual(self.run_case(document)["decision"], "PHASE5_HIERARCHICAL_ARCHITECTURE")

    def test_tampered_artifact_stops(self) -> None:
        artifact = Path(self.manifest["artifacts"]["routed_odb"]["path"])
        artifact.write_text("tampered", encoding="utf-8")
        result = self.run_case(self.manifest)
        self.assertFalse(result["evidence_valid"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")

    def test_false_pass_metrics_stop(self) -> None:
        document = copy.deepcopy(self.manifest)
        document["current_wbq"]["overflow_edges"] = 1
        self.assertEqual(self.run_case(document)["decision"], "STOP_INVALID_RUN")


if __name__ == "__main__":
    unittest.main()
