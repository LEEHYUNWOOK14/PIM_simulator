import json
import os

import pya


ROOT = os.environ["STOB_REPO_ROOT"]
STATUS_PATH = os.path.join(ROOT, "output", "hbm2_3d_status.log")


def checkpoint(message):
    with open(STATUS_PATH, "a") as status:
        status.write(message + "\n")


with open(STATUS_PATH, "w") as status:
    status.write("HBM2 3D macro started\n")
with open(os.path.join(ROOT, "design", "hbm2_package.json"), "r") as stream:
    CFG = json.load(stream)
checkpoint("package configuration loaded")

ROUTING_STACK = (
    (235, 0, -100.0, 0.0, 0x44515C, 0x20272D, "Logic die silicon"),
    (67, 20, 0.10, 0.20, 0x55D6BE, 0x237F72, "Logic RTL / LI1"),
    (67, 44, 0.20, 0.35, 0xE6EDF3, 0x9AA6B2, "Logic RTL / MCON"),
    (68, 20, 0.35, 0.71, 0x58A6FF, 0x2067A5, "Logic RTL / MET1"),
    (68, 44, 0.71, 0.91, 0xF0F4F8, 0xB8C2CC, "Logic RTL / VIA1"),
    (69, 20, 0.91, 1.27, 0xFF7B72, 0xB6403A, "Logic RTL / MET2"),
    (69, 44, 1.27, 1.49, 0xF0F4F8, 0xB8C2CC, "Logic RTL / VIA2"),
    (70, 20, 1.49, 2.26, 0xD2A8FF, 0x7549A8, "Logic RTL / MET3"),
    (70, 44, 2.26, 2.52, 0xF0F4F8, 0xB8C2CC, "Logic RTL / VIA3"),
    (71, 20, 2.52, 3.42, 0xFFC857, 0xAD7620, "Logic RTL / MET4"),
    (71, 44, 3.42, 3.72, 0xF0F4F8, 0xB8C2CC, "Logic RTL / VIA4"),
    (72, 20, 3.72, 4.92, 0x7EE787, 0x388F46, "Logic RTL / MET5"),
)


def box_um(x1, y1, x2, y2, dbu):
    return pya.Box(
        int(round(x1 / dbu)),
        int(round(y1 / dbu)),
        int(round(x2 / dbu)),
        int(round(y2 / dbu)),
    )


def rectangle_region(cx, cy, width, height, dbu):
    return pya.Region(
        box_um(cx - width / 2, cy - height / 2,
               cx + width / 2, cy + height / 2, dbu)
    )


def grid_region(cx, cy, width, height, columns, rows, size, dbu):
    region = pya.Region()
    x_pitch = width / max(columns - 1, 1)
    y_pitch = height / max(rows - 1, 1)
    for column in range(columns):
        x = cx - width / 2 + column * x_pitch
        for row in range(rows):
            y = cy - height / 2 + row * y_pitch
            region.insert(box_um(x - size / 2, y - size / 2,
                                 x + size / 2, y + size / 2, dbu))
    return region


def add_material(d25, region, dbu, zstart, zstop, frame, fill, name, number):
    if region.is_empty():
        return
    d25.open_display(frame, fill, pya.LayerInfo(number, 0, name), name)
    d25.entry(region, dbu, zstart, zstop)
    d25.close_display()


view = pya.LayoutView.current()
if view is None or view.active_cellview() is None:
    raise RuntimeError("Open output.gds before running the HBM2 package macro")

cell_view = view.active_cellview()
layout = cell_view.layout()
cell = cell_view.cell
dbu = layout.dbu
if cell is None:
    raise RuntimeError("The active layout has no selected top cell")
checkpoint("active GDS layout acquired")

gds_bbox = cell.dbbox()
gds_cx = (gds_bbox.left + gds_bbox.right) / 2
gds_cy = (gds_bbox.bottom + gds_bbox.top) / 2
target_cx = gds_cx + CFG["logic_block_x_um"]
target_cy = gds_cy + CFG["logic_block_y_um"]
dx = int(round((target_cx - gds_cx) / dbu))
dy = int(round((target_cy - gds_cy) / dbu))
move = pya.Trans(dx, dy)

