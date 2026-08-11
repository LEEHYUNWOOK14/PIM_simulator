import pya


# GDS layer/datatype, lower Z, upper Z, frame color, fill color, display name.
# Z values are visual approximations which preserve the SKY130 interconnect order.
STACK = (
    (235, 0, -2.00, 0.00, 0x44515C, 0x20272D, "Silicon / die boundary"),
    (67, 20, 0.10, 0.20, 0x55D6BE, 0x237F72, "LI1"),
    (67, 44, 0.20, 0.35, 0xE6EDF3, 0x9AA6B2, "MCON"),
    (68, 20, 0.35, 0.71, 0x58A6FF, 0x2067A5, "MET1"),
    (68, 44, 0.71, 0.91, 0xF0F4F8, 0xB8C2CC, "VIA1"),
    (69, 20, 0.91, 1.27, 0xFF7B72, 0xB6403A, "MET2"),
    (69, 44, 1.27, 1.49, 0xF0F4F8, 0xB8C2CC, "VIA2"),
    (70, 20, 1.49, 2.26, 0xD2A8FF, 0x7549A8, "MET3"),
    (70, 44, 2.26, 2.52, 0xF0F4F8, 0xB8C2CC, "VIA3"),
    (71, 20, 2.52, 3.42, 0xFFC857, 0xAD7620, "MET4"),
    (71, 44, 3.42, 3.72, 0xF0F4F8, 0xB8C2CC, "VIA4"),
    (72, 20, 3.72, 4.92, 0x7EE787, 0x388F46, "MET5"),
)


view = pya.LayoutView.current()
if view is None or view.active_cellview() is None:
    raise RuntimeError("Open output.gds before running the SKY130 2.5D macro")

cell_view = view.active_cellview()
layout = cell_view.layout()
cell = cell_view.cell
if cell is None:
    raise RuntimeError("The active layout has no selected top cell")

d25 = view.open_d25_view()
if d25 is None:
    raise RuntimeError("KLayout 2.5D view requires GUI mode with OpenGL support")
d25.begin("STOB SKY130HD visual stack")

displayed = 0
for layer, datatype, zstart, zstop, frame, fill, name in STACK:
    layer_index = layout.find_layer(layer, datatype)
    if layer_index is None:
        continue

    region = pya.Region(cell.begin_shapes_rec(layer_index))
    if region.is_empty():
        continue

    layer_info = pya.LayerInfo(layer, datatype, name)
    d25.open_display(frame, fill, layer_info, name)
    d25.entry(region, layout.dbu, zstart, zstop)
    d25.close_display()
    displayed += 1

d25.finish()
print("STOB 2.5D view ready: {} material layers".format(displayed), flush=True)
