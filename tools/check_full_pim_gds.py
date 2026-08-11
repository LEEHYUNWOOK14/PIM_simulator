import os
import pya

gds_path = os.environ["STOB_FULL_PIM_GDS"]
layout = pya.Layout()
layout.read(gds_path)
top_names = sorted(cell.name for cell in layout.top_cells())
expected = "full_pim_system_top"
if expected not in top_names:
    raise RuntimeError(f"expected top {expected}, found {top_names}")
top = layout.cell(expected)
if top is None or top.bbox().empty():
    raise RuntimeError("Full-PIM top has an empty layout")
print(f"FULL_PIM_GDS PASS top={expected} cells={layout.cells()} bbox={top.bbox()}", flush=True)
