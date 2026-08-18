#!/usr/bin/env python3
"""Gate B-variant actual traces against C11 bit-exact and PyTorch accuracy."""

from __future__ import annotations

import csv
import argparse
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "reports/groot_normalization/results/multirow_l4_vectors"
DEFAULT_RESULTS = ROOT / "reports/groot_normalization/results/quad_local_ab_actual_trace"
B2_RESULTS = ROOT / "reports/groot_normalization/results/quad_local_b2_actual_trace"
THRESHOLD = 0.025


def words(path: Path) -> list[int]:
    return [int(value, 16) for value in path.read_text(encoding="ascii").split()]


def bf16(value: int) -> float:
    return struct.unpack(">f", struct.pack(">I", value << 16))[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--b2", action="store_true")
    parser.add_argument("--results")
    parser.add_argument("--variant")
    args = parser.parse_args()
    results = Path(args.results).resolve() if args.results else (B2_RESULTS if args.b2 else DEFAULT_RESULTS)
    rows = []
    with (VECTORS / "cases.csv").open(encoding="utf-8") as stream:
        cases = list(csv.DictReader(stream))
    for case in cases:
        profile = case["profile_id"]
        actual = words(results / f"{profile}_actual.hex")
        model = words(VECTORS / f"{profile}_mixed_expected.hex")
        pytorch = words(VECTORS / f"{profile}_pytorch_expected.hex")
        if not (len(actual) == len(model) == len(pytorch)):
            raise RuntimeError(f"length mismatch for {profile}")
        errors = [abs(bf16(got) - bf16(want)) for got, want in zip(actual, pytorch)]
        nonfinite = sum(not math.isfinite(bf16(value)) for value in actual)
        model_mismatches = sum(got != want for got, want in zip(actual, model))
        pytorch_mismatches = sum(got != want for got, want in zip(actual, pytorch))
        maximum = max(errors, default=0.0)
        result = (
            "PASS"
            if model_mismatches == 0 and nonfinite == 0 and maximum <= THRESHOLD
            else "FAIL"
        )
        rows.append(
            {
                "profile_id": profile,
                "elements": len(actual),
                "c11_bit_mismatches": model_mismatches,
                "pytorch_bit_mismatches": pytorch_mismatches,
                "max_abs": maximum,
                "nonfinite": nonfinite,
                "threshold": THRESHOLD,
                "result": result,
            }
        )
    payload = {
        "schema_version": 1,
        "variant": args.variant or (
            "logic_die_normalization_hbm_quad_local_b2_top"
            if args.b2
            else "logic_die_normalization_hbm_quad_local_ab_top"
        ),
        "profiles": rows,
        "passed_profiles": sum(row["result"] == "PASS" for row in rows),
        "failed_profiles": sum(row["result"] == "FAIL" for row in rows),
        "overall_result": "PASS" if all(row["result"] == "PASS" for row in rows) else "FAIL",
    }
    results.mkdir(parents=True, exist_ok=True)
    (results / "accuracy_summary.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )
    with (results / "accuracy_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(
        "WBQ_QUAD_LOCAL_ACTUAL_TRACE_ACCURACY "
        f"result={payload['overall_result']} passed={payload['passed_profiles']} "
        f"failed={payload['failed_profiles']} threshold={THRESHOLD}"
    )
    return 0 if payload["overall_result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
