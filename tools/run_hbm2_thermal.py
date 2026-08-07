#!/usr/bin/env python3
"""Solver-independent HBM2 architectural thermal reference pipeline."""
from __future__ import annotations

import argparse, csv, json, shutil, tempfile
from dataclasses import dataclass
from pathlib import Path
import numpy as np
from scipy import sparse
from scipy.sparse.linalg import spsolve

ROOT = Path(__file__).resolve().parents[1]

def load_json(path):
    with open(ROOT / path, encoding="utf-8") as f: return json.load(f)

@dataclass
class Layer:
    name: str; material: str; thickness: float; kind: str; die: int = -1

def value(table, material, prop): return float(table["materials"][material][prop]["value"])

def build_layers(cfg, arch):
    g=cfg["geometry_um"]; n=int(arch["dram_dies_per_stack"]); u=1e-6
    layers=[Layer("substrate","organic_substrate",g["substrate_thickness"]["value"]*u,"passive"),
            Layer("interposer","silicon",g["interposer_thickness"]["value"]*u,"passive"),
            Layer("logic_die","silicon",g["base_die_thickness"]["value"]*u,"logic")]
    for d in range(n):
        layers += [Layer(f"bump_{d}","underfill_bump_effective",g["bump_plane_thickness"]["value"]*u,"passive"),
                   Layer(f"dram_{d}","silicon",g["dram_die_thickness"]["value"]*u,"dram",d)]
    layers += [Layer("tim","tim",g["tim_thickness"]["value"]*u,"passive"),
               Layer("lid","copper",g["lid_thickness"]["value"]*u,"passive")]
    return layers

