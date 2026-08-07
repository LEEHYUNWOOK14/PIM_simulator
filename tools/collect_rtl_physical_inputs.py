#!/usr/bin/env python3
"""Merge synthesis, placement, and VCD/SAIF-derived block-power reports."""
from __future__ import annotations
import argparse, csv, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def resolve(base: Path, value: str) -> Path:
    p=Path(value)
    return p if p.is_absolute() else (base/p).resolve()

def rows(path: Path) -> list[dict]:
    with path.open(newline="",encoding="utf-8") as f: return list(csv.DictReader(f))

def indexed(path: Path) -> dict[str,dict]:
    result={}
    for line,row in enumerate(rows(path),2):
        name=row.get("instance","").strip()
        if not name: raise ValueError(f"{path}:{line}: missing instance")
        if name in result: raise ValueError(f"{path}:{line}: duplicate instance {name}")
        result[name]=row
    return result

def collect(manifest_path: str, output_path: str) -> dict:
    mp=Path(manifest_path)
    if not mp.is_absolute(): mp=ROOT/mp
    manifest=json.loads(mp.read_text(encoding="utf-8")); base=mp.parent
    required=("synthesis_csv","placement_csv","block_power_csv","activity_source")
    missing=[x for x in required if not manifest.get(x)]
    if missing: raise ValueError("manifest missing: "+", ".join(missing))
    area_path=resolve(base,manifest["synthesis_csv"]); place_path=resolve(base,manifest["placement_csv"])
    power_path=resolve(base,manifest["block_power_csv"]); activity_path=resolve(base,manifest["activity_source"])
    area=indexed(area_path); placement=indexed(place_path); power=indexed(power_path)
    if set(area)!=set(power):
        raise ValueError(f"synthesis/power instance mismatch: synthesis_only={sorted(set(area)-set(power))}, power_only={sorted(set(power)-set(area))}")
    blocks=[]
    for name,a in area.items():
        p=power[name]; block={"instance":name,"module":a["module"],"area_um2":float(a["area_um2"]),
            "power":{"dynamic_W":float(p["dynamic_W"]),"leakage_W":float(p["leakage_W"])},
            "activity":{"format":p.get("activity_format") or manifest.get("activity_format","normalized"),
                        "toggle_count":float(p.get("toggle_count") or 0),"duration_s":float(p.get("duration_s") or manifest.get("duration_s",1))}}
        if name in placement:
            q=placement[name]; block["placement"]={k:float(q[k]) for k in ("x_um","y_um","width_um","height_um")}
        for key in ("stack","die","channel","bank"):
            value=p.get(key,"")
            if value not in (None,""): block.setdefault("target_hint",{})[key]=int(value)
        blocks.append(block)
    extra_placements=sorted(set(placement)-set(area))
    doc={"schema_version":1,"description":"Normalized RTL physical input assembled from replaceable reports.",
         "units":{"length":"um","area":"um^2","power":"W"},
         "sources":{"synthesis":str(area_path),"placement":str(place_path),"activity":str(activity_path),"power":str(power_path)},
         "collection_warnings":([{"type":"placement_without_synthesis","instances":extra_placements}] if extra_placements else []),"blocks":blocks}
    out=Path(output_path)
    if not out.is_absolute(): out=ROOT/out
    out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(doc,indent=2),encoding="utf-8")
    print(f"Collected {len(blocks)} blocks into {out}")
    return doc

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument("--manifest",required=True); ap.add_argument("--output",default="output/rtl_to_3d/normalized_input.json"); a=ap.parse_args()
    try: collect(a.manifest,a.output)
    except (ValueError,KeyError,OSError,json.JSONDecodeError) as exc: print(f"ERROR: {exc}"); return 2
    return 0
if __name__=="__main__": raise SystemExit(main())
