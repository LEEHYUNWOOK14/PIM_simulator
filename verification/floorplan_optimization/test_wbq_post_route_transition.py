from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import run_wbq_post_route_transition as transition  # noqa: E402


class WbqPostRouteTransitionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.status = self.directory / "status.json"
        self.decision = self.directory / "decision.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def read_status(self) -> dict:
        return json.loads(self.status.read_text(encoding="utf-8"))

    def test_pipeline_records_both_passed_stages_and_selected_next_stage(self) -> None:
        def run(command: list[str], **_: object) -> subprocess.CompletedProcess:
            if "decide_wbq_post_route.py" in command[1]:
                self.decision.write_text(
                    json.dumps(
                        {
                            "decision": "PHASE5_HIERARCHICAL_ARCHITECTURE",
                            "verdict": "IMPROVED_NOT_CLOSED",
                            "evidence_valid": True,
                        }
                    ),
                    encoding="utf-8",
                )
            return subprocess.CompletedProcess(command, 0)

        with mock.patch.object(transition.subprocess, "run", side_effect=run):
            self.assertEqual(transition.run_pipeline(self.status, self.decision), 0)

        document = self.read_status()
        self.assertEqual(document["status"], "PASS")
        self.assertEqual(document["next_stage"], "PHASE5_HIERARCHICAL_ARCHITECTURE")
        self.assertEqual(
            document["stages"]["collect_global_route_evidence"]["status"],
            "PASS",
        )
        self.assertEqual(document["stages"]["decide_post_route"]["status"], "PASS")

    def test_command_failure_records_fail_and_stop(self) -> None:
        with mock.patch.object(
            transition.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 7),
        ):
            self.assertEqual(transition.run_pipeline(self.status, self.decision), 1)
        document = self.read_status()
        self.assertEqual(document["status"], "FAIL")
        self.assertEqual(document["next_stage"], "STOP")
        self.assertEqual(
            document["stages"]["collect_global_route_evidence"]["detail"],
            "exit_code=7",
        )

    def test_waiting_approval_is_explicit_and_resumable(self) -> None:
        transition.mark_waiting_approval(
            self.status,
            "launch_phase5_candidate",
            "sandbox authorization pending",
        )
        document = self.read_status()
        self.assertEqual(document["status"], "WAITING_APPROVAL")
        self.assertEqual(
            document["next_stage"],
            "RESUME_launch_phase5_candidate_AFTER_APPROVAL",
        )
        self.assertEqual(
            document["stages"]["launch_phase5_candidate"]["detail"],
            "sandbox authorization pending",
        )


if __name__ == "__main__":
    unittest.main()
