from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools/analyze_logic_die_pcu_system.py"
SPEC = importlib.util.spec_from_file_location("pcu_system", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
pcu = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = pcu
SPEC.loader.exec_module(pcu)


class LogicDiePcuSystemTest(unittest.TestCase):
    def test_transaction_counts_are_exact(self) -> None:
        result = pcu.simulate_call(7, 1536, 8, bank_port_mode="single_shared")
        vectors = 7 * (1536 // (16 * 8))
        self.assertEqual(result.reduction_read_vectors, vectors)
        self.assertEqual(result.replay_read_vectors, vectors)
        self.assertEqual(result.writeback_vectors, vectors)

    def test_split_ports_are_not_slower(self) -> None:
        shared = pcu.simulate_call(41, 1536, 8, bank_port_mode="single_shared")
        split = pcu.simulate_call(41, 1536, 8, bank_port_mode="split_rw")
        independent = pcu.simulate_call(41, 1536, 8, bank_port_mode="independent_pcu_ports")
        self.assertLessEqual(split.cycles, shared.cycles)
        self.assertLessEqual(independent.cycles, split.cycles)

    def test_lane_scaling_reduces_cycles(self) -> None:
        cycles = [pcu.simulate_call(41, 1536, lanes).cycles for lanes in (4, 8, 16)]
        self.assertGreater(cycles[0], cycles[1])
        self.assertGreater(cycles[1], cycles[2])

    def test_external_and_internal_traffic_are_not_conflated(self) -> None:
        workload = [{
            "invocations": 2,
            "tensor_bytes_per_call": 1024,
            "affine_bytes_per_call": 128,
            "rows": 4,
        }]
        traffic = pcu.traffic_for_workload(workload)
        self.assertEqual(traffic["gpu_external_bytes"], 4352)
        self.assertEqual(traffic["pcu_external_bytes_resident"], 64)
        self.assertEqual(traffic["bank_array_reduction_read_bytes"], 2048)
        self.assertEqual(traffic["bank_array_replay_read_bytes"], 2048)
        self.assertGreater(traffic["external_reduction_fraction_resident"], 0.98)

    def test_cycle_model_matches_integrated_rtl_within_three_percent(self) -> None:
        # Authoritative cycles are emitted by the integrated PCU trace tests.
        measured = [
            (8, 128, True, 200),
            (4, 2048, True, 196),
            (8, 128, False, 224),
            (41, 1536, False, 1065),
            (280, 2048, False, 9017),
        ]
        for rows, hidden, rms_norm, rtl_cycles in measured:
            modeled = pcu.simulate_call(
                rows, hidden, 8, bank_port_mode="split_rw", rms_norm=rms_norm
            ).cycles
            error = abs(modeled - rtl_cycles) / rtl_cycles
            self.assertLessEqual(error, 0.03, (rows, hidden, modeled, rtl_cycles))


if __name__ == "__main__":
    unittest.main()
