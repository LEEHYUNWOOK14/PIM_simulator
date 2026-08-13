"""Render the merged wbq research GDS with a deterministic bbox-derived camera."""

import os
import pya

gds = os.environ["STOB_FINAL_GDS"]
lyp = os.environ["STOB_FINAL_LYP"]
png = os.environ["STOB_FINAL_PNG"]
top_name = os.environ.get("STOB_FINAL_TOP", "STOB_FINAL_PHYSICAL_MERGED_NOT_SIGNOFF")

view = pya.LayoutView()
cellview_index = view.load_layout(gds)
cellview = view.cellview(cellview_index)
layout = cellview.layout()
top = layout.cell(top_name)
if top is None:
    raise RuntimeError("missing final merged top cell " + top_name)
bbox = top.dbbox()
if bbox.empty():
    raise RuntimeError("final merged top bbox is empty")
margin = max(bbox.width(), bbox.height()) * 0.02
camera = pya.DBox(
    bbox.left - margin,
    bbox.bottom - margin,
    bbox.right + margin,
    bbox.top + margin,
)
view.select_cell(top.cell_index(), cellview_index)
view.load_layer_props(lyp)
view.add_missing_layers()
view.max_hier()
view.zoom_box(camera)
view.save_image(png, 2400, 2400)
if not os.path.isfile(png) or os.path.getsize(png) == 0:
    raise RuntimeError("final merged fixed-camera image is missing or empty")
print(
    "KLAYOUT_WBQ_FINAL_RENDER PASS "
    + png
    + " bbox_um="
    + str([bbox.left, bbox.bottom, bbox.right, bbox.top]),
    flush=True,
)
