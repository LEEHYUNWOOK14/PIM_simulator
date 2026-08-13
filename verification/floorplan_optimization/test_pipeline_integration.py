from __future__ import annotations

import csv
import json
import unittest
from pathlib import Path

import gdstk

ROOT = Path(__file__).resolve().parents[2]
STRATEGIES = {"manual_baseline", "wirelength_first", "thermal_first", "balanced", "cost_first"}


def rows(path: str) -> list[dict]:
    with (ROOT / path).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


class FloorplanPipelineIntegrationTests(unittest.TestCase):
    def test_candidate_sets_and_evidence_are_aligned(self) -> None:
        paths = [
            "output/floorplan_optimization/exploration/selected_candidates.csv",
            "output/floorplan_optimization/openroad_proxy/openroad_proxy_metrics.csv",
            "output/floorplan_optimization/thermal_results.csv",
            "output/floorplan_optimization/hotspot_results.csv",
            "output/floorplan_optimization/3dice_results.csv",
            "output/floorplan_optimization/candidate_comparison.csv",
        ]
        for path in paths:
            self.assertEqual({row["strategy"] for row in rows(path)}, STRATEGIES, path)
        for row in rows(paths[-1]):
            self.assertEqual(row["signoff"], "NO")
            self.assertIn("proxy", row["physical_evidence"])
            self.assertIn("modeled", row["thermal_evidence"])

    def test_all_candidate_solvers_conserve_the_same_estimated_power(self) -> None:
        for path in ("output/floorplan_optimization/thermal_results.csv", "output/floorplan_optimization/hotspot_results.csv", "output/floorplan_optimization/3dice_results.csv"):
            for row in rows(path):
                self.assertEqual(row["status"], "PASS")
                self.assertAlmostEqual(float(row["input_power_W"]), 4.0, places=12)
        for row in rows("output/floorplan_optimization/thermal_results.csv"):
            self.assertLessEqual(float(row["power_conservation_error_W"]), 1e-12)
            self.assertEqual(row["solver_validation"], "PASS")

    def test_candidate_gds_hierarchy_and_thermal_overlay(self) -> None:
        for strategy in STRATEGIES:
            directory = ROOT / f"output/floorplan_optimization/visualization/{strategy}"
            metadata = json.loads((directory / "visualization_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["counts"]["tsv_shapes"], 320)
            self.assertEqual(metadata["counts"]["micro_bump_shapes"], 320)
            self.assertEqual(metadata["counts"]["thermal_bins"], 512)
            self.assertFalse(metadata["thermal_overlay"]["signoff"])
            library = gdstk.read_gds(directory / "logic_die_floorplan.gds")
            names = {cell.name for cell in library.cells}
            self.assertEqual(sum(name.startswith("TSV_") for name in names), 48)
            self.assertEqual(sum(name.startswith("BUMP_") for name in names), 48)
            self.assertEqual(sum(name.startswith("BLOCK_") for name in names), 8)

    def test_visualization_deliverables_are_nonempty(self) -> None:
        figure_dir = ROOT / "output/floorplan_optimization/visualization/paper_figures"
        manifest = json.loads((figure_dir / "figure_manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["status"], "PASS")
        self.assertEqual(len(manifest["figures"]), 6)
        for filename in manifest["figures"]:
            self.assertGreater((figure_dir / filename).stat().st_size, 50_000)
        for strategy in STRATEGIES:
            directory = ROOT / f"output/floorplan_optimization/visualization/{strategy}"
            self.assertGreater((directory / "klayout_fixed_camera.png").stat().st_size, 100_000)
            paraview = json.loads((directory / "paraview/paraview_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(paraview["status"], "PASS")
            self.assertEqual(paraview["files"][0]["cells"], 11080)

    def test_current_rtl_physical_scope_is_not_overclaimed(self) -> None:
        snapshot = json.loads((ROOT / "reports/floorplan_optimization/results/current_rtl_openroad_snapshot.json").read_text(encoding="utf-8"))
        self.assertEqual(snapshot["global_route"]["total_congestion"], 0)
        self.assertEqual(snapshot["detailed_route"]["status"], "FAIL_RESOURCE_INTERRUPTED")
        self.assertFalse(snapshot["detailed_route"]["output_odb_created"])
        self.assertFalse(snapshot["constraint_limitations"]["timing_signoff"])

    def test_phase8_evidence_package_is_complete(self) -> None:
        matrix = rows("reports/floorplan_optimization/requirement_to_evidence.csv")
        self.assertEqual({row["requirement_id"] for row in matrix}, {f"R{i:02d}" for i in range(1, 17)})
        self.assertTrue(all(row["status"] in {"PASS", "PASS_WITH_LIMITATIONS"} for row in matrix))
        for row in matrix:
            self.assertTrue((ROOT / row["primary_artifact"].strip()).exists(), row["requirement_id"])
        for path in (
            "reports/floorplan_optimization/08_final_audit.md",
            "reports/floorplan_optimization/paper_figure_index.md",
            "reports/floorplan_optimization/rtl_refresh_handoff.md",
            "tools/run_logic_die_floorplan_analysis.ps1",
        ):
            self.assertGreater((ROOT / path).stat().st_size, 500)


if __name__ == "__main__": unittest.main()
