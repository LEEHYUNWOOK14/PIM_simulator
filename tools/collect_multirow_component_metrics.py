#!/usr/bin/env python3
import csv,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];base=ROOT/"reports/groot_normalization/results/multirow_sky130";rows=[]
for kind in ("reducer","apply","scalar"):
  for value in (4,8,16):
    y=(base/f"{kind}_{value}_yosys.log").read_text(errors="replace");s=(base/f"{kind}_{value}_sta.log").read_text(errors="replace")
    area=float(re.findall(r"Chip area for module .*?:\s*([0-9.]+)",y)[-1]);arrival=max(float(x) for x in re.findall(r"^\s*([0-9.]+)\s+data arrival time$",s,re.M));slack=float(re.findall(r"worst slack\s+(-?[0-9.]+)",s)[-1])
    rows.append({"component":kind,"parameter":value,"area_um2":area,"arrival_ns":arrival,"fmax_mhz":1000/arrival,"slack_at_10ns":slack})
out=base/"component_metrics.csv";f=out.open("w",newline="");w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows);f.close();print(f"MULTIROW_METRICS PASS rows={len(rows)} output={out}")
