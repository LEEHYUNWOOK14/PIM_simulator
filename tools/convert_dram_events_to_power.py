#!/usr/bin/env python3
"""Convert interval event counts into the standard thermal power CSV."""
import argparse,csv,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser(); ap.add_argument("input"); ap.add_argument("output"); ap.add_argument("--energy",default="design/thermal/dram_event_energy.json"); a=ap.parse_args()
energy=json.loads((ROOT/a.energy).read_text(encoding="utf-8")); fields="time_ns duration_ns stack die physical_channel bank block power_mw source confidence".split()
with open(a.input,newline="",encoding="utf-8") as src, open(a.output,"w",newline="",encoding="utf-8") as dst:
 r=csv.DictReader(src); w=csv.DictWriter(dst,fieldnames=fields); w.writeheader()
 for n,row in enumerate(r,2):
  dur=float(row["duration_ns"])
  if dur<=0: raise ValueError(f"line {n}: duration must be positive")
  joules=sum(float(row.get(ev,0))*spec["value"]*1e-12 for ev,spec in energy["event_energy_pJ"].items()); power_mw=joules/(dur*1e-9)*1e3+energy["background_power_mW"]["value"]
  w.writerow({"time_ns":row["time_ns"],"duration_ns":row["duration_ns"],"stack":row["stack"],"die":row["die"],"physical_channel":row["physical_channel"],"bank":row["bank"],"block":row.get("block","bank_array"),"power_mw":power_mw,"source":"event_energy_adapter","confidence":"low"})
