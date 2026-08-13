import copy
import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import compare_hardware_cost_revisions as compare
import generate_synthetic_hardware_cost_adapters as generator
import hardware_cost_adapter_contract as contract


class HardwareCostAdapterV2Tests(unittest.TestCase):
    def generate(self, root):
        adapter_dir = Path(root) / "adapters"
        paths = generator.generate(output_path=str(adapter_dir))
        return adapter_dir, paths

    def snapshots(self, root):
        adapter_dir, _ = self.generate(root)
        revisions = Path(root) / "revisions"
        definitions = json.loads((ROOT / "hardware_cost/regression/synthetic_candidate_definitions.json").read_text(encoding="utf-8"))
        result = {}
        for candidate in definitions["candidates"]:
            paths = [adapter_dir / candidate["id"] / f"{axis}.json" for axis in contract.AXES]
            result[candidate["id"]] = contract.build_snapshot(paths, candidate["captured_at"], revisions / f"{candidate['id']}.json")
        return revisions, result

    def test_all_five_adapters_for_three_candidates_validate(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, paths = self.generate(temporary)
            self.assertEqual(len(paths), 15)
            axes = []
            for path in paths:
                document = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(contract.validate_adapter(document), [])
                axes.append(document["axis"])
            self.assertEqual({axis: axes.count(axis) for axis in contract.AXES}, {axis: 3 for axis in contract.AXES})

    def test_power_conservation_violation_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            adapter_dir, _ = self.generate(temporary)
            document = json.loads((adapter_dir / "synthetic_balanced/power.json").read_text(encoding="utf-8"))
            document["metrics"]["categories"]["bf16_fp16"]["total_power_W"] += 0.1
            self.assertTrue(any("category sum" in error or "dynamic plus leakage" in error for error in contract.validate_adapter(document)))

    def test_source_hash_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            adapter_dir, _ = self.generate(temporary)
            document = json.loads((adapter_dir / "synthetic_low_area/area.json").read_text(encoding="utf-8"))
            document["source_evidence"][0]["sha256"] = "0" * 64
            self.assertTrue(any("hash/size mismatch" in error for error in contract.validate_adapter(document)))

    def test_candidate_identity_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            adapter_dir, _ = self.generate(temporary)
            paths = [adapter_dir / "synthetic_low_area" / f"{axis}.json" for axis in contract.AXES]
            timing = json.loads(paths[1].read_text(encoding="utf-8")); timing["candidate"]["id"] = "different"
            paths[1].write_text(json.dumps(timing), encoding="utf-8")
            with self.assertRaisesRegex(contract.AdapterContractError, "candidate identity"):
                contract.build_snapshot(paths, "2026-08-12T12:00:00+09:00")

    def test_bundle_preserves_all_five_axes_and_energy_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, snapshots = self.snapshots(temporary)
        balanced = snapshots["synthetic_balanced"]
        self.assertEqual(balanced["physical_totals"]["mapped_floorplan_area_um2"], 10_000_000.0)
        self.assertEqual(balanced["physical_totals"]["critical_path_ns"], 9.0)
        self.assertEqual(balanced["physical_totals"]["total_power_W"], 3.8)
        self.assertEqual(balanced["workload"]["throughput_ops_s"], 1.8e9)
        self.assertEqual(balanced["thermal"]["peak_temperature_K"], 322.0)
        self.assertIsNone(balanced["workload"]["energy_per_op_J"])
        self.assertFalse(balanced["parameter_status"]["final_architecture_parameters_selected"])

    def test_three_candidate_end_to_end_comparison(self):
        with tempfile.TemporaryDirectory() as temporary:
            revisions, _ = self.snapshots(temporary)
            output = Path(temporary) / "report"
            summary = compare.compare(str(revisions), "synthetic_low_area", str(output))
            with (output / "paper_delta_table.csv").open(newline="", encoding="utf-8") as stream:
                rows = {row["revision"]: row for row in csv.DictReader(stream)}
            balanced = rows["synthetic_balanced"]
            self.assertAlmostEqual(float(balanced["area_vs_baseline_pct"]), 25.0)
            self.assertAlmostEqual(float(balanced["critical_path_vs_baseline_pct"]), -25.0)
            self.assertAlmostEqual(float(balanced["throughput_vs_baseline_pct"]), 80.0)
            self.assertEqual(balanced["energy_vs_baseline_policy"], "unavailable")
            self.assertEqual(summary["revision_count"], 3)
            for name in summary["outputs"]:
                self.assertTrue((output / name).is_file() and (output / name).stat().st_size > 0)


if __name__ == "__main__":
    unittest.main()