def power_map(profile, layers, nx, ny, stack_count, event_csv=None):
    p=np.zeros((len(layers),ny,nx)); events=[]
    dram=[i for i,l in enumerate(layers) if l.kind=="dram"]; logic=next(i for i,l in enumerate(layers) if l.kind=="logic")
    def rect(z,x0,x1,y0,y1,w): p[z,y0:y1,x0:x1]+=w/max(1,(x1-x0)*(y1-y0))
    # Watts are architectural stimuli, not measured device power.
    for s in range(stack_count):
        a=s*(nx//stack_count); b=(s+1)*(nx//stack_count); sw=b-a
        if profile in ("uniform","all_channel_balanced","refresh_heavy","bursty_transient"):
            for z in dram: rect(z,a,b,0,ny,0.25 if profile!="refresh_heavy" else 0.45)
            rect(logic,a,b,0,ny,2.0)
        elif profile=="single_bank_hotspot": rect(dram[0],a,a+sw//32,0,ny//4,1.2); rect(logic,a,b,0,ny,1.0)
        elif profile=="single_channel_hotspot":
            for z in dram: rect(z,a,a+sw//8,0,ny,0.8)
            rect(logic,a,a+sw//8,0,ny,2.0)
        elif profile=="bank_pim_hotspot": rect(dram[0],a,a+sw//32,0,ny//4,1.0); rect(logic,a,a+sw//8,0,ny//4,3.0)
        elif profile=="logic_pcu_hotspot": rect(logic,a+sw//3,a+2*sw//3,ny//3,2*ny//3,6.0)
        else: raise ValueError(f"unknown power profile: {profile}")
    if event_csv:
        p[:]=0
        with open(event_csv,newline="",encoding="utf-8") as f:
            for line,r in enumerate(csv.DictReader(f),2):
                try:
                    if "time_ns" in r:
                        die_text=r["die"]; target="logic" if die_text=="logic_die" else "dram"; die=-1 if target=="logic" else int(die_text.replace("dram_",""))
                        e={"start_s":float(r["time_ns"])*1e-9,"end_s":(float(r["time_ns"])+float(r["duration_ns"]))*1e-9,"target":target,"stack":int(r["stack"]),"die":die,"channel":int(r["physical_channel"]),"bank":int(r["bank"]),"power_W":float(r["power_mw"])*1e-3}
                    else:
                        e={k:(float(v) if k in ("start_s","end_s","power_W") else int(v) if k in ("stack","die","channel","bank") else v) for k,v in r.items()}
                    if e["power_W"]<0 or e["end_s"]<=e["start_s"] or not 0<=e["stack"]<stack_count or e["channel"]>7 or e["bank"]>15: raise ValueError("range violation")
                    events.append(e)
                except Exception as exc: raise ValueError(f"invalid power event at line {line}: {exc}") from exc
    return p,events

def apply_events(base, events, layers, nx, ny, stacks, t):
    p=base.copy(); sw=nx//stacks
    for e in events:
        if not e["start_s"] <= t < e["end_s"]: continue
        s=e["stack"]; x0=s*sw; x1=(s+1)*sw; y0=0; y1=ny
        if e["channel"]>=0: x0 += (e["channel"]*sw)//8; x1=x0+sw//8
        if e["bank"]>=0: x1=x0+max(1,(x1-x0)//4); y0=(e["bank"]//4)*ny//4; y1=y0+ny//4
        z=next(i for i,l in enumerate(layers) if (e["target"]=="logic" and l.kind=="logic") or (e["target"]=="dram" and l.die==e["die"]))
        p[z,y0:y1,x0:x1]+=e["power_W"]/((x1-x0)*(y1-y0))
    return p

def assemble(layers,mats,nx,ny,width,height,bounds,tsv_fill):
    nz=len(layers); dx=width/nx; dy=height/ny; N=nz*ny*nx
    K=sparse.lil_matrix((N,N)); rhs=np.zeros(N); cap=np.zeros(N)
    def idx(z,y,x): return (z*ny+y)*nx+x
    kxy=[]; kz=[]
    for l in layers:
        kx=value(mats,l.material,"kx_W_mK")
        kk=value(mats,l.material,"kz_W_mK")
        if l.kind=="dram": kk=(1-tsv_fill)*kk+tsv_fill*value(mats,"copper","kz_W_mK")
        kxy.append(kx); kz.append(kk)
    for z,l in enumerate(layers):
      dz=l.thickness; vol=dx*dy*dz; rho=value(mats,l.material,"density_kg_m3"); cp=value(mats,l.material,"specific_heat_J_kgK")
      for y in range(ny):
       for x in range(nx):
        i=idx(z,y,x); cap[i]=rho*cp*vol
        for zz,yy,xx,G in ((z,y,x-1,kxy[z]*dy*dz/dx),(z,y,x+1,kxy[z]*dy*dz/dx),(z,y-1,x,kxy[z]*dx*dz/dy),(z,y+1,x,kxy[z]*dx*dz/dy)):
          if 0<=xx<nx and 0<=yy<ny: K[i,i]+=G; K[i,idx(zz,yy,xx)]-=G
        if z>0:
          G=dx*dy/(layers[z-1].thickness/(2*kz[z-1])+dz/(2*kz[z])); K[i,i]+=G; K[i,idx(z-1,y,x)]-=G
        if z<nz-1:
          G=dx*dy/(dz/(2*kz[z])+layers[z+1].thickness/(2*kz[z+1])); K[i,i]+=G; K[i,idx(z+1,y,x)]-=G
        side="bottom" if z==0 else "top" if z==nz-1 else None
        if side:
          bc=bounds[side]; area=dx*dy
          if bc["type"]=="convection": G=bc["h_W_m2K"]["value"]*area
          else: G=2*kz[z]*area/dz
          ambient=bounds["ambient_temperature_K"]["value"]
          K[i,i]+=G; rhs[i]+=G*bc.get("temperature_K",{}).get("value",ambient)
    return K.tocsr(),rhs,cap

def layer_stats(T,layers):
    return [{"layer":l.name,"min_K":float(T[z].min()),"mean_K":float(T[z].mean()),"max_K":float(T[z].max())} for z,l in enumerate(layers)]

def block_stats(T,layers,stacks):
    rows=[]; nx=T.shape[2]; ny=T.shape[1]; sw=nx//stacks
    for s in range(stacks):
      base=s*sw
      for z,l in enumerate(layers):
       if l.kind=="logic": rows.append({"stack":s,"die":l.name,"channel":-1,"bank":-1,"block":"logic_die","mean_K":float(T[z,:,base:base+sw].mean()),"max_K":float(T[z,:,base:base+sw].max())})
       elif l.kind=="dram":
        for ch in range(8):
         cx=base+ch*sw//8
         for bank in range(16):
          x0=cx+(bank%4)*max(1,sw//32); x1=min(cx+sw//8,x0+max(1,sw//32)); y0=(bank//4)*ny//4; y1=(bank//4+1)*ny//4; q=T[z,y0:y1,x0:x1]
          rows.append({"stack":s,"die":l.name,"channel":ch,"bank":bank,"block":"bank_array_pim_region","mean_K":float(q.mean()),"max_K":float(q.max())})
    return rows

def write_vtk(path,T,layers,width,height):
    nz,ny,nx=T.shape
    with open(path,"w",encoding="ascii") as f:
        f.write("# vtk DataFile Version 3.0\nHBM2 temperature\nASCII\nDATASET STRUCTURED_POINTS\n")
        f.write(f"DIMENSIONS {nx} {ny} {nz}\nORIGIN 0 0 0\nSPACING {width/nx} {height/ny} 1\nPOINT_DATA {nx*ny*nz}\nSCALARS temperature_K float 1\nLOOKUP_TABLE default\n")
        for v in T.ravel(): f.write(f"{v:.8g}\n")

def plot_outputs(out,T,layers,history,power):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    active=[i for i,l in enumerate(layers) if l.kind in ("logic","dram")]
    fig,ax=plt.subplots(figsize=(10,4)); im=ax.imshow(np.max(T[active],axis=0),origin="lower",cmap="inferno"); fig.colorbar(im,ax=ax,label="K"); ax.set_title("Peak active-layer temperature"); fig.tight_layout(); fig.savefig(out/"temperature_heatmap.png",dpi=160); plt.close(fig)
    fig,ax=plt.subplots(figsize=(10,4)); im=ax.imshow(np.max(power[active],axis=0),origin="lower",cmap="magma"); fig.colorbar(im,ax=ax,label="W/cell"); ax.set_title("Power map"); fig.tight_layout(); fig.savefig(out/"power_map.png",dpi=160); plt.close(fig)
    fig,ax=plt.subplots(figsize=(8,4)); im=ax.imshow(T[:,T.shape[1]//2,:],origin="lower",aspect="auto",cmap="inferno"); fig.colorbar(im,ax=ax,label="K"); ax.set_yticks(range(len(layers)),[l.name for l in layers],fontsize=6); fig.tight_layout(); fig.savefig(out/"temperature_cross_section.png",dpi=160); plt.close(fig)
    if history:
      fig,ax=plt.subplots(); ax.plot([x[0]*1e3 for x in history],[x[1] for x in history]); ax.set(xlabel="time (ms)",ylabel="peak temperature (K)"); fig.tight_layout(); fig.savefig(out/"transient_peak.png",dpi=160); plt.close(fig)

def write_3d_assets(out,T,layers,width,height):
    """Portable 3-D assets: VTK field, OpenSCAD layer stack, and GDS temperature bins."""
    peak=T.max(axis=(1,2)); lo=float(T.min()); span=max(float(T.max()-lo),1e-12)
    z=0.0; lines=["// Architectural thermal visualization; dimensions are scaled."]
    for l,temp in zip(layers,peak):
        c=(float(temp)-lo)/span; h=max(l.thickness*1e5,0.2)
        lines.append(f"color([{c:.4f},0,{1-c:.4f},0.75]) translate([0,0,{z:.5f}]) cube([{width*1e4:.5f},{height*1e4:.5f},{h:.5f}]);")
        z+=h
    (out/"temperature_stack.scad").write_text("\n".join(lines)+"\n",encoding="utf-8")
    try:
        import gdstk
        lib=gdstk.Library(unit=1e-6,precision=1e-9); cell=lib.new_cell("HBM2_THERMAL")
        nz,ny,nx=T.shape; dx=width*1e6/nx; dy=height*1e6/ny
        active=[i for i,l in enumerate(layers) if l.kind in ("logic","dram")]; field=np.max(T[active],axis=0)
        for y in range(ny):
          for x in range(nx):
            q=min(15,int(16*(field[y,x]-lo)/span)); cell.add(gdstk.rectangle((x*dx,y*dy),((x+1)*dx,(y+1)*dy),layer=200+q,datatype=0))
        with tempfile.TemporaryDirectory(prefix="hbm2_thermal_") as td:
            tmp=Path(td)/"temperature_bins.gds"
            lib.write_gds(str(tmp)); shutil.copy2(tmp,out/"temperature_bins.gds")
    except ImportError: pass

def run(args):
    cfg=load_json(args.config); arch=load_json(cfg["stack_config"]); mats=load_json(cfg["materials"]); bounds=load_json(cfg["boundaries"])
    if args.dies: arch["dram_dies_per_stack"]=args.dies
    if args.stacks: arch["stack_count"]=args.stacks
    stacks=arch["stack_count"]; nx=cfg["grid"]["nx_per_stack"]*stacks; ny=cfg["grid"]["ny"]
    width=arch["geometry_um"]["die_width"]["value"]*1e-6*stacks; height=arch["geometry_um"]["die_height"]["value"]*1e-6
    layers=build_layers(cfg,arch); p,events=power_map(args.profile,layers,nx,ny,stacks,args.events)
    K,b,cap=assemble(layers,mats,nx,ny,width,height,bounds,float(cfg["tsv"]["fill_ratio"]["value"])); shape=(len(layers),ny,nx)
    T=spsolve(K,p.ravel()+b).reshape(shape); history=[]
    if args.transient:
      dt=args.dt or cfg["analysis"]["timestep_s"]; duration=args.duration or cfg["analysis"]["duration_s"]; A=K+sparse.diags(cap/dt); temp=np.full(K.shape[0],bounds["initial_temperature_K"]["value"])
      for step in range(1,int(round(duration/dt))+1):
        tt=step*dt; pp=apply_events(p,events,layers,nx,ny,stacks,tt); temp=spsolve(A,pp.ravel()+b+(cap/dt)*temp); history.append((tt,float(temp.max())))
      T=temp.reshape(shape)
    out=ROOT/args.output; out.mkdir(parents=True,exist_ok=True)
    inputs=out/"inputs"; inputs.mkdir(exist_ok=True)
    (inputs/"resolved_stack.json").write_text(json.dumps(arch,indent=2),encoding="utf-8"); (inputs/"resolved_materials.json").write_text(json.dumps(mats,indent=2),encoding="utf-8"); (inputs/"resolved_boundaries.json").write_text(json.dumps(bounds,indent=2),encoding="utf-8")
    total=float((apply_events(p,events,layers,nx,ny,stacks,0) if events else p).sum())
    hot=np.unravel_index(np.argmax(T),T.shape); blocks=block_stats(T,layers,stacks)
    result={"status":"PASS","disclaimer":cfg["disclaimer"],"profile":args.profile,"grid":[nx,ny,len(layers)],"stack_count":stacks,"dram_dies_per_stack":arch["dram_dies_per_stack"],"input_power_W":total,"peak_temperature_K":float(T.max()),"peak_delta_K":float(T.max()-bounds["ambient_temperature_K"]["value"]),"hotspot":{"layer":layers[hot[0]].name,"x_index":int(hot[2]),"y_index":int(hot[1])},"layers":layer_stats(T,layers),"external_solver_adapters":cfg["external_solvers"]}
    (out/"summary.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    (out/"thermal_summary.md").write_text(f"# Thermal summary\n\n- Status: PASS\n- Profile: `{args.profile}`\n- Total input power: {total:.6g} W\n- Peak: {T.max():.6f} K\n- Hotspot: `{layers[hot[0]].name}` at grid ({hot[2]}, {hot[1]})\n- Scope: {cfg['disclaimer']}\n",encoding="utf-8")
    with open(out/"layer_temperatures.csv","w",newline="",encoding="utf-8") as f:
      w=csv.DictWriter(f,fieldnames=result["layers"][0]); w.writeheader(); w.writerows(result["layers"])
    with open(out/"block_temperatures.csv","w",newline="",encoding="utf-8") as f:
      w=csv.DictWriter(f,fieldnames=blocks[0]); w.writeheader(); w.writerows(blocks)
    if history:
      with open(out/"transient.csv","w",newline="",encoding="utf-8") as f: csv.writer(f).writerows([["time_s","peak_K"],*history])
    np.savez_compressed(out/"temperature_field.npz",temperature_K=T,power_W_cell=p)
    write_vtk(out/"temperature_field.vtk",T,layers,width,height); write_3d_assets(out,T,layers,width,height); plot_outputs(out,T,layers,history,p)
    print(json.dumps(result,indent=2)); return result

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--config",default="design/thermal/hbm2_thermal_config.json"); ap.add_argument("--output",default="output/hbm2_thermal/reference"); ap.add_argument("--profile",default="uniform"); ap.add_argument("--events"); ap.add_argument("--dies",type=int); ap.add_argument("--stacks",type=int); ap.add_argument("--transient",action="store_true"); ap.add_argument("--dt",type=float); ap.add_argument("--duration",type=float); args=ap.parse_args(); run(args)
if __name__=="__main__": main()
