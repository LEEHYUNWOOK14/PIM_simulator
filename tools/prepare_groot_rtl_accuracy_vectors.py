#!/usr/bin/env python3
"""Prepare one captured BF16 row per GR00T profile for RTL replay."""

from __future__ import annotations

import csv
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "reports/groot_normalization/results/actual_groot/action_head_trace"
OUT = ROOT / "reports/groot_normalization/results/actual_groot/rtl_accuracy_vectors"
OUT.mkdir(parents=True, exist_ok=True)


def bf16_bits(value: float) -> int:
    word = struct.unpack(">I", struct.pack(">f", value))[0]
    if (word & 0x7F800000) != 0x7F800000:
        word += 0x7FFF + ((word >> 16) & 1)
    return (word >> 16) & 0xFFFF


def read_hex(path: Path) -> list[str]:
    return [line.strip().lower() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]


def write_words(path: Path, words: list[str]) -> None:
    path.write_text("\n".join(words) + "\n", encoding="ascii")


def main() -> int:
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    rows = []
    for profile, sample in manifest["samples"].items():
        hidden = int(sample["shape"][-1])
        epsilon = 1.0e-6 if profile == "action_dit_norm_out" else 1.0e-5
        paths = {}
        for field, suffix in (
            ("input_hex", "x"),
            ("gamma_hex", "gamma"),
            ("beta_hex", "beta"),
            ("output_hex", "expected"),
        ):
            source = read_hex(TRACE / sample[field])
            words = source[:hidden] if field in ("input_hex", "output_hex") else source
            if len(words) != hidden:
                raise RuntimeError(f"{profile} {field} length {len(words)} != {hidden}")
            destination = OUT / f"{profile}_{suffix}.hex"
            write_words(destination, words)
            paths[suffix] = destination.relative_to(ROOT).as_posix()
        rows.append(
            {
                "profile_id": profile,
                "hidden_size": hidden,
                "epsilon": epsilon,
                "epsilon_bf16": f"{bf16_bits(epsilon):04x}",
                "inv_hidden_bf16": f"{bf16_bits(1.0 / hidden):04x}",
                "x_file": paths["x"],
                "gamma_file": paths["gamma"],
                "beta_file": paths["beta"],
                "expected_file": paths["expected"],
                "source_classification": manifest["classification"],
            }
        )
    with (OUT / "cases.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"GROOT_RTL_ACCURACY_VECTORS PASS cases={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
