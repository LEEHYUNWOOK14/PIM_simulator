#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parent
lines = (root / "logs" / "b1_block_power.log").read_text(encoding="utf-8", errors="replace").splitlines()
section = None
sums = {"logic_die": [0.0] * 4, "bank_hierarchy": [0.0] * 4}
counts = {"logic_die": 0, "bank_hierarchy": 0}
for line in lines:
    if line.startswith("LOGIC_DIE_LEAF_CELLS="):
        section = "logic_die"
        counts[section] = int(line.split("=")[1])
        continue
    if line.startswith("BANK_HIERARCHY_LEAF_CELLS="):
        section = "bank_hierarchy"
        counts[section] = int(line.split("=")[1])
        continue
    fields = line.split()
    if section and len(fields) == 5:
        try:
            nums = [float(x) for x in fields[:4]]
        except ValueError:
            continue
        sums[section] = [a + b for a, b in zip(sums[section], nums)]
out = {key: {"leaf_cells": counts[key], "internal_w": vals[0], "switching_w": vals[1],
             "leakage_w": vals[2], "total_w": vals[3]} for key, vals in sums.items()}
(root / "metrics" / "b1_block_power.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
print(json.dumps(out, indent=2))
