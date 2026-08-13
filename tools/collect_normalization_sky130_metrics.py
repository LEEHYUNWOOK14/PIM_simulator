#!/usr/bin/env python3
"""Collect Sky130HD mapped area and OpenROAD STA metrics."""
from __future__ import annotations
import csv,re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
RESULTS=ROOT/"reports"/"groot_normalization"/"results"/"sky130_mapping"
OUTPUT=ROOT/"reports"/"groot_normalization"/"results"/"normalization_sky130_metrics.csv"

def last(pattern:str,text:str,label:str)->float:
    values=re.findall(pattern,text,re.I|re.M)
    if not values:raise RuntimeError(f"missing {label}")
    return float(values[-1])

def main()->None:
    rows=[]
    top="bank_normalization_pipelined_vector_reducer"
    for dtype in ("fp16","bf16"):
      for lanes in (2,4):
        stem=f"{top}_{dtype}_l{lanes}"
        ylog=(RESULTS/f"{stem}_yosys.log").read_text(encoding="utf-8",errors="replace")
        slog=(RESULTS/f"{stem}_sta.log").read_text(encoding="utf-8",errors="replace")
        if "Found and reported 0 problems." not in ylog:raise RuntimeError(f"Yosys check failed: {stem}")
        area=last(r"Chip area for module ['\\]*[^:]+:\s*([0-9.]+)",ylog,"area")
        slack=last(r"worst slack\s+(-?[0-9.]+)",slog,"worst slack")
        # OpenROAD full-clock reports the path arrival as data arrival time.
        arrivals=[float(value) for value in re.findall(
          r"^\s*(-?[0-9.]+)\s+data arrival time",slog,re.I|re.M)]
        if not arrivals:raise RuntimeError(f"missing arrival: {stem}")
        arrival=max(arrivals)
        rows.append({"data_format":dtype.upper(),"lanes":lanes,"clock_period_ns":10.0,
          "mapped_area_um2":area,"critical_path_ns":arrival,"worst_slack_ns":slack,
          "timing_met":slack>=0,"corner":"sky130hd_tt_025C_1v80",
          "evidence":"YOSYS_ABC_OPENROAD_PRELAYOUT_STA"})
    with OUTPUT.open("w",newline="",encoding="utf-8")as stream:
      writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(f"NORMALIZATION_SKY130_METRICS PASS rows={len(rows)} output={OUTPUT}")
if __name__=="__main__":main()
