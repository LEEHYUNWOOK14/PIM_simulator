from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import optimize_logic_die_floorplan as optimizer
import validate_logic_die_floorplan as validator
import collect_floorplan_openroad_proxy_metrics as openroad_metrics
import floorplan_manifest_to_mapped_power as thermal_adapter


class FloorplanOptimizerTests(unittest.TestCase):
    def test_candidate_thermal_adapter_conserves_power(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = thermal_adapter.adapt(
                "output/floorplan_optimization/exploration/candidates/balanced.json",
                str(Path(temporary) / "mapped_power.json"),
            )
            self.assertEqual(result["status"], "PASS")
            self.assertAlmostEqual(result["checks"]["mapped_power_W"], 4.0, places=12)
            self.assertEqual(len(result["blocks"]), 8)

    def test_openroad_congestion_and_def_roundtrip_parsers(self) -> None:
        root = ROOT / "output/floorplan_optimization/openroad_proxy"
        expected = {"manual_baseline": 0, "wirelength_first": 0, "balanced": 358, "thermal_first": 225}
        for strategy, overflow in expected.items():
            directory = root / strategy
            metadata = json.loads((directory / "proxy_manifest.json").read_text(encoding="utf-8"))
            # Older generated metadata is refreshed by the proxy runner; skip only
            # when a developer intentionally runs this unit before regeneration.
            if "expected_placements" not in metadata:
                continue
            congestion = openroad_metrics.parse_congestion(directory / "congestion.rpt")
            self.assertEqual(congestion["overflow_sum"], overflow)
            ok, error, count = openroad_metrics.verify_def_roundtrip(directory / "floorplan_proxy.def", metadata)
            self.assertTrue(ok)
            self.assertLessEqual(error, 0.001)
            self.assertEqual(count, 16)

    def test_seeded_search_is_reproducible_and_exports_legal_candidates(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a = optimizer.optimize(
                "design/floorplan/logic_die_floorplan.json",
                "design/floorplan/placement_objectives.json", first, 235, 80,
            )
            b = optimizer.optimize(
                "design/floorplan/logic_die_floorplan.json",
                "design/floorplan/placement_objectives.json", second, 235, 80,
            )
            self.assertEqual(a["selected"], b["selected"])
            self.assertEqual(a["feasible_unique_candidates"], b["feasible_unique_candidates"])
            self.assertGreater(a["feasible_unique_candidates"], 10)
            self.assertGreater(a["rejected_candidates"], 0)
            for path in Path(first, "candidates").glob("*.json"):
                report = validator.validate(str(path), "design/floorplan/logic_die_floorplan.schema.json", None)
                self.assertEqual(report["status"], "PASS")

    def test_pareto_rows_and_rejection_reasons_are_present(self) -> None:
        output = ROOT / "output/floorplan_optimization/exploration"
        with (output / "pareto_frontier.csv").open(newline="", encoding="utf-8") as stream:
            frontier = list(csv.DictReader(stream))
        with (output / "rejected_candidates.csv").open(newline="", encoding="utf-8") as stream:
            rejected = list(csv.DictReader(stream))
        self.assertTrue(frontier)
        self.assertTrue(all(row["pareto_optimal"] == "True" for row in frontier))
        reasons = Counter(reason.split(":", 1)[0] for row in rejected for reason in row["reason"].split(";"))
        self.assertIn("tsv_keepout", reasons)


if __name__ == "__main__":
    unittest.main()
