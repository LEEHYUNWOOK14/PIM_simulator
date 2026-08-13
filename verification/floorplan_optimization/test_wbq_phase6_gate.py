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
from verify_wbq_phase6_gate import verify  # noqa: E402


class WbqPhase6GateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.route_artifacts = {}
        for name in {"route_log", "route_guide", "congestion_report", "routed_odb", "routed_sdc"}:
            path = self.directory / name
            path.write_text(name, encoding="utf-8")
            self.route_artifacts[name] = self.item(path)
        self.route = {
            "schema_version": 1,
            "top": "logic_die_normalization_hbm_top",
            "variant": "wbq_v4_control",
            "verdict": "PASS_PF4",
            "same_metric_definition": True,
            "placement_gate_pass": True,
            "placement_input_hashes_match": True,
            "clean_completion": True,
            "current_wbq": {
                "residual_congestion": 0,
                "overflow_edges": 0,
                "all_skipped_nets_allowlisted": True,
            },
            "artifacts": self.route_artifacts,
        }
        self.route_path = self.directory / "route.json"
        self.write(self.route_path, self.route)
        self.decision = {
            "schema_version": 1,
            "source_manifest": str(self.route_path),
            "source_manifest_sha256": self.digest(self.route_path),
            "verdict": "PASS_PF4",
            "evidence_valid": True,
            "decision": "PHASE6_CLOCK_AND_DETAILED_ROUTE",
        }
        self.decision_path = self.directory / "decision.json"
        self.write(self.decision_path, self.decision)
        odb = self.directory / "3_place.odb"
        sdc = self.directory / "3_place.sdc"
        odb.write_text("odb", encoding="utf-8")
        sdc.write_text("sdc", encoding="utf-8")
        self.placement = {
            "schema_version": 1,
            "top": "logic_die_normalization_hbm_top",
            "variant": "wbq",
            "gate_pass": True,
            "artifacts": {"placed_odb": self.item(odb), "placed_sdc": self.item(sdc)},
        }
        self.placement_path = self.directory / "placement.json"
        self.write(self.placement_path, self.placement)

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def digest(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def item(self, path: Path) -> dict[str, object]:
        return {"path": str(path), "bytes": path.stat().st_size, "sha256": self.digest(path)}

    @staticmethod
    def write(path: Path, value: dict) -> None:
        path.write_text(json.dumps(value), encoding="utf-8")

    def test_exact_pass_evidence_authorizes_phase6(self) -> None:
        result = verify(self.decision_path, self.placement_path)
        self.assertTrue(result["gate_pass"])
        self.assertTrue(all(result["checks"].values()))

    def test_tampered_placement_bytes_fail_closed(self) -> None:
        Path(self.placement["artifacts"]["placed_odb"]["path"]).write_text("changed", encoding="utf-8")
        result = verify(self.decision_path, self.placement_path)
        self.assertFalse(result["gate_pass"])
        self.assertFalse(result["checks"]["placement_placed_odb_match"])

    def test_stale_decision_source_hash_fails_closed(self) -> None:
        changed = copy.deepcopy(self.route)
        changed["current_wbq"]["residual_congestion"] = 1
        self.write(self.route_path, changed)
        result = verify(self.decision_path, self.placement_path)
        self.assertFalse(result["gate_pass"])
        self.assertFalse(result["checks"]["source_manifest_hash_match"])
        self.assertFalse(result["checks"]["source_recomputes_phase6"])

    def test_phase5_decision_fails_closed(self) -> None:
        self.decision["decision"] = "PHASE5_HIERARCHICAL_ARCHITECTURE"
        self.write(self.decision_path, self.decision)
        result = verify(self.decision_path, self.placement_path)
        self.assertFalse(result["gate_pass"])
        self.assertFalse(result["checks"]["decision_exact_phase6"])


if __name__ == "__main__":
    unittest.main()
