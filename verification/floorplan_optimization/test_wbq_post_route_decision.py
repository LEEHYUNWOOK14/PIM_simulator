from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import collect_wbq_global_route_evidence as collector  # noqa: E402
from decide_wbq_post_route import (  # noqa: E402
    SCHEMA_V1_ARTIFACT_KEYS,
    SCHEMA_V2_ARTIFACT_KEYS,
    decide,
)

# Deliberately independent of the consumer constants: a producer/consumer drift
# must fail this test instead of silently changing the fixture with the consumer.
V1_ARTIFACT_KEYS = {
    "route_log",
    "route_guide",
    "congestion_report",
    "routed_odb",
    "routed_sdc",
}
V2_ARTIFACT_KEYS = V1_ARTIFACT_KEYS | {"placement_manifest_at_route_launch"}


def artifact_record(path: Path) -> dict[str, str | int]:
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


class WbqPostRouteDecisionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.artifacts = {}
        for name in V2_ARTIFACT_KEYS:
            path = self.directory / name
            path.write_text(name, encoding="utf-8")
            self.artifacts[name] = artifact_record(path)
        self.manifest = self.make_manifest(schema_version=2)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def make_manifest(self, schema_version: int) -> dict:
        keys = V1_ARTIFACT_KEYS if schema_version == 1 else V2_ARTIFACT_KEYS
        return {
            "schema_version": schema_version,
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
            "artifacts": {name: self.artifacts[name] for name in keys},
        }

    def run_case(self, document: dict) -> dict:
        path = self.directory / "manifest.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return decide(path)

    def test_versioned_contract_is_explicit(self) -> None:
        self.assertEqual(set(SCHEMA_V1_ARTIFACT_KEYS), V1_ARTIFACT_KEYS)
        self.assertEqual(set(SCHEMA_V2_ARTIFACT_KEYS), V2_ARTIFACT_KEYS)

    def test_v1_pass_pf4_remains_supported(self) -> None:
        result = self.run_case(self.make_manifest(schema_version=1))
        self.assertTrue(result["evidence_valid"])
        self.assertEqual(result["decision"], "PHASE6_CLOCK_AND_DETAILED_ROUTE")

    def test_v2_pass_pf4_selects_phase6(self) -> None:
        result = self.run_case(self.manifest)
        self.assertTrue(result["evidence_valid"])
        self.assertEqual(result["source_schema_version"], 2)
        self.assertEqual(result["decision"], "PHASE6_CLOCK_AND_DETAILED_ROUTE")

    def test_nonzero_valid_route_selects_phase5(self) -> None:
        document = copy.deepcopy(self.manifest)
        document["verdict"] = "IMPROVED_NOT_CLOSED"
        document["current_wbq"]["residual_congestion"] = 1
        document["current_wbq"]["overflow_edges"] = 1
        self.assertEqual(
            self.run_case(document)["decision"],
            "PHASE5_HIERARCHICAL_ARCHITECTURE",
        )

    def test_v2_extra_artifact_stops(self) -> None:
        document = copy.deepcopy(self.manifest)
        document["artifacts"]["unexpected"] = self.artifacts["route_log"]
        result = self.run_case(document)
        self.assertFalse(result["checks"]["artifact_inventory"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")

    def test_v2_missing_launch_manifest_stops(self) -> None:
        document = copy.deepcopy(self.manifest)
        document["artifacts"].pop("placement_manifest_at_route_launch")
        result = self.run_case(document)
        self.assertFalse(result["checks"]["artifact_inventory"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")

    def test_unknown_schema_stops(self) -> None:
        document = copy.deepcopy(self.manifest)
        document["schema_version"] = 3
        result = self.run_case(document)
        self.assertFalse(result["checks"]["schema_version"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")

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


class WbqCollectorDecisionIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.raw = self.directory / "raw"
        self.out = self.directory / "out"
        self.raw.mkdir()
        self.out.mkdir()

        self.baseline = self.raw / "physical_feasibility_metrics.json"
        self.place_manifest = self.out / "wbq_placement_manifest.json"
        self.route_log = self.raw / "route.log"
        self.congestion = self.raw / "route.congestion.rpt"
        self.summary = self.raw / "route.congestion.summary"
        self.sources = self.raw / "route.sources.summary"
        self.guide = self.raw / "route.route_guide"
        self.odb = self.raw / "route.odb"
        self.sdc = self.raw / "route.sdc"

        self.baseline.write_text(
            json.dumps(
                {
                    "v4_distributed_landing_pad_route": {
                        "pin_model": "565 distributed internal met5 20um landing pads",
                        "remaining_congestion": 2,
                        "report_entries": 4,
                        "report_overflow_edges": 2,
                        "report_total_overflow_tracks": 5,
                    }
                }
            ),
            encoding="utf-8",
        )
        placed_odb = self.raw / "placed.odb"
        placed_sdc = self.raw / "placed.sdc"
        placed_odb.write_text("placed odb", encoding="utf-8")
        placed_sdc.write_text("placed sdc", encoding="utf-8")
        place_document = {
            "gate_pass": True,
            "artifacts": {
                "placed_odb": artifact_record(placed_odb),
                "placed_sdc": artifact_record(placed_sdc),
            },
        }
        self.place_manifest.write_text(json.dumps(place_document), encoding="utf-8")
        place_manifest_sha = hashlib.sha256(self.place_manifest.read_bytes()).hexdigest()
        self.route_log.write_text(
            "\n".join(
                [
                    "WBQ_ROUTE_GIT_SHA=fixture",
                    f"WBQ_ROUTE_PLACE_ODB_SHA256={place_document['artifacts']['placed_odb']['sha256']}",
                    f"WBQ_ROUTE_PLACE_SDC_SHA256={place_document['artifacts']['placed_sdc']['sha256']}",
                    f"WBQ_ROUTE_PLACE_MANIFEST_SHA256={place_manifest_sha}",
                    "WBQ_ROUTE_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD",
                    "WBQ_ROUTE_SIGNAL_LAYERS=met1-met5",
                    "WBQ_ROUTE_CLOCK_LAYERS=met2-met5",
                    "WBQ_ROUTE_CONGESTION_ITERATIONS=1",
                    "WBQ_ROUTE_GLOBAL_ROUTER=CUGR",
                    "WBQ_ROUTE_SKIP_LARGE_FANOUT_NETS=5000",
                    "WBQ_V4_CONTROL_BUMP_PIN_COUNT 565",
                    "Iterative RRR finished with congestion remaining (1)",
                    "Skipping net clk_i with 6000 terminals",
                    "WBQ_ROUTE_EXIT_CODE=0",
                    "NORMALIZATION_HBM_WBQ_V4_CONTROL_ROUTE PASS",
                    "Elapsed (wall clock) time (h:mm:ss or m:ss): 0:01",
                    "Maximum resident set size (kbytes): 1024",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        self.congestion.write_text("fixture congestion\n", encoding="utf-8")
        self.summary.write_text(
            "entries=3\noverflow_edges=1\ntotal_overflow_tracks=2\n"
            "max_congestion=3\nmax_capacity=2\nmax_usage=3\n",
            encoding="utf-8",
        )
        self.sources.write_text("bank=1\nwriteback=1\n", encoding="utf-8")
        self.guide.write_text("fixture guide\n", encoding="utf-8")
        self.odb.write_text("fixture routed odb\n", encoding="utf-8")
        self.sdc.write_text("fixture routed sdc\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def collect(self) -> tuple[Path, dict]:
        with mock.patch.multiple(
            collector,
            BASELINE=self.baseline,
            PLACE_MANIFEST=self.place_manifest,
            ROUTE_LOG=self.route_log,
            CONGESTION=self.congestion,
            SUMMARY=self.summary,
            SOURCES=self.sources,
            GUIDE=self.guide,
            ODB=self.odb,
            SDC=self.sdc,
            OUT=self.out,
        ):
            self.assertEqual(collector.main(), 0)
        manifest_path = self.out / "wbq_global_route_manifest.json"
        return manifest_path, json.loads(manifest_path.read_text(encoding="utf-8"))

    def write_case(self, name: str, document: dict) -> Path:
        path = self.out / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_collector_v2_output_is_accepted_by_decision_gate(self) -> None:
        manifest_path, document = self.collect()
        self.assertEqual(document["schema_version"], 2)
        self.assertEqual(set(document["artifacts"]), V2_ARTIFACT_KEYS)
        result = decide(manifest_path)
        self.assertTrue(result["evidence_valid"])
        self.assertEqual(result["decision"], "PHASE5_HIERARCHICAL_ARCHITECTURE")

    def test_collector_output_with_extra_artifact_is_rejected(self) -> None:
        _, document = self.collect()
        document["artifacts"]["unexpected"] = document["artifacts"]["route_log"]
        result = decide(self.write_case("extra.json", document))
        self.assertFalse(result["checks"]["artifact_inventory"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")

    def test_collector_output_missing_launch_manifest_is_rejected(self) -> None:
        _, document = self.collect()
        document["artifacts"].pop("placement_manifest_at_route_launch")
        result = decide(self.write_case("missing.json", document))
        self.assertFalse(result["checks"]["artifact_inventory"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")

    def test_collector_output_with_tampered_artifact_is_rejected(self) -> None:
        manifest_path, _ = self.collect()
        self.odb.write_text("tampered routed odb\n", encoding="utf-8")
        result = decide(manifest_path)
        self.assertFalse(result["checks"]["artifact_routed_odb"])
        self.assertEqual(result["decision"], "STOP_INVALID_RUN")


if __name__ == "__main__":
    unittest.main()
