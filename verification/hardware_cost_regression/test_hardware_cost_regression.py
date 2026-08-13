import copy,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
import capture_hardware_cost_revision as capture
import compare_hardware_cost_revisions as compare
import hardware_cost_evidence_contract as contract

MANIFEST="hardware_cost/regression/baseline_manifest.json"

class HardwareCostRegressionTests(unittest.TestCase):
    def capture(self):
        td=tempfile.TemporaryDirectory(); self.addCleanup(td.cleanup); out=Path(td.name)/"baseline.json"
        return capture.capture(MANIFEST,str(out))

    def test_baseline_freezes_required_metrics_without_false_timing(self):
        s=self.capture(); self.assertEqual(s["revision"]["id"],"provisional_baseline_2026_08_11")
        self.assertEqual(s["schema_version"],2); self.assertEqual(s["evidence_contract"]["contract_version"],2)
        self.assertEqual(contract.validate_snapshot(s),[])
        self.assertEqual({x["precision"] for x in s["observations"]},{"FP16","BF16"})
        self.assertTrue(all(x["critical_path_ns"] is None and x["slack_ns"] is None for x in s["observations"]))
        self.assertIsNone(s["workload"]["energy_per_op_J"]); self.assertEqual(s["workload"]["status"],"pending")

    def test_categories_are_exclusive_and_conserve_power(self):
        s=self.capture(); blocks=[b for c in s["categories"].values() for b in c["blocks"]]
        self.assertEqual(len(blocks),len(set(blocks))); self.assertEqual(len(blocks),5)
        self.assertEqual(len(s["block_metrics"]),5)
        self.assertAlmostEqual(sum(c["total_power_W"] for c in s["categories"].values()),4.0,places=12)
        self.assertAlmostEqual(sum(b["total_power_W"] for b in s["block_metrics"]),4.0,places=12)

    def test_source_files_are_hashed(self):
        s=self.capture(); self.assertGreaterEqual(len(s["source_files"]),6)
        self.assertTrue(all(len(x["sha256"])==64 and x["bytes"]>0 and x["claim_class"] in {"measured","derived","modeled","assumed"} for x in s["source_files"]))

    def test_final_architecture_selection_is_rejected(self):
        manifest=json.loads((ROOT/MANIFEST).read_text(encoding="utf-8")); manifest["parameter_status"]["final_architecture_parameters_selected"]=True
        with tempfile.TemporaryDirectory() as td:
            mp=Path(td)/"manifest.json"; mp.write_text(json.dumps(manifest),encoding="utf-8")
            with self.assertRaisesRegex(capture.CaptureError,"must remain false"): capture.capture(str(mp),str(Path(td)/"x.json"))

    def test_real_metric_slots_and_energy_per_op_are_collected(self):
        manifest=json.loads((ROOT/MANIFEST).read_text(encoding="utf-8")); first=manifest["synthesis_observations"][0]
        first.update({"technology_mapped_area_um2":12345.0,"critical_path_ns":4.0,"slack_ns":1.0,"calibration":"technology_mapped"})
        manifest["primary_observation"]=first["name"]
        manifest["calibration"].update({"synthesis":"technology_mapped","timing":"technology_mapped","power":"activity_based","workload":"workload_model"})
        manifest["evidence_contract"]["toolchain"].update({"synthesis_tool_version":"0.40","power_tool":"OpenSTA power fixture","power_tool_version":"1"})
        manifest["evidence_contract"]["operating_point"].update({"pdk":"sky130","library":"sky130_fd_sc_hd","process_corner":"tt","voltage_V":1.8,"temperature_C":25.0,"clock_constraint_ns":10.0,"workload_trace_id":"fixture"})
        workload=json.loads((ROOT/"hardware_cost/regression/gr00t_pending.json").read_text(encoding="utf-8")); workload["status"]="available"; workload["workload"].update({"name":"fixture","precision":"FP16"}); workload["metrics"]["throughput_ops_s"]=2e9
        with tempfile.TemporaryDirectory() as td:
            wp=Path(td)/"workload.json"; wp.write_text(json.dumps(workload),encoding="utf-8"); manifest["gr00t_workload_json"]=str(wp)
            mp=Path(td)/"manifest.json"; mp.write_text(json.dumps(manifest),encoding="utf-8"); s=capture.capture(str(mp),str(Path(td)/"snapshot.json"))
        self.assertEqual(s["physical_totals"]["technology_mapped_area_um2"],12345.0); self.assertEqual(s["physical_totals"]["critical_path_ns"],4.0); self.assertEqual(s["physical_totals"]["slack_ns"],1.0)
        self.assertAlmostEqual(s["workload"]["energy_per_op_J"],2e-9)

    def test_axis_invalid_calibration_is_rejected(self):
        manifest=json.loads((ROOT/MANIFEST).read_text(encoding="utf-8")); manifest["calibration"]["power"]="placed"
        with tempfile.TemporaryDirectory() as td:
            mp=Path(td)/"manifest.json"; mp.write_text(json.dumps(manifest),encoding="utf-8")
            with self.assertRaisesRegex(capture.CaptureError,"calibration.power"):
                capture.capture(str(mp),str(Path(td)/"snapshot.json"))

    def test_technology_calibration_requires_operating_point_and_tool_version(self):
        manifest=json.loads((ROOT/MANIFEST).read_text(encoding="utf-8")); first=manifest["synthesis_observations"][0]
        first.update({"technology_mapped_area_um2":12345.0,"calibration":"technology_mapped"}); manifest["primary_observation"]=first["name"]
        manifest["calibration"]["synthesis"]="technology_mapped"
        with tempfile.TemporaryDirectory() as td:
            mp=Path(td)/"manifest.json"; mp.write_text(json.dumps(manifest),encoding="utf-8")
            with self.assertRaisesRegex(capture.CaptureError,"operating_point.pdk"):
                capture.capture(str(mp),str(Path(td)/"snapshot.json"))

    def test_synthetic_power_keeps_energy_unavailable(self):
        manifest=json.loads((ROOT/MANIFEST).read_text(encoding="utf-8")); manifest["calibration"]["workload"]="workload_model"
        manifest["evidence_contract"]["operating_point"]["workload_trace_id"]="fixture"
        workload=json.loads((ROOT/"hardware_cost/regression/gr00t_pending.json").read_text(encoding="utf-8")); workload["status"]="available"; workload["metrics"]["throughput_ops_s"]=2e9
        with tempfile.TemporaryDirectory() as td:
            wp=Path(td)/"workload.json"; wp.write_text(json.dumps(workload),encoding="utf-8"); manifest["gr00t_workload_json"]=str(wp)
            mp=Path(td)/"manifest.json"; mp.write_text(json.dumps(manifest),encoding="utf-8")
            snapshot=capture.capture(str(mp),str(Path(td)/"snapshot.json"))
        self.assertEqual(snapshot["workload"]["throughput_ops_s"],2e9)
        self.assertIsNone(snapshot["workload"]["energy_per_op_J"])

    def test_nested_calibration_mismatch_is_rejected(self):
        snapshot=self.capture(); snapshot["block_metrics"][0]["calibration"]="placed"
        errors=contract.validate_snapshot(snapshot)
        self.assertTrue(any("block_metrics" in error and "top-level physical" in error for error in errors))

    def test_revision_delta_and_paper_outputs(self):
        base=self.capture(); later=copy.deepcopy(base); later["revision"].update({"id":"later","label":"Later synthetic revision","captured_at":"2026-08-12T00:00:00+09:00"})
        later["physical_totals"]["total_power_W"]*=1.1; later["physical_totals"]["dynamic_power_W"]+=.4
        later["categories"]["bf16_fp16"]["total_power_W"]+=.4; later["categories"]["bf16_fp16"]["dynamic_power_W"]+=.4
        later["block_metrics"][0]["total_power_W"]+=.4; later["block_metrics"][0]["dynamic_power_W"]+=.4
        later["thermal"]["peak_temperature_K"]+=2
        with tempfile.TemporaryDirectory() as td:
            revisions=Path(td)/"revisions"; revisions.mkdir(); out=Path(td)/"out"
            (revisions/"base.json").write_text(json.dumps(base),encoding="utf-8"); (revisions/"later.json").write_text(json.dumps(later),encoding="utf-8")
            result=compare.compare(str(revisions),base["revision"]["id"],str(out))
            rows=(out/"paper_revision_table.csv").read_text(encoding="utf-8")
            self.assertEqual(result["revision_count"],2); self.assertIn("10.0",rows)
            for name in result["outputs"]: self.assertTrue((out/name).is_file() and (out/name).stat().st_size>0)

    def test_cross_calibration_delta_is_suppressed(self):
        base=self.capture(); later=copy.deepcopy(base); later["revision"].update({"id":"placed","label":"Placed evidence","captured_at":"2026-08-12T00:00:00+09:00"})
        later["calibration"]["physical"]="placed"
        later["evidence_contract"]["toolchain"].update({"synthesis_tool_version":"0.40","physical_tool":"OpenROAD","physical_tool_version":"2.0"})
        later["evidence_contract"]["operating_point"].update({"pdk":"sky130","library":"sky130_fd_sc_hd","process_corner":"tt","voltage_V":1.8,"temperature_C":25.0})
        for block in later["block_metrics"]: block["calibration"]="placed"
        for category in later["categories"].values():
            if category["blocks"]: category["physical_calibration"]="placed"
        with tempfile.TemporaryDirectory() as td:
            revisions=Path(td)/"revisions"; revisions.mkdir(); out=Path(td)/"out"
            (revisions/"base.json").write_text(json.dumps(base),encoding="utf-8"); (revisions/"later.json").write_text(json.dumps(later),encoding="utf-8")
            compare.compare(str(revisions),base["revision"]["id"],str(out))
            with (out/"paper_delta_table.csv").open(encoding="utf-8") as f: rows=list(__import__("csv").DictReader(f))
        row=next(x for x in rows if x["revision"]=="placed")
        self.assertEqual(row["area_vs_baseline_pct"],""); self.assertEqual(row["area_vs_baseline_policy"],"prohibited")

    def test_calibration_policy_levels(self):
        self.assertTrue(contract.comparison_policy("synthetic","synthetic")["delta_allowed"])
        self.assertEqual(contract.comparison_policy("placed","technology_mapped")["status"],"reference_only")
        self.assertEqual(contract.comparison_policy("synthetic","placed")["status"],"prohibited")

if __name__=="__main__": unittest.main()
