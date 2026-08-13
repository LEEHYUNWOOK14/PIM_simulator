#!/usr/bin/env python3
"""Convert captured GR00T BF16 normalization samples to bank/lane packets."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def read_hex(path: Path) -> list[int]:
    return [int(line.strip(), 16) for line in path.read_text(encoding="ascii").splitlines() if line.strip()]


def raw_sha(values: list[int]) -> str:
    data = bytearray()
    for value in values:
        data.extend(value.to_bytes(2, "little"))
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--banks", type=int, default=16)
    parser.add_argument("--lanes", type=int, default=4)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    trace = json.loads((args.trace / "trace_manifest.json").read_text(encoding="utf-8"))
    summaries = []
    total_mismatches = 0
    total_packets = 0
    for profile_index, (profile, sample) in enumerate(trace["samples"].items()):
        shape = sample["shape"]
        hidden = int(shape[-1])
        rows = math.prod(shape[:-1])
        source = read_hex(args.trace / sample["input_hex"])
        expected_output = read_hex(args.trace / sample["output_hex"])
        if len(source) != rows * hidden or len(expected_output) != rows * hidden:
            raise RuntimeError(f"shape/hex length mismatch for {profile}")
        if raw_sha(source) != sample["input_sha256"]:
            raise RuntimeError(f"input checksum mismatch for {profile}")
        if raw_sha(expected_output) != sample["output_sha256"]:
            raise RuntimeError(f"output checksum mismatch for {profile}")

        vectors_per_bank = math.ceil(hidden / (args.banks * args.lanes))
        reconstructed = [0] * len(source)
        packet_path = args.output / f"{profile}_bank_packets.csv"
        packed_path = args.output / f"{profile}_bank_packets.hex"
        packet_count = 0
        padding_elements = 0
        with packet_path.open("w", newline="", encoding="utf-8") as packet_file, packed_path.open(
            "w", encoding="ascii"
        ) as packed_file:
            fields = [
                "profile_id",
                "tag",
                "row",
                "bank",
                "bank_parity",
                "vector_address",
                "valid_lanes",
                "packed_lane3_to_lane0_hex",
            ]
            writer = csv.DictWriter(packet_file, fieldnames=fields)
            writer.writeheader()
            for row in range(rows):
                tag = 0x1000 + profile_index * 0x400 + row
                if tag > 0xFFFF:
                    raise RuntimeError("16-bit tag space exhausted")
                row_base = row * hidden
                for vector in range(vectors_per_bank):
                    for bank in range(args.banks):
                        lane_values = []
                        valid_lanes = 0
                        for lane in range(args.lanes):
                            column = vector * args.banks * args.lanes + bank * args.lanes + lane
                            if column < hidden:
                                value = source[row_base + column]
                                reconstructed[row_base + column] = value
                                valid_lanes += 1
                            else:
                                value = 0
                                padding_elements += 1
                            lane_values.append(value)
                        packed = "".join(f"{value:04x}" for value in reversed(lane_values))
                        writer.writerow(
                            {
                                "profile_id": profile,
                                "tag": f"{tag:04x}",
                                "row": row,
                                "bank": bank,
                                "bank_parity": "odd" if bank & 1 else "even",
                                "vector_address": vector,
                                "valid_lanes": valid_lanes,
                                "packed_lane3_to_lane0_hex": packed,
                            }
                        )
                        packed_file.write(packed + "\n")
                        packet_count += 1

        mismatches = sum(a != b for a, b in zip(source, reconstructed))
        total_mismatches += mismatches
        total_packets += packet_count
        summaries.append(
            {
                "profile_id": profile,
                "source_shape": shape,
                "rows": rows,
                "hidden_size": hidden,
                "banks": args.banks,
                "lanes": args.lanes,
                "vectors_per_bank": vectors_per_bank,
                "packets": packet_count,
                "padding_elements": padding_elements,
                "input_elements": len(source),
                "input_sha256": sample["input_sha256"],
                "roundtrip_sha256": raw_sha(reconstructed),
                "roundtrip_mismatches": mismatches,
                "tag_base": f"{0x1000 + profile_index * 0x400:04x}",
                "packet_csv": packet_path.name,
                "packet_hex": packed_path.name,
            }
        )

    result = {
        "source_classification": trace["classification"],
        "model": trace["model"],
        "model_revision": trace["model_revision"],
        "mapping": {
            "formula": "column=vector_address*(BANKS*LANES)+bank*LANES+lane",
            "packed_order": "lane3..lane0; each lane is one 16-bit BF16 word",
            "bank_parity": "bank_id bit 0",
            "padding": "zero in invalid tail lanes",
            "tag": "0x1000 + profile_index*0x400 + row",
        },
        "banks": args.banks,
        "lanes": args.lanes,
        "profiles": summaries,
        "total_packets": total_packets,
        "total_roundtrip_mismatches": total_mismatches,
        "status": "PASS" if total_mismatches == 0 else "FAIL",
    }
    (args.output / "mapping_manifest.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    with (args.output / "mapping_summary.csv").open("w", newline="", encoding="utf-8") as file:
        flattened = []
        for summary in summaries:
            item = dict(summary)
            item["source_shape"] = json.dumps(item["source_shape"])
            flattened.append(item)
        writer = csv.DictWriter(file, fieldnames=list(flattened[0]))
        writer.writeheader()
        writer.writerows(flattened)
    print(
        "GROOT_TRACE_TO_RTL PASS "
        f"profiles={len(summaries)} packets={total_packets} "
        f"roundtrip_mismatches={total_mismatches} banks={args.banks} lanes={args.lanes}"
    )
    return 0 if total_mismatches == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
