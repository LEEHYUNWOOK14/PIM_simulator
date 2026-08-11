"""Run inside KLayout's embedded Python in headless mode."""

import json
import os

import pya


gds_path = os.environ["STOB_HBM2_GDS"]
manifest_path = os.environ["STOB_HBM2_MANIFEST"]
layout = pya.Layout()
layout.read(gds_path)
top_names = sorted(cell.name for cell in layout.top_cells())
with open(manifest_path, "r", encoding="utf-8") as stream:
    manifest = json.load(stream)
if manifest["top_cell"] not in top_names:
    raise RuntimeError("expected top cell not found: " + manifest["top_cell"])
for index in range(manifest["dram_dies"]):
    name = "DRAM_DIE_{:02d}_8PHYSICAL_CHANNELS".format(index)
    if layout.cell(name) is None:
        raise RuntimeError("missing DRAM die cell: " + name)
print("KLAYOUT_HBM2_GDS PASS: " + manifest["top_cell"], flush=True)

