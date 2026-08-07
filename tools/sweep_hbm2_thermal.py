#!/usr/bin/env python3
"""Small deterministic uncertainty/sensitivity sweep."""
import csv, json, sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
import run_hbm2_thermal as th
ROOT=Path(__file__).resolve().parents[1]

def solve(overrides):
    cfg=th.load_json("design/thermal/hbm2_thermal_config.json"); arch=th.load_json(cfg["stack_config"]); mats=th.load_json(cfg["materials"]); bc=th.load_json(cfg["boundaries"])
    for key,val in overrides.items():
      if key=="tim_k": mats["materials"]["tim"]["kx_W_mK"]["value"]=mats["materials"]["tim"]["kz_W_mK"]["value"]=val
      elif key=="silicon_k":
        for q in ("kx_W_mK","ky_W_mK","kz_W_mK"): mats["materials"]["silicon"][q]["value"]=val
      elif key=="top_h": bc["top"]["h_W_m2K"]["value"]=val
      elif key=="die_um": cfg["geometry_um"]["dram_die_thickness"]["value"]=val
      elif key=="tim_um": cfg["geometry_um"]["tim_thickness"]["value"]=val
    layers=th.build_layers(cfg,arch); nx=16; ny=8; w=8e-3; h=12e-3; p,_=th.power_map("uniform",layers,nx,ny,1); p*=overrides.get("power_scale",1)
    K,b,_=th.assemble(layers,mats,nx,ny,w,h,bc,overrides.get("tsv_fill",.02)); T=th.spsolve(K,p.ravel()+b)
    return float(T.max())

def main():
    cases=[("nominal",{}),("best",{"tim_k":8,"top_h":15000,"silicon_k":150,"tsv_fill":.08,"die_um":25,"tim_um":20,"power_scale":.8}),("worst",{"tim_k":1,"top_h":1000,"silicon_k":100,"tsv_fill":.005,"die_um":50,"tim_um":100,"power_scale":1.2})]
    sweeps={"tim_k":[1,4,8],"top_h":[1000,5000,15000],"silicon_k":[100,130,150],"tsv_fill":[.005,.02,.08],"die_um":[25,32,50],"tim_um":[20,50,100],"power_scale":[.8,1,1.2]}
    rows=[]
    for name,o in cases: rows.append({"parameter":"combined","setting":name,"value":"","peak_K":solve(o)})
    nominal=solve({})
    for parameter,values in sweeps.items():
      for v in values: rows.append({"parameter":parameter,"setting":"sweep","value":v,"peak_K":solve({parameter:v})})
    out=ROOT/"output/hbm2_thermal/sensitivity"; out.mkdir(parents=True,exist_ok=True)
    with open(out/"sweep_results.csv","w",newline="",encoding="utf-8") as f: w=csv.DictWriter(f,fieldnames=rows[0]); w.writeheader(); w.writerows(rows)
    report={"status":"PASS","nominal_peak_K":nominal,"best_peak_K":rows[1]["peak_K"],"worst_peak_K":rows[2]["peak_K"],"note":"Ranges are epistemic architectural uncertainty, not statistical confidence bounds."}
    (out/"sensitivity_report.json").write_text(json.dumps(report,indent=2),encoding="utf-8"); print(json.dumps(report,indent=2))
if __name__=="__main__": main()
