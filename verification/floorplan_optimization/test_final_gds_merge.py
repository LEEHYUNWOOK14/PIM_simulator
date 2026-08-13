from __future__ import annotations

import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from klayout_python import kdb  # noqa: E402
from merge_final_rtl_gds import MergeError, ORIENTATIONS, apply_matrix, merge  # noqa: E402


class FinalGdsMergeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.rtl = self.directory / "rtl.gds"
        self.overlay = self.directory / "overlay.gds"
        self.manifest = self.directory / "manifest.json"
        self._write_layout(self.rtl, 0.005, rtl=True)
        self._write_layout(self.overlay, 0.002, rtl=False)
        self.manifest.write_text(json.dumps({
            "die": {"x_um": 0, "y_um": 0, "width_um": 8000, "height_um": 12000},
            "tsv_bundles": [{"bundle_id": "TSV_ANCHOR", "x_um": 1000, "y_um": 2000,
                             "rows": 1, "columns": 1, "pitch_um": 150}],
            "micro_bump_bundles": [], "blocks": [], "reserved_regions": []
        }), encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _write_layout(path: Path, dbu: float, rtl: bool) -> None:
        layout = kdb.Layout(); layout.dbu = dbu
        top = layout.create_cell("COLLIDE_TOP"); child = layout.create_cell("SHARED")
        if rtl:
            l1 = layout.layer(kdb.LayerInfo(1, 0)); l2 = layout.layer(kdb.LayerInfo(2, 0))
            child.shapes(l1).insert(kdb.Box(0, 0, round(100/dbu), round(50/dbu)))
            child.shapes(l2).insert(kdb.Box(round(10/dbu), round(10/dbu), round(20/dbu), round(20/dbu)))
        else:
            layer = layout.layer(kdb.LayerInfo(120, 0))
            child.shapes(layer).insert(kdb.Box(round(995/dbu), round(1995/dbu), round(1005/dbu), round(2005/dbu)))
        top.insert(kdb.CellInstArray(child.cell_index(), kdb.Trans()))
        layout.write(str(path))

    def recipe(self, orientation: str = "R0") -> tuple[Path, dict]:
        matrix = ORIENTATIONS[orientation][0]
        second = apply_matrix(matrix, (100.0, 0.0))
        data = {
            "schema_version": "1.0",
            "inputs": {"rtl": {"path": str(self.rtl), "top_cell": "COLLIDE_TOP"},
                       "overlay": {"path": str(self.overlay), "top_cell": "COLLIDE_TOP"},
                       "floorplan_manifest": str(self.manifest), "overlay_lyp": None},
            "output": {"gds": str(self.directory / f"merged_{orientation}.gds"),
                       "lyp": str(self.directory / f"merged_{orientation}.lyp"),
                       "report": str(self.directory / f"merged_{orientation}.json"),
                       "top_cell": "STOB_FINAL_PHYSICAL_MERGED_NOT_SIGNOFF", "dbu_um": 0.001},
            "namespaces": {"rtl_prefix": "RTL__", "overlay_prefix": "OVERLAY__"},
            "layer_mapping": {"unmapped_rtl_policy": "error", "forbid_overlay_collisions": True,
                              "rules": [{"name": "metal", "from": {"layer": 1, "datatype": 0}, "to": {"layer": 10, "datatype": 0}},
                                        {"name": "via", "from": {"layer": 2, "datatype": 0}, "to": {"layer": 11, "datatype": 0}}]},
            "placement": {"orientation": orientation, "physical_scale": 1.0, "allow_non_unit_scale": False,
                          "translation_mode": "from_anchors", "anchor_tolerance_um": 0.001,
                          "anchors": [
                              {"name": "manifest_tsv", "source_um": {"x_um": 0, "y_um": 0},
                               "target_manifest_ref": {"object_type": "tsv_bundle", "object_id": "TSV_ANCHOR", "point": "centroid"}},
                              {"name": "direction", "source_um": {"x_um": 100, "y_um": 0},
                               "target_um": {"x_um": 1000 + second[0], "y_um": 2000 + second[1]}}
                          ]},
            "verification": {"require_anchor_alignment": True, "minimum_anchor_count": 2, "require_rtl_shapes": True,
                             "require_overlay_shapes": True, "enforce_rtl_within_manifest_die": True}
        }
        path = self.directory / f"recipe_{orientation}.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path, data

    @staticmethod
    def recursive_bbox_um(gds: str, top_name: str, layer: int, datatype: int) -> list[float]:
        layout = kdb.Layout(); layout.read(gds); top = layout.cell(top_name)
        region = kdb.Region(top.begin_shapes_rec(layout.find_layer(layer, datatype)))
        box = region.bbox()
        return [box.left*layout.dbu, box.bottom*layout.dbu, box.right*layout.dbu, box.top*layout.dbu]

    def test_dbu_layer_namespace_and_manifest_anchor_merge(self) -> None:
        recipe, _ = self.recipe()
        report = merge(recipe)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["normalization"]["rtl_reference_magnification"], 1.0)
        self.assertEqual(report["normalization"]["overlay_reference_magnification"], 1.0)
        self.assertEqual(report["max_anchor_residual_um"], 0.0)
        self.assertTrue(all(name.startswith("RTL__") for name in report["cell_namespace"]["rtl"].values()))
        self.assertTrue(all(name.startswith("OVERLAY__") for name in report["cell_namespace"]["overlay"].values()))
        layout = kdb.Layout(); layout.read(report["output"]["gds"])
        self.assertAlmostEqual(layout.dbu, 0.001)
        self.assertIsNotNone(layout.cell("STOB_FINAL_PHYSICAL_MERGED_NOT_SIGNOFF"))
        self.assertIn("10/0", report["output"]["layers"])
        self.assertIn("120/0", report["output"]["layers"])
        self.assertEqual(self.recursive_bbox_um(report["output"]["gds"], "STOB_FINAL_PHYSICAL_MERGED_NOT_SIGNOFF", 10, 0), [1000.0, 2000.0, 1100.0, 2050.0])

    def test_all_eight_orientations_align_two_anchors(self) -> None:
        for orientation in ORIENTATIONS:
            with self.subTest(orientation=orientation):
                recipe, _ = self.recipe(orientation)
                report = merge(recipe)
                self.assertLessEqual(report["max_anchor_residual_um"], 0.001)
                self.assertTrue(report["geometry"]["rtl_within_manifest_die"])
                matrix = ORIENTATIONS[orientation][0]
                corners = [apply_matrix(matrix, p) for p in ((0,0),(100,0),(0,50),(100,50))]
                expected = [min(p[0] for p in corners)+1000, min(p[1] for p in corners)+2000,
                            max(p[0] for p in corners)+1000, max(p[1] for p in corners)+2000]
                self.assertEqual(self.recursive_bbox_um(report["output"]["gds"], "STOB_FINAL_PHYSICAL_MERGED_NOT_SIGNOFF", 10, 0), expected)

    def test_inconsistent_anchor_is_rejected(self) -> None:
        path, data = self.recipe()
        data["placement"]["anchors"][1]["target_um"]["x_um"] += 10
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(MergeError, "residual"):
            merge(path)

    def test_unmapped_layer_and_overlay_collision_are_rejected(self) -> None:
        path, data = self.recipe()
        data["layer_mapping"]["rules"] = data["layer_mapping"]["rules"][:1]
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(MergeError, "unmapped RTL"):
            merge(path)
        path, data = self.recipe()
        data["layer_mapping"]["rules"][0]["to"] = {"layer": 120, "datatype": 0}
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(MergeError, "collision"):
            merge(path)

    def test_non_unit_scale_and_output_overwrite_are_rejected(self) -> None:
        path, data = self.recipe()
        data["placement"]["physical_scale"] = 2.0
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(MergeError, "non-unit"):
            merge(path)
        path, _ = self.recipe()
        merge(path)
        with self.assertRaisesRegex(MergeError, "output exists"):
            merge(path)
        self.assertEqual(merge(path, force=True)["status"], "PASS")

    def test_unsafe_namespace_prefixes_are_rejected(self) -> None:
        path, data = self.recipe()
        data["namespaces"]["overlay_prefix"] = data["namespaces"]["rtl_prefix"]
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(MergeError, "prefixes must differ"):
            merge(path)


if __name__ == "__main__":
    unittest.main()
