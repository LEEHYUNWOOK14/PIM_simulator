#!/usr/bin/env python3
"""Export candidate power to a pinned 3D-ICE full-stack steady-state model."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def absolute(path: str | Path) -> Path:
    value = Path(path); return value if value.is_absolute() else ROOT / value


def export(mapped_power: str, output_dir: str) -> dict:
    source = absolute(mapped_power); data = json.loads(source.read_text(encoding="utf-8"))
    if data.get("status") != "PASS" or data.get("unmapped_blocks"): raise ValueError("3D-ICE export requires a fully mapped PASS input")
    output = absolute(output_dir); output.mkdir(parents=True, exist_ok=True)
    floorplan = []
    for index, block in enumerate(data["blocks"]):
        rectangle = block["rectangle_um"]; name = f"B{index}_{re.sub(r'[^A-Za-z0-9_]', '_', block['module'])}"
        floorplan += [f"{name} :", f"  position {float(rectangle['x_um']):.9g}, {float(rectangle['y_um']):.9g} ;", f"  dimension {float(rectangle['width_um']):.9g}, {float(rectangle['height_um']):.9g} ;", f"  power values {float(block['total_power_W']):.12g} ;", ""]
    (output / "logic.flp").write_text("\n".join(floorplan), encoding="ascii")
    (output / "zero.flp").write_text("ZERO :\n  position 0, 0 ;\n  dimension 8000, 12000 ;\n  power values 0 ;\n", encoding="ascii")
    stack_entries = []
    for die in reversed(range(8)):
        stack_entries.append(f'  die DRAM_{die} DRAM floorplan "zero.flp" ;')
        stack_entries.append(f"  layer BUMP_{die} BUMP ;")
    stack_entries.append('  die LOGIC LOGIC_DIE floorplan "logic.flp" ;')
    stack = """material SILICON :
  thermal conductivity 1.30e-04 ;
  volumetric heat capacity 1.631e-12 ;

material UNDERFILL :
  thermal conductivity 5.0e-06 ;
  volumetric heat capacity 1.760e-12 ;

top heat sink :
  heat transfer coefficient 5.0e-09 ;
  temperature 300.0 ;

dimensions :
  chip length 8000, width 12000 ;
  cell length 250, width 750 ;

layer BUMP :
  height 15 ;
  material UNDERFILL ;

die DRAM :
  source 1 SILICON ;
  layer 31 SILICON ;

die LOGIC_DIE :
  source 1 SILICON ;
  layer 99 SILICON ;

stack:
""" + "\n".join(stack_entries) + """

solver:
  steady ;
  initial temperature 300.0 ;

output:
  Tmap ( LOGIC, "temperature_map.txt", final );
  Tflp ( LOGIC, "floorplan_temperature.txt", maximum, final );
"""
    (output / "candidate.stk").write_text(stack, encoding="ascii")
    metadata = {
        "status": "EXPORTED", "source": str(source.relative_to(ROOT)).replace("\\", "/"),
        "input_power_W": float(data["checks"]["mapped_power_W"]), "dram_dies": 8,
        "grid": [32, 16], "solver": "3D-ICE 4.0 commit 4953952a1ef6d38807ff307212a6f15e5b2ef935",
        "classification": "modeled", "signoff": False,
        "limitations": ["effective bump material", "top convection only", "estimated block power", "not calibrated"],
    }
    (output / "3dice_export.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"FLOORPLAN_3DICE_EXPORT PASS power_W={metadata['input_power_W']:.9g} output={output}"); return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--mapped-power", required=True); parser.add_argument("--output", required=True)
    args = parser.parse_args(); export(args.mapped_power, args.output); return 0


if __name__ == "__main__": raise SystemExit(main())
