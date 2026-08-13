import json
import os
import pya

gds_path = os.environ["STOB_FLOORPLAN_GDS"]
manifest_path = os.environ["STOB_FLOORPLAN_VIS_MANIFEST"]
with open(manifest_path, "r", encoding="utf-8") as stream:
    expected = json.load(stream)
layout = pya.Layout()
layout.read(gds_path)
tops = layout.top_cells()
names = [cell.name for cell in tops]
if expected["top_cell"] not in names:
    raise RuntimeError("missing floorplan top cell: " + expected["top_cell"])
top = next(cell for cell in tops if cell.name == expected["top_cell"])

def count_layers(layer_numbers):
    total = 0
    for index in layout.layer_indices():
        if layout.get_info(index).layer not in layer_numbers:
            continue
        iterator = top.begin_shapes_rec(index)
        while not iterator.at_end():
            total += 1
            iterator.next()
    return total

tsv = count_layers(range(120, 127))
bumps = count_layers(range(140, 147))
if tsv != expected["counts"]["tsv_shapes"]:
    raise RuntimeError(f"TSV shape mismatch: {tsv} != {expected['counts']['tsv_shapes']}")
if bumps != expected["counts"]["micro_bump_shapes"]:
    raise RuntimeError(f"micro-bump shape mismatch: {bumps} != {expected['counts']['micro_bump_shapes']}")
if top.bbox().empty():
    raise RuntimeError("floorplan top bbox is empty")
print(f"KLAYOUT_FLOORPLAN_GDS PASS top={top.name} tsv={tsv} bumps={bumps} bbox={top.bbox()}", flush=True)
