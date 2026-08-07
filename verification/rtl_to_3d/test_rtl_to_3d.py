import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
import collect_rtl_physical_inputs as collect
import rtl_to_3d_power_map as mapper
import run_hbm2_thermal as thermal

FIX=ROOT/"verification/rtl_to_3d/fixtures"

class RtlTo3DTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc=json.loads((FIX/"synthetic_input.json").read_text(encoding="utf-8"))
        cls.rules=mapper.read_json("design/rtl_to_3d/mapping_rules.json")
        cls.arch=mapper.read_json("design/hbm2_architecture.json")

    def map(self,doc=None,allow=False):
        return mapper.map_document(copy.deepcopy(doc or self.doc),self.rules,self.arch,allow)

    def test_fixture_maps_and_conserves_power(self):
        result=self.map(); self.assertEqual(result["status"],"PASS")
        self.assertEqual(len(result["blocks"]),5); self.assertEqual(result["checks"]["mapped_power_W"],4.0)
        self.assertLessEqual(result["checks"]["power_conservation_error_W"],1e-12)

    def test_bank_coordinates_are_derived(self):
        result=self.map(); last=result["blocks"][-1]
        self.assertEqual(last["target"]["channel"],7); self.assertEqual(last["target"]["bank"],15)
        self.assertEqual(last["rectangle_um"],{"x_um":7750.0,"y_um":9000.0,"width_um":250.0,"height_um":3000.0})

    def test_wrong_units_are_rejected(self):
        doc=copy.deepcopy(self.doc); doc["units"]["power"]="mW"
        with self.assertRaisesRegex(mapper.MappingError,"units must be exactly"): self.map(doc)

    def test_out_of_bounds_is_rejected(self):
        doc=copy.deepcopy(self.doc); doc["blocks"][0]["placement"]["x_um"]=7900
        with self.assertRaisesRegex(mapper.MappingError,"outside"): self.map(doc)

    def test_unmapped_is_detected_and_fails_by_default(self):
        doc=copy.deepcopy(self.doc); doc["blocks"][0]["instance"]="top.unknown"; doc["blocks"][0]["module"]="unknown"
        with self.assertRaisesRegex(mapper.MappingError,"unmapped RTL blocks"): self.map(doc)
        result=self.map(doc,True); self.assertEqual(result["status"],"PASS_WITH_UNMAPPED")
        self.assertEqual(result["checks"]["unmapped_detection"],"DETECTED")

    def test_collection_from_replaceable_reports(self):
        with tempfile.TemporaryDirectory() as td:
            result=collect.collect(str(FIX/"report_manifest.json"),str(Path(td)/"normalized.json"))
        self.assertEqual(len(result["blocks"]),5); self.assertTrue(result["sources"]["activity"].endswith("synthetic_activity.vcd"))

    def test_thermal_rasterization_conserves_power(self):
        result=self.map()
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/"mapped.json"; path.write_text(json.dumps(result),encoding="utf-8")
            cfg=thermal.load_json("design/thermal/hbm2_thermal_config.json")
            layers=thermal.build_layers(cfg,self.arch)
            width=self.arch["geometry_um"]["die_width"]["value"]*1e-6
            height=self.arch["geometry_um"]["die_height"]["value"]*1e-6
            power,events,_=thermal.mapped_power_map(path,layers,32,16,1,width,height)
        self.assertEqual(events,[]); self.assertAlmostEqual(float(power.sum()),4.0,places=12)

if __name__=="__main__": unittest.main()
