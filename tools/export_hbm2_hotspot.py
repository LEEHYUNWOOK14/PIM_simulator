#!/usr/bin/env python3
"""Export a HotSpot-compatible 2-D floorplan/power pair for cross-checking."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; out=ROOT/"output/hbm2_thermal/solver/hotspot"; out.mkdir(parents=True,exist_ok=True)
flp=[]; ptr=[]
for ch in range(8):
  for bank in range(16):
    x=(ch*4+bank%4)*0.00025; y=(bank//4)*0.003
    flp.append(f"CH{ch}_B{bank}\t0.00025\t0.003\t{x:.6g}\t{y:.6g}"); ptr.append("0.001953125")
(out/"hbm2_banks.flp").write_text("\n".join(flp)+"\n",encoding="ascii")
(out/"uniform.ptrace").write_text("\t".join(f"CH{c}_B{b}" for c in range(8) for b in range(16))+"\n"+"\t".join(ptr)+"\n",encoding="ascii")
(out/"README.md").write_text("Pinned upstream: HotSpot f18831e48cef5d62580585cca0d7fab6c71bc3cc. This 2-D export is for qualitative cross-checking; the internal solver retains the full 3-D stack.\n",encoding="utf-8")
print(out)