d25 = view.open_d25_view()
if d25 is None:
    raise RuntimeError("KLayout 2.5D view requires GUI mode with OpenGL support")
d25.begin("STOB HBM2 package and routed logic die")
checkpoint("2.5D view opened")

package_w = CFG["package_width_um"]
package_h = CFG["package_height_um"]
logic_w = CFG["logic_die_width_um"]
logic_h = CFG["logic_die_height_um"]
dram_w = CFG["dram_die_width_um"]
dram_h = CFG["dram_die_height_um"]

add_material(d25, rectangle_region(gds_cx, gds_cy, package_w, package_h, dbu), dbu,
             -280, -180, 0x4B5563, 0x26313A, "Package substrate / interposer", 900)
add_material(d25, rectangle_region(gds_cx, gds_cy, logic_w, logic_h, dbu), dbu,
             -100, 0, 0x8CA0AD, 0x35444E, "HBM2 base logic die", 901)
checkpoint("package substrate and base die added")

for layer, datatype, zstart, zstop, frame, fill, name in ROUTING_STACK[1:]:
    layer_index = layout.find_layer(layer, datatype)
    if layer_index is None:
        continue
    region = pya.Region(cell.begin_shapes_rec(layer_index))
    region.transform(move)
    add_material(d25, region, dbu, zstart, zstop, frame, fill, name, 910 + layer)
checkpoint("routed logic layers added")

bump_region = grid_region(gds_cx, gds_cy, dram_w * 0.92, dram_h * 0.92,
                          CFG["microbump_columns"], CFG["microbump_rows"],
                          CFG["microbump_size_um"], dbu)
add_material(d25, bump_region, dbu, 5, 20, 0xF5D76E, 0xB88912,
             "Representative microbump array", 920)
checkpoint("microbump array added")

dram_bottom = 24.0
die_pitch = CFG["dram_die_thickness_um"] + CFG["die_gap_um"]
channel_gap = 24.0
channel_width = (dram_w - channel_gap * (CFG["channel_count"] - 1)) / CFG["channel_count"]
dram_colors = (0x377DFF, 0x31B46C, 0xE05A47, 0x9A66D4,
               0x00A6A6, 0xD79B22, 0xD94F91, 0x708090)

for die in range(CFG["dram_die_count"]):
    die_region = pya.Region()
    for channel in range(CFG["channel_count"]):
        left = gds_cx - dram_w / 2 + channel * (channel_width + channel_gap)
        die_region.insert(box_um(left, gds_cy - dram_h / 2,
                                 left + channel_width, gds_cy + dram_h / 2, dbu))
    zstart = dram_bottom + die * die_pitch
    color = dram_colors[die % len(dram_colors)]
    add_material(d25, die_region, dbu, zstart,
                 zstart + CFG["dram_die_thickness_um"], 0xDDE7F0, color,
                 "HBM2 DRAM die {} / 8 channels".format(die), 930 + die)
checkpoint("DRAM stack added")

tsv_region = pya.Region()
side_offset = dram_w * 0.40
row_span = dram_h * 0.84
for side in (-1, 1):
    side_grid = grid_region(gds_cx + side * side_offset, gds_cy,
                            dram_w * 0.05, row_span,
                            CFG["tsv_columns_per_side"], CFG["tsv_rows"],
                            CFG["tsv_size_um"], dbu)
    tsv_region += side_grid
stack_top = dram_bottom + (CFG["dram_die_count"] - 1) * die_pitch + CFG["dram_die_thickness_um"]
add_material(d25, tsv_region, dbu, 20, stack_top, 0xFFF2B2, 0xC98B18,
             "Representative TSV columns", 940)
checkpoint("TSV columns added")

ring_outer = rectangle_region(gds_cx, gds_cy, package_w * 1.02, package_h * 1.02, dbu)
ring_inner = rectangle_region(gds_cx, gds_cy, dram_w * 1.02, dram_h * 1.02, dbu)
add_material(d25, ring_outer - ring_inner, dbu, stack_top + 15, stack_top + 65,
             0xD9E1E8, 0x68747E, "Thermal lid perimeter", 950)

d25.finish()
checkpoint("HBM2 3D view finished")
print("STOB HBM2 package view ready: {} DRAM dies".format(CFG["dram_die_count"]),
      flush=True)
