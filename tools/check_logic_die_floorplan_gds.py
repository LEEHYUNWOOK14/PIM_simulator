import json
import math
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

# The overlay is only usable for final integration when its independently read
# geometry occupies the exact coordinate frame declared by the canonical
# manifest.  Older visualization manifests did not cache this value, so derive
# it from their referenced canonical manifest while keeping the check strict.
geometry = expected.get("geometry", {})
expected_bbox_um = geometry.get("expected_top_bbox_um")
if expected_bbox_um is None:
    with open(expected["manifest"], "r", encoding="utf-8-sig") as stream:
        canonical = json.load(stream)
    die = canonical["die"]
    expected_bbox_um = [
        float(die["x_um"]),
        float(die["y_um"]),
        float(die["x_um"]) + float(die["width_um"]),
        float(die["y_um"]) + float(die["height_um"]),
    ]
bbox = top.bbox()
actual_bbox_um = [
    bbox.left * layout.dbu,
    bbox.bottom * layout.dbu,
    bbox.right * layout.dbu,
    bbox.top * layout.dbu,
]
tolerance_um = max(float(layout.dbu), 1e-9)
if any(
    not math.isclose(float(actual), float(wanted), rel_tol=0.0, abs_tol=tolerance_um)
    for actual, wanted in zip(actual_bbox_um, expected_bbox_um)
):
    raise RuntimeError(
        f"floorplan top bbox mismatch: actual_um={actual_bbox_um} "
        f"expected_um={expected_bbox_um} tolerance_um={tolerance_um}"
    )
print(
    f"KLAYOUT_FLOORPLAN_GDS PASS top={top.name} tsv={tsv} bumps={bumps} "
    f"bbox_um={actual_bbox_um}",
    flush=True,
)
