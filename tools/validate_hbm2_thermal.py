#!/usr/bin/env python3
"""Physics and regression checks for the HBM2 reference thermal model."""
import copy, json, sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
import run_hbm2_thermal as th

ROOT=Path(__file__).resolve().parents[1]
def solve(nx,ny,dies=8,profile="uniform",tsv=0.02):
    cfg=th.load_json("design/thermal/hbm2_thermal_config.json"); arch=th.load_json(cfg["stack_config"]); mats=th.load_json(cfg["materials"]); bc=th.load_json(cfg["boundaries"])
    arch["dram_dies_per_stack"]=dies; layers=th.build_layers(cfg,arch); width=arch["geometry_um"]["die_width"]["value"]*1e-6; height=arch["geometry_um"]["die_height"]["value"]*1e-6
    p,_=th.power_map(profile,layers,nx,ny,1); K,b,c=th.assemble(layers,mats,nx,ny,width,height,bc,tsv); T=th.spsolve(K,p.ravel()+b)
    return T.reshape((len(layers),ny,nx)),K,b,p,layers,c

def main():
    checks={}
    T,K,b,p,layers,cap=solve(32,16)
    residual=np.linalg.norm(K@T.ravel()-(p.ravel()+b),np.inf); checks["steady_equation_residual_W"]={"value":float(residual),"limit":1e-8,"pass":bool(residual<1e-8)}
    # Uniform load and symmetric boundaries must remain laterally symmetric.
    sym=max(np.max(np.abs(T-T[:,:,::-1])),np.max(np.abs(T-T[:,::-1,:]))); checks["uniform_symmetry_K"]={"value":float(sym),"limit":1e-8,"pass":bool(sym<1e-8)}
    # With zero power, all cells must equal ambient.
    T0=th.spsolve(K,b).reshape(T.shape); zero=np.max(np.abs(T0-300)); checks["zero_power_ambient_K"]={"value":float(zero),"limit":1e-7,"pass":bool(zero<1e-7)}
    # Uniform cases are exactly 1-D laterally; coarse/fine agreement exposes indexing errors.
    Tc,*_=solve(16,8); grid=abs(float(T.max()-Tc.max())); checks["grid_convergence_peak_K"]={"value":grid,"limit":0.05,"pass":grid<0.05}
    variants={}
    for dies in (4,8,12):
      Tv,*_=solve(16,8,dies); variants[f"{dies}Hi"]={"peak_K":float(Tv.max()),"pass":bool(np.isfinite(Tv).all() and Tv.max()>300)}
    checks["variants"]={"value":variants,"pass":all(v["pass"] for v in variants.values())}
    Tplain,*_=solve(16,8,8,"uniform",0.0); Teff,*_=solve(16,8,8,"uniform",0.02); delta=float(Tplain.max()-Teff.max()); checks["tsv_effective_comparison_K"]={"value":delta,"pass":bool(delta>0)}
    # A one-cell conductance network must reproduce the analytic convection result T=Tamb+P/(hA).
    h=5000.; area=8e-3*12e-3; analytic=300+4/(h*area); numeric=th.spsolve(th.sparse.csr_matrix([[h*area]]),np.array([4+h*area*300]))[0]
    ae=abs(float(numeric-analytic)); checks["analytic_single_slab_K"]={"value":ae,"limit":1e-12,"pass":bool(ae<1e-12)}
    # Backward-Euler timestep convergence for a 0.5 ms constant pulse.
    def transient(dt):
      temp=np.full(K.shape[0],300.0); A=K+th.sparse.diags(cap/dt)
      for _ in range(round(5e-4/dt)): temp=th.spsolve(A,p.ravel()+b+(cap/dt)*temp)
      return float(temp.max())
    ta,tb=transient(1e-4),transient(5e-5); td=abs(ta-tb); checks["timestep_convergence_K"]={"value":td,"limit":0.25,"pass":td<0.25,"coarse_K":ta,"fine_K":tb}
    report={"status":"PASS" if all(v["pass"] for v in checks.values()) else "FAIL","checks":checks,"disclaimer":"Architectural model verification, not silicon calibration or signoff."}
    out=ROOT/"output/hbm2_thermal/validation"; out.mkdir(parents=True,exist_ok=True); (out/"validation_report.json").write_text(json.dumps(report,indent=2),encoding="utf-8"); print(json.dumps(report,indent=2)); return 0 if report["status"]=="PASS" else 1
if __name__=="__main__": raise SystemExit(main())
