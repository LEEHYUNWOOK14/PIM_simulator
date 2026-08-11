from __future__ import annotations

from pathlib import Path
import shutil
import tempfile

import gdstk


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "output.gds"

LIB = gdstk.Library(unit=1e-6, precision=1e-9)
CELLS: dict[str, gdstk.Cell] = {}

L_BANK = 1
L_LOGIC = 2
L_PIPE = 3
L_FP16 = 4
L_VIA = 5
L_PWR = 6
L_MISC = 7
L_TEXT = 10


def rect(cell, x0, y0, x1, y1, layer, datatype=0):
    cell.add(gdstk.rectangle((x0, y0), (x1, y1), layer=layer, datatype=datatype))


def path(cell, points, width, layer, datatype=0):
    cell.add(gdstk.FlexPath(points, width, layer=layer, datatype=datatype))


def make_bitcell():
    cell = LIB.new_cell("FP16_LANE_CELL")
    CELLS[cell.name] = cell
    rect(cell, -0.22, -0.12, 0.22, 0.12, L_BANK)
    rect(cell, -0.08, -0.08, 0.08, 0.08, L_FP16)
    path(cell, [(-0.18, -0.18), (0.18, 0.18)], 0.025, L_PIPE)
    path(cell, [(-0.18, 0.18), (0.18, -0.18)], 0.025, L_PIPE)
    rect(cell, -0.03, -0.24, 0.03, 0.24, L_VIA)
    for i in range(4):
        off = -0.16 + i * 0.11
        path(cell, [(-0.21, off), (0.21, off + 0.03)], 0.012, L_MISC)
        path(cell, [(-0.21, -off), (0.21, -off - 0.03)], 0.012, L_MISC)
    return cell


def make_microtile():
    cell = LIB.new_cell("REDUCTION_LANE_TILE")
    CELLS[cell.name] = cell
    bit = CELLS["FP16_LANE_CELL"]
    for r in range(8):
        for c in range(8):
            x = (c - 3.5) * 0.75
            y = (r - 3.5) * 0.75
            cell.add(gdstk.Reference(bit, origin=(x, y)))
    for i in range(17):
        y = -3.05 + i * 0.38
        path(cell, [(-3.35, y), (3.35, y)], 0.025 if i % 2 == 0 else 0.014, L_LOGIC)
    for i in range(17):
        x = -3.35 + i * 0.42
        path(cell, [(x, -3.35), (x, 3.35)], 0.014, L_FP16)
    for i in range(8):
        offset = -2.65 + i * 0.72
        path(cell, [(-3.15, offset), (3.15, offset + 0.35)], 0.012, L_PWR)
        path(cell, [(-3.15, -offset), (3.15, -offset - 0.35)], 0.012, L_PWR)
    for i in range(8):
        x = -3.1 + i * 0.88
        path(cell, [(x, -3.1), (x + 0.18, 3.1)], 0.01, L_MISC)
        path(cell, [(x, 3.1), (x + 0.18, -3.1)], 0.01, L_MISC)
    return cell


def make_block():
    cell = LIB.new_cell("BANK_LOCAL_REDUCTION_BUFFER")
    CELLS[cell.name] = cell
    tile = CELLS["REDUCTION_LANE_TILE"]
    rect(cell, -7.2, -4.7, 7.2, 4.7, L_BANK)
    rect(cell, -6.8, -4.3, 6.8, 4.3, L_LOGIC)
    for r in range(4):
        for c in range(4):
            x = -4.8 + c * 3.2
            y = -1.85 + r * 3.7
            cell.add(gdstk.Reference(tile, origin=(x, y)))
    path(cell, [(-6.8, 0), (6.8, 0)], 0.14, L_PIPE)
    path(cell, [(0, -4.3), (0, 4.3)], 0.14, L_PIPE)
    path(cell, [(-6.2, -3.6), (6.2, 3.6)], 0.07, L_PWR)
    path(cell, [(-6.2, 3.6), (6.2, -3.6)], 0.07, L_PWR)
    path(cell, [(-6.6, -2.1), (6.6, -2.1)], 0.05, L_MISC)
    path(cell, [(-6.6, 2.1), (6.6, 2.1)], 0.05, L_MISC)
    for i in range(10):
        y = -4.1 + i * 0.9
        path(cell, [(-7.0, y), (7.0, y + 0.16)], 0.02, L_FP16)
        path(cell, [(-7.0, -y), (7.0, -y - 0.16)], 0.02, L_FP16)
    rect(cell, -0.8, -0.4, 0.8, 0.4, L_FP16)
    rect(cell, -5.9, -3.9, -4.9, -3.1, L_FP16)
    rect(cell, 4.9, 3.1, 5.9, 3.9, L_FP16)
    return cell


