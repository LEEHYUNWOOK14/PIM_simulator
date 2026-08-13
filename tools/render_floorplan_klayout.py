"""KLayout batch renderer for fixed-camera candidate comparison images."""
import os
import pya

gds = os.environ["STOB_FLOORPLAN_GDS"]
lyp = os.environ["STOB_FLOORPLAN_LYP"]
png = os.environ["STOB_FLOORPLAN_PNG"]
top_name = os.environ.get("STOB_FLOORPLAN_TOP", "STOB_LOGIC_DIE_FLOORPLAN_NOT_SIGNOFF")

view = pya.LayoutView()
cellview_index = view.load_layout(gds)
cellview = view.cellview(cellview_index)
layout = cellview.layout()
top = layout.cell(top_name)
if top is None:
    raise RuntimeError("missing top cell " + top_name)
view.select_cell(top.cell_index(), cellview_index)
view.load_layer_props(lyp)
view.add_missing_layers()
view.max_hier()
view.zoom_box(pya.DBox(0, 0, 8000, 12000))
view.save_image(png, 2400, 3600)
print("KLAYOUT_RENDER PASS " + png, flush=True)
