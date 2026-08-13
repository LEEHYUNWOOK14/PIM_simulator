import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPO_ROOT / "tools" / "b0_b1_artifact_audit.py"
SPEC = importlib.util.spec_from_file_location("b0_b1_artifact_audit", TOOL_PATH)
audit = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(audit)


METRIC_NAMES = {
    "area_um2": "um2",
    "critical_path_ns": "ns",
    "power_mw": "mW",
    "energy_pj_per_work": "pJ/work",
    "congestion_overflow": "count",
    "utilization_pct": "%",
}


class ArtifactAuditTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "design").mkdir()
        self.metric_schema = {
            "schema_version": 1,
            "metrics": {
                name: {
                    "unit": unit, "required": True, "aliases": [],
                    **({"valid_min": 0, "pass_max": 0} if name == "congestion_overflow" else {"valid_exclusive_min": 0}),
                }
                for name, unit in METRIC_NAMES.items()
            },
        }
        self.write_json("design/metrics.json", self.metric_schema)
        self.profile = {
            "schema_version": 1,
            "repository_root": ".",
            "metric_schema": "design/metrics.json",
            "comparison_keys": ["workload_id", "clock_period_ns", "technology", "library_id", "physical_options_id"],
            "equal_digest_groups": ["source", "tool", "library", "sdc", "stimulus"],
            "experiments": {},
        }
        for experiment in ("b0", "b1"):
            self.profile["experiments"][experiment] = {
                "completion_token": f"tokens/{experiment}.json",
                "groups": {name: {"paths": [f"{experiment}/{name}.txt"]} for name in ("source", "tool", "library", "sdc", "stimulus")},
                "required_artifacts": [f"{experiment}/result.dat"],
                "metric_sources": [f"{experiment}/metrics.csv"],
            }
        self.write_json("design/profile.json", self.profile)

    def tearDown(self):
        self.temporary.cleanup()

    def write_json(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def prepare(self, experiment, context=None, source_text="same source"):
        base = self.root / experiment
        base.mkdir(parents=True, exist_ok=True)
        values = {"source": source_text, "tool": "same tool", "library": "same library", "sdc": "same sdc", "stimulus": "same stimulus"}
        for name, value in values.items():
            (base / f"{name}.txt").write_text(value, encoding="utf-8")
        (base / "result.dat").write_text("complete", encoding="utf-8")
        with (base / "metrics.csv").open("w", encoding="utf-8", newline="") as stream:
            stream.write("metric,value,unit,evidence\n")
            for index, (name, unit) in enumerate(METRIC_NAMES.items(), 1):
                value = 0 if name == "congestion_overflow" else index
                stream.write(f"{name},{value},{unit},MEASURED\n")
        default_context = {
            "workload_id": "shared-v1", "clock_period_ns": 10.0, "technology": "sky130hd",
            "library_id": "tt-025c-1v80", "physical_options_id": "u30-ar1-m2-d035",
        }
        self.write_json(f"tokens/{experiment}.json", {
            "status": "COMPLETE", "experiment_id": experiment, "producer_exit_code": 0,
            "completed_at": "2026-08-13T00:00:00+09:00", "comparison_context": context or default_context,
        })

    def capture(self, experiment):
        return audit.capture(
            self.root / "design/profile.json", experiment, self.root / f"snapshots/{experiment}.json", 0, 0
        )

    def test_missing_token_is_pending_without_touching_guarded_tree(self):
        result = self.capture("b0")
        self.assertEqual("PENDING", result["status"])
        self.assertIn("completion token absent", result["reasons"][0])

    def test_complete_snapshots_compare_and_compute_deltas(self):
        self.prepare("b0")
        self.prepare("b1")
        self.assertEqual("PASS", self.capture("b0")["status"])
        self.assertEqual("PASS", self.capture("b1")["status"])
        result = audit.compare_snapshots(
            self.root / "design/profile.json", self.root / "snapshots/b0.json", self.root / "snapshots/b1.json"
        )
        self.assertEqual("PASS", result["status"])
        self.assertTrue(result["comparable"])
        self.assertTrue(all(row["delta"] == 0 for row in result["metrics"]))

    def test_workload_mismatch_is_not_comparable(self):
        self.prepare("b0")
        context = {
            "workload_id": "different", "clock_period_ns": 10.0, "technology": "sky130hd",
            "library_id": "tt-025c-1v80", "physical_options_id": "u30-ar1-m2-d035",
        }
        self.prepare("b1", context=context)
        self.capture("b0")
        self.capture("b1")
        result = audit.compare_snapshots(
            self.root / "design/profile.json", self.root / "snapshots/b0.json", self.root / "snapshots/b1.json"
        )
        self.assertEqual("NOT_COMPARABLE", result["status"])
        self.assertIn("comparison context mismatch workload_id", "\n".join(result["reasons"]))
        self.assertTrue(all(row["delta"] is None for row in result["metrics"]))

    def test_source_hash_mismatch_is_not_comparable(self):
        self.prepare("b0")
        self.prepare("b1", source_text="changed source")
        self.capture("b0")
        self.capture("b1")
        result = audit.compare_snapshots(
            self.root / "design/profile.json", self.root / "snapshots/b0.json", self.root / "snapshots/b1.json"
        )
        self.assertEqual("NOT_COMPARABLE", result["status"])
        self.assertIn("hash mismatch: source", result["reasons"])

    def test_completed_but_missing_required_artifact_fails(self):
        self.prepare("b0")
        (self.root / "b0/result.dat").unlink()
        result = self.capture("b0")
        self.assertEqual("FAIL", result["status"])
        self.assertIn("missing or empty artifact: b0/result.dat", result["reasons"])

    def test_metric_gate_failure_fails_completed_snapshot(self):
        self.prepare("b0")
        metric_path = self.root / "b0/metrics.csv"
        metric_path.write_text(metric_path.read_text(encoding="utf-8").replace("congestion_overflow,0", "congestion_overflow,3"), encoding="utf-8")
        # Refresh the completion assertion after intentionally producing the fixture.
        token = json.loads((self.root / "tokens/b0.json").read_text(encoding="utf-8"))
        self.write_json("tokens/b0.json", token)
        result = self.capture("b0")
        self.assertEqual("FAIL", result["status"])
        self.assertIn("metric gate failed congestion_overflow", "\n".join(result["reasons"]))

    def test_absent_snapshot_comparison_is_pending_and_html_renders(self):
        result = audit.compare_snapshots(
            self.root / "design/profile.json", self.root / "snapshots/b0.json", self.root / "snapshots/b1.json"
        )
        self.assertEqual("PENDING", result["status"])
        output = self.root / "comparison.html"
        audit.render_html(result, output)
        rendered = output.read_text(encoding="utf-8")
        self.assertIn("PENDING", rendered)
        self.assertIn("area_um2", rendered)


if __name__ == "__main__":
    unittest.main()