def make_channel(index: int):
    cell = LIB.new_cell(f"CHANNEL_{index:02d}")
    CELLS[cell.name] = cell
    block = CELLS["BANK_LOCAL_REDUCTION_BUFFER"]
    x0 = -38.0
    y0 = -20.0
    rect(cell, -40.0, -22.0, 40.0, 22.0, L_LOGIC)
    path(cell, [(-39.0, -18.0), (39.0, -18.0)], 0.16, L_PIPE)
    path(cell, [(-39.0, 18.0), (39.0, 18.0)], 0.16, L_PIPE)
    path(cell, [(-39.0, 0), (39.0, 0)], 0.12, L_PWR)
    path(cell, [(-39.0, -8.5), (39.0, 8.5)], 0.06, L_MISC)
    path(cell, [(-39.0, 8.5), (39.0, -8.5)], 0.06, L_MISC)
    for r in range(4):
        for c in range(4):
            x = x0 + c * 19.0
            y = y0 + r * 18.0
            cell.add(gdstk.Reference(block, origin=(x + 9.5, y + 9.0)))
    for i in range(24):
        x = -36.0 + i * 6.5
        rect(cell, x, -21.0, x + 0.9, 21.0, L_VIA)
    for i in range(18):
        y = -19.0 + i * 2.25
        path(cell, [(-38.0, y), (38.0, y + 0.85)], 0.035, L_FP16)
    for i in range(18):
        x = -37.5 + i * 4.35
        path(cell, [(x, -20.5), (x + 1.1, 20.5)], 0.024, L_MISC)
        path(cell, [(x, 20.5), (x + 1.1, -20.5)], 0.024, L_MISC)
    return cell


def make_top():
    cell = LIB.new_cell("LOGIC_DIE_64CH_REDUCTION_TOP")
    CELLS[cell.name] = cell
    ch = [CELLS[f"CHANNEL_{i:02d}"] for i in range(64)]
    cols = 8
    rows = 8
    pitch_x = 92.0
    pitch_y = 54.0
    origin_x = -((cols - 1) * pitch_x) / 2
    origin_y = -((rows - 1) * pitch_y) / 2

    rect(cell, -430.0, -260.0, 430.0, 260.0, L_LOGIC)
    rect(cell, -405.0, -235.0, 405.0, 235.0, L_BANK)
    path(cell, [(-395.0, 0), (395.0, 0)], 0.9, L_PIPE)
    path(cell, [(0, -225.0), (0, 225.0)], 0.9, L_PIPE)
    path(cell, [(-395.0, -150.0), (395.0, 150.0)], 0.24, L_PWR)
    path(cell, [(-395.0, 150.0), (395.0, -150.0)], 0.24, L_PWR)
    path(cell, [(-395.0, -190.0), (395.0, -190.0)], 0.13, L_MISC)
    path(cell, [(-395.0, 190.0), (395.0, 190.0)], 0.13, L_MISC)
    path(cell, [(-390.0, -40.0), (390.0, -40.0)], 0.11, L_FP16)
    path(cell, [(-390.0, 40.0), (390.0, 40.0)], 0.11, L_FP16)

    for idx, ch_cell in enumerate(ch):
        c = idx % cols
        r = idx // cols
        ox = origin_x + c * pitch_x
        oy = origin_y + r * pitch_y
        cell.add(gdstk.Reference(ch_cell, origin=(ox, oy)))

    # Add some dense lane-like rails to make the layout visually rich.
    for i in range(128):
        y = -220.0 + i * 14.0
        width = 0.12 if i % 2 == 0 else 0.08
        path(cell, [(-410.0, y), (410.0, y)], width, L_FP16)
    for i in range(192):
        x = -400.0 + i * 17.0
        width = 0.08 if i % 3 else 0.14
        path(cell, [(x, -235.0), (x, 235.0)], width, L_FP16)
    for i in range(48):
        x = -380.0 + i * 33.0
        path(cell, [(x, -245.0), (x + 16.0, 245.0)], 0.045, L_VIA)
        path(cell, [(x, 245.0), (x + 16.0, -245.0)], 0.045, L_VIA)
    for i in range(36):
        rect(cell, -420.0 + i * 48.0, -255.0, -416.0 + i * 48.0, 255.0, L_PWR)
    for i in range(28):
        rect(cell, -430.0, -250.0 + i * 34.0, 430.0, -247.0 + i * 34.0, L_PWR)
    for i in range(20):
        y = -230.0 + i * 24.0
        path(cell, [(-420.0, y), (420.0, y + 8.0)], 0.02, L_MISC)
        path(cell, [(-420.0, -y), (420.0, -y - 8.0)], 0.02, L_MISC)

    # Labels.
    cell.add(gdstk.Label("logic_die_64ch_reduction_top", (0, 245.0), layer=L_TEXT))
    cell.add(gdstk.Label("shared_fp16_pipeline_fabric", (-295.0, 245.0), layer=L_TEXT))
    cell.add(gdstk.Label("bank_local_reduction_buffer", (245.0, 245.0), layer=L_TEXT))
    cell.add(gdstk.Label("channel_arbiter_fabric", (-120.0, -248.0), layer=L_TEXT))
    cell.add(gdstk.Label("synthetic_layout_from_simulator_structure", (190.0, -248.0), layer=L_TEXT))
    return cell


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    make_bitcell()
    make_microtile()
    make_block()
    for i in range(64):
        make_channel(i)
    top = make_top()
    temp_path = Path(tempfile.gettempdir()) / "stob_output.gds"
    if temp_path.exists():
        temp_path.unlink()
    LIB.write_gds(str(temp_path))
    shutil.copyfile(temp_path, OUT)
    print(f"WROTE {OUT}")


if __name__ == "__main__":
    main()
