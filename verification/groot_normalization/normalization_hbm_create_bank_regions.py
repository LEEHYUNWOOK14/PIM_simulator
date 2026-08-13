import os
import re

import odb
import openroad


ROOT = "/mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2"
REPORT_ROOT = os.path.join(ROOT, "reports/groot_normalization/physical_feasibility")
SOURCE_DB = os.path.join(REPORT_ROOT, "logic_die_normalization_hbm_top_v2_repaired_legal.odb")
OUTPUT_DB = os.path.join(REPORT_ROOT, "logic_die_normalization_hbm_top_v5_bank_regions.odb")

tech = openroad.Tech()
tech.readLiberty("/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib")
design = openroad.Design(tech)
design.readDb(SOURCE_DB)
block = design.getBlock()

# The legal core is approximately (7, 7)-(9022.9, 9022.9) um.  Keep a
# 20-um guard band and arrange 2.0-mm bank islands on a 4x4 grid.  The
# approximately 0.25-mm corridors between islands remain available to the
# adapter, global reducer/scalar, and inter-bank buses.  They are placement
# groups, not macros: cells remain freely legalizable inside each island.
dbu = block.getDbUnitsPerMicron()
core_lo_um = 20.0
core_hi_um = 9010.0
pitch_um = (core_hi_um - core_lo_um) / 4.0
island_um = 2000.0
inset_um = (pitch_um - island_um) / 2.0

groups = []
counts = [0] * 16
for bank in range(16):
    column = bank % 4
    row = bank // 4
    x0 = round((core_lo_um + column * pitch_um + inset_um) * dbu)
    y0 = round((core_lo_um + row * pitch_um + inset_um) * dbu)
    x1 = round((core_lo_um + column * pitch_um + inset_um + island_um) * dbu)
    y1 = round((core_lo_um + row * pitch_um + inset_um + island_um) * dbu)
    region = odb.dbRegion_create(block, f"pcu_bank_region_{bank}")
    odb.dbBox_create(region, x0, y0, x1, y1)
    region.setRegionType("SUGGESTED")
    group = odb.dbGroup_create(region, f"pcu_bank_group_{bank}")
    group.setType("PHYSICAL_CLUSTER")
    groups.append(group)

bank_pattern = re.compile(r"g_bank\[([0-9]+)\]")
total_cells = 0
for inst in block.getInsts():
    total_cells += 1
    match = bank_pattern.search(inst.getName().replace("\\", ""))
    if match is None:
        continue
    bank = int(match.group(1))
    if 0 <= bank < 16:
        groups[bank].addInst(inst)
        counts[bank] += 1

print(f"V5_TOTAL_CELLS {total_cells}")
print(f"V5_GROUPED_CELLS {sum(counts)}")
for bank, count in enumerate(counts):
    column = bank % 4
    row = bank // 4
    x0 = core_lo_um + column * pitch_um + inset_um
    y0 = core_lo_um + row * pitch_um + inset_um
    x1 = x0 + island_um
    y1 = y0 + island_um
    print(
        f"V5_BANK {bank} CELLS {count} "
        f"GUIDE_UM {x0:.1f} {y0:.1f} {x1:.1f} {y1:.1f}"
    )

if min(counts) == 0:
    raise RuntimeError("at least one PCU bank has no grouped standard cells")

design.writeDb(OUTPUT_DB)
print(f"V5_REGION_DB {OUTPUT_DB}")
