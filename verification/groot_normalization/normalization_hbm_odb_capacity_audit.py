import os

import odb
import openroad


ROOT = "/mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2"
REPORT_ROOT = os.path.join(ROOT, "reports/groot_normalization/physical_feasibility")


def box_area_um2(box, dbu):
    return (box.xMax() - box.xMin()) * (box.yMax() - box.yMin()) / (dbu * dbu)


def audit(path):
    tech = openroad.Tech()
    tech.readLiberty(
        "/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/"
        "sky130_fd_sc_hd__tt_025C_1v80.lib"
    )
    design = openroad.Design(tech)
    design.readDb(path)
    block = design.getBlock()
    dbu = block.getDbUnitsPerMicron()

    row_area = sum(box_area_um2(row.getBBox(), dbu) for row in block.getRows())
    blockage_area = sum(
        box_area_um2(blockage.getBBox(), dbu) for blockage in block.getBlockages()
    )
    region_area = sum(
        box_area_um2(boundary, dbu)
        for region in block.getRegions()
        for boundary in region.getBoundaries()
    )
    print(f"ODB_CAPACITY_PATH {path}")
    print(f"ODB_CAPACITY_ROWS {len(block.getRows())} AREA_UM2 {row_area:.3f}")
    print(
        f"ODB_CAPACITY_BLOCKAGES {len(block.getBlockages())} "
        f"RECTANGLE_AREA_UM2 {blockage_area:.3f}"
    )
    print(
        f"ODB_CAPACITY_REGIONS {len(block.getRegions())} "
        f"RECTANGLE_AREA_UM2 {region_area:.3f}"
    )


audit(os.path.join(REPORT_ROOT, "logic_die_normalization_hbm_top_v5_bank_regions.odb"))
