import json
import os

import openroad


ROOT = "/mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2"
REPORT_ROOT = os.path.join(ROOT, "reports/groot_normalization/physical_feasibility")
SOURCE_DB = os.path.join(
    REPORT_ROOT, "logic_die_normalization_hbm_top_v5_bank_gp.odb"
)
VIOLATION_REPORT = os.path.join(
    REPORT_ROOT, "logic_die_normalization_hbm_top_v5_placement_violations.rpt"
)
OUTPUT_DB = os.path.join(
    REPORT_ROOT, "logic_die_normalization_hbm_top_v5_bank_gp_reclassified.odb"
)


tech = openroad.Tech()
tech.readLiberty(
    "/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/"
    "sky130_fd_sc_hd__tt_025C_1v80.lib"
)
design = openroad.Design(tech)
design.readDb(SOURCE_DB)
block = design.getBlock()

with open(VIOLATION_REPORT, encoding="utf-8") as stream:
    violations = json.load(stream)["DPL"]["category"]["Placement_failures"][
        "violations"
    ]

regions = []
for bank in range(16):
    group = block.findGroup(f"pcu_bank_group_{bank}")
    if group is None:
        raise RuntimeError(f"missing bank group {bank}")
    region = group.getRegion()
    boundaries = list(region.getBoundaries())
    if len(boundaries) != 1:
        raise RuntimeError(f"bank {bank} does not have one rectangular boundary")
    regions.append((bank, group, boundaries[0]))

assigned = [0] * 16
already_grouped = 0
missing = []
outside = []
for violation in violations:
    name = violation["sources"][0]["name"]
    inst = block.findInst(name)
    if inst is None:
        missing.append(name)
        continue
    if inst.getGroup() is not None:
        already_grouped += 1
        continue

    bbox = inst.getBBox()
    center_x = (bbox.xMin() + bbox.xMax()) // 2
    center_y = (bbox.yMin() + bbox.yMax()) // 2
    destination = None
    for bank, group, boundary in regions:
        if (
            boundary.xMin() <= center_x < boundary.xMax()
            and boundary.yMin() <= center_y < boundary.yMax()
        ):
            destination = (bank, group)
            break
    if destination is None:
        outside.append(name)
        continue
    bank, group = destination
    group.addInst(inst)
    assigned[bank] += 1

print(f"V5_RECLASSIFY_INPUT_VIOLATIONS {len(violations)}")
print(f"V5_RECLASSIFY_ASSIGNED {sum(assigned)}")
print(f"V5_RECLASSIFY_ALREADY_GROUPED {already_grouped}")
print(f"V5_RECLASSIFY_MISSING {len(missing)}")
print(f"V5_RECLASSIFY_OUTSIDE {len(outside)}")
for bank, count in enumerate(assigned):
    print(f"V5_RECLASSIFY_BANK {bank} ADDED {count}")

if missing or outside or already_grouped or sum(assigned) != len(violations):
    raise RuntimeError(
        "stranded-cell reclassification was not exact: "
        f"assigned={sum(assigned)} already={already_grouped} "
        f"missing={len(missing)} outside={len(outside)}"
    )

design.writeDb(OUTPUT_DB)
print(f"V5_RECLASSIFY_DB {OUTPUT_DB}")
print("V5_RECLASSIFY_PASS")
