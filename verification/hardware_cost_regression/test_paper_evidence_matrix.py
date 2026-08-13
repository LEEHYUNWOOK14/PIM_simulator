from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import paper_evidence_matrix as evidence


class PaperEvidenceMatrixTests(unittest.TestCase):
    def test_all_six_classes_are_present_and_current_routing_is_blocked(self):
        matrix, errors = evidence.build()
        self.assertEqual(errors, [])
        self.assertEqual(
            {row["classification"] for row in matrix["results"]},
            {"rtl_simulated", "synthesized", "placed", "modeled", "estimated", "illustrative"},
        )
        routing = next(row for row in matrix["results"] if row["basis"] == "global_routing")
        self.assertEqual(routing["gate_status"], "FAIL")
        self.assertEqual(routing["classification"], "placed")
        self.assertEqual(routing["claim_status"], "BLOCKED")
        self.assertFalse(matrix["routing_claim_allowed"])
        for row in matrix["results"]:
            self.assertTrue(all(len(record["sha256"]) == 64 for record in row["evidence_records"]))

    def test_pf4_pending_rejects_affirmative_routing_wording(self):
        violations = evidence.routing_overclaims("The design is routing feasible.", "paper.md", "PENDING")
        self.assertEqual(len(violations), 1)
        self.assertEqual(len(evidence.routing_overclaims("Global-routing feasibility only.", "paper.md", "PENDING")), 1)
        self.assertEqual(evidence.routing_overclaims("Routing feasibility remains unestablished.", "paper.md", "PENDING"), [])

    def test_missing_gate_blocks_claim(self):
        physical = {"gates": {"PF-4": {"status": "PENDING"}}}
        item = {
            "id": "route",
            "basis": "global_routing",
            "required_gate": "PF-4",
            "evidence": [],
        }
        row = evidence.classify_result(copy.deepcopy(item), physical)
        self.assertEqual(row["claim_status"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
