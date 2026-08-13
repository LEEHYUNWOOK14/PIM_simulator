#!/usr/bin/env python3
"""Export candidate mapped-power IR as a HotSpot 2-D floorplan and trace."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def export(mapped_power: str, output_dir: str) -> dict:
    source = absolute(mapped_power)
    data = json.loads(source.read_text(encoding="utf-8"))
    if data.get("status") != "PASS" or data.get("unmapped_blocks"):
        raise ValueError("HotSpot export requires a fully mapped PASS input")
    output = absolute(output_dir); output.mkdir(parents=True, exist_ok=True)
    names, floorplan, powers = [], [], []
    for index, block in enumerate(data["blocks"]):
        name = f"B{index}_{re.sub(r'[^A-Za-z0-9_]', '_', block['module'])}"
        rectangle = block["rectangle_um"]
        names.append(name)
        floorplan.append("\t".join((
            name,
            f"{float(rectangle['width_um']) * 1e-6:.12g}",
            f"{float(rectangle['height_um']) * 1e-6:.12g}",
            f"{float(rectangle['x_um']) * 1e-6:.12g}",
            f"{float(rectangle['y_um']) * 1e-6:.12g}",
        )))
        powers.append(f"{float(block['total_power_W']):.12g}")
    (output / "candidate.flp").write_text("\n".join(floorplan) + "\n", encoding="ascii")
    (output / "candidate.ptrace").write_text("\t".join(names) + "\n" + "\t".join(powers) + "\n", encoding="ascii")
    metadata = {
        "status": "EXPORTED", "source": str(source.relative_to(ROOT)).replace("\\", "/"),
        "blocks": names, "input_power_W": sum(map(float, powers)),
        "solver": "HotSpot f18831e48cef5d62580585cca0d7fab6c71bc3cc",
        "model": "2-D silicon block model; upstream example1 configuration with ambient/t_chip overrides",
        "classification": "modeled", "signoff": False,
        "limitations": ["not the reference solver 3-D stack", "generic package parameters", "estimated candidate power"],
    }
    (output / "hotspot_export.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"FLOORPLAN_HOTSPOT_EXPORT PASS blocks={len(names)} power_W={metadata['input_power_W']:.9g}")
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mapped-power", required=True); parser.add_argument("--output", required=True)
    args = parser.parse_args(); export(args.mapped_power, args.output); return 0


if __name__ == "__main__": raise SystemExit(main())
