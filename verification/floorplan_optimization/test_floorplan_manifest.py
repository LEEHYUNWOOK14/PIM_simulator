from __future__ import annotations

import copy
import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import generate_logic_die_floorplan_manifest as generator
import validate_logic_die_floorplan as validator

MANIFEST = ROOT / "design/floorplan/logic_die_floorplan.json"
SCHEMA = ROOT / "design/floorplan/logic_die_floorplan.schema.json"
TSV = ROOT / "design/floorplan/tsv_connectivity.csv"


class FloorplanManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = json.loads(MANIFEST.read_text(encoding="utf-8"))

    def write_manifest(self, directory: Path, document: dict) -> Path:
        path = directory / "manifest.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def assert_rejected(self, mutate, message: str) -> None:
        with tempfile.TemporaryDirectory() as temp:
            document = copy.deepcopy(self.document)
            mutate(document)
            path = self.write_manifest(Path(temp), document)
            with self.assertRaisesRegex(validator.FloorplanValidationError, message):
                validator.validate(str(path), str(SCHEMA), None)

    def test_valid_manifest_and_csv_roundtrip(self) -> None:
        report = validator.validate(str(MANIFEST), str(SCHEMA), str(TSV))
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["counts"]["tsv_bundles"], 48)
        self.assertEqual(report["counts"]["tsv_shapes"], 320)

    def test_wrong_coordinate_unit_is_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["coordinate_system"].update(length_unit="mm"), "schema")

    def test_block_overlap_is_rejected(self) -> None:
        def mutate(doc):
            doc["blocks"][1]["x_um"] = doc["blocks"][0]["x_um"]
            doc["blocks"][1]["y_um"] = doc["blocks"][0]["y_um"]
        self.assert_rejected(mutate, "block overlap")

    def test_block_outside_die_is_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["blocks"][0].update(x_um=7900), "outside die")

    def test_tsv_keepout_is_rejected(self) -> None:
        def mutate(doc):
            block = doc["blocks"][0]
            block.update(x_um=450, y_um=1750, width_um=100, height_um=100)
        self.assert_rejected(mutate, "TSV keep-out")

    def test_duplicate_bundle_is_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["tsv_bundles"].append(copy.deepcopy(doc["tsv_bundles"][0])), "duplicate vertical bundle")

    def test_dangling_endpoint_is_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["tsv_bundles"][0].update(source="missing.endpoint"), "dangling source")

    def test_reserved_region_collision_is_rejected(self) -> None:
        def mutate(doc):
            doc["reserved_regions"][0].update(x_um=600, y_um=1000, width_um=800, height_um=4200)
        self.assert_rejected(mutate, "prohibited region")

    def test_csv_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "tsv.csv"
            with TSV.open(newline="", encoding="utf-8") as source:
                rows = list(csv.DictReader(source))
            rows[0]["x_um"] = "999"
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaisesRegex(validator.FloorplanValidationError, "CSV mismatch"):
                validator.validate(str(MANIFEST), str(SCHEMA), str(path))

    def test_legacy_and_physical_report_adapter(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            placement = directory / "placement.csv"
            placement.write_text(
                "instance,x_um,y_um,width_um,height_um\n"
                "top.logic_die_64ch_reduction_top,675,1100,650,4000\n",
                encoding="utf-8",
            )
            normalized = directory / "normalized.json"
            normalized.write_text(json.dumps({"blocks": [{
                "instance": "top.logic_die_64ch_reduction_top",
                "module": "logic_die_64ch_reduction_top",
                "area_um2": 2800000,
                "dynamic_power_W": 0.45,
                "leakage_power_W": 0.05,
            }]}), encoding="utf-8")
            output, csv_output = directory / "out.json", directory / "out.csv"
            result = generator.generate(
                "design/hbm2_architecture.json", "design/hbm2_package.json",
                str(output), str(csv_output), str(placement), str(normalized),
            )
            report = validator.validate(str(output), str(SCHEMA), str(csv_output))
            block = result["blocks"][0]
            self.assertEqual(report["status"], "PASS")
            self.assertEqual(block["classification"], "placed")
            self.assertEqual(block["dynamic_W"] + block["leakage_W"], 0.5)
            self.assertEqual(result["legacy_compatibility"]["logic_block_x_um"], 0.0)


if __name__ == "__main__":
    unittest.main()
