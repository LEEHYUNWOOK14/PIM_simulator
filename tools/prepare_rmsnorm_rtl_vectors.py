#!/usr/bin/env python3
"""Generate deterministic BF16 RMSNorm vectors for 128/2048-wide PCU tests."""
from __future__ import annotations
import csv, importlib.util, json, struct, sys
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"reports/groot_normalization/results/rmsnorm_l8_vectors"

def load_model():
    path=ROOT/"tools/explore_groot_mixed_precision.py"
    spec=importlib.util.spec_from_file_location("mixed_model",path)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module
    spec.loader.exec_module(module);return module

def fp32_bits(value): return struct.unpack(">I",struct.pack(">f",float(value)))[0]
def write_hex(path,values): path.write_text("\n".join(f"{int(v):04x}" for v in values)+"\n",encoding="ascii")
def add32(a,b): return np.asarray(a+b,dtype=np.float32)

def reduce_interleaved(x,lanes=8):
    rows,hidden=x.shape;vectors=hidden//(16*lanes)
    layout=x.reshape(rows,vectors,16,lanes)
    slots=np.zeros((rows,16,4),np.float32);sqslots=np.zeros_like(slots)
    for vector in range(vectors):
        level=layout[:,vector];sq=np.asarray(level*level,dtype=np.float32)
        while level.shape[-1]>1:
            level=add32(level[...,0::2],level[...,1::2]);sq=add32(sq[...,0::2],sq[...,1::2])
        slot=vector%4;slots[:,:,slot]=add32(slots[:,:,slot],level[...,0]);sqslots[:,:,slot]=add32(sqslots[:,:,slot],sq[...,0])
    total=add32(add32(slots[:,:,0],slots[:,:,1]),add32(slots[:,:,2],slots[:,:,3]))
    sumsq=add32(add32(sqslots[:,:,0],sqslots[:,:,1]),add32(sqslots[:,:,2],sqslots[:,:,3]))
    while total.shape[1]>1:
        total=add32(total[:,0::2],total[:,1::2]);sumsq=add32(sumsq[:,0::2],sumsq[:,1::2])
    return total[:,0],sumsq[:,0]

def nr2_rsqrt(model,argument):
    inverse=model.lut256(argument)
    for _ in range(2):
        yy=np.asarray(inverse*inverse,dtype=np.float32)
        correction=np.asarray(np.float32(1.5)-np.asarray(np.float32(0.5)*np.asarray(argument*yy,dtype=np.float32),dtype=np.float32),dtype=np.float32)
        inverse=np.asarray(inverse*correction,dtype=np.float32)
    return inverse

def metrics(model,actual,reference):
    af=model.bits_to_float(actual);rf=model.bits_to_float(reference);err=np.abs(af-rf)
    return {"bit_mismatches":int(np.count_nonzero(actual!=reference)),"max_abs":float(np.max(err)),"mean_abs":float(np.mean(err,dtype=np.float64))}

def main():
    model=load_model();OUT.mkdir(parents=True,exist_ok=True);rng=np.random.default_rng(5100)
    cases=[];accuracy=[]
    for width,rows in ((128,8),(2048,4)):
        profile=f"rmsnorm_w{width}"
        # Non-zero mean and non-uniform magnitudes distinguish RMSNorm from LN.
        raw=np.asarray(rng.normal(0.35,1.1,size=(rows,width)),dtype=np.float32)
        gamma_raw=np.asarray(rng.uniform(0.65,1.35,size=width),dtype=np.float32)
        beta_raw=np.asarray(rng.uniform(2.0,3.0,size=width),dtype=np.float32)
        xb=model.float_to_bits(raw);gb=model.float_to_bits(gamma_raw);bb=model.float_to_bits(beta_raw)
        x=model.bits_to_float(xb);gamma=model.bits_to_float(gb)
        _,sumsq=reduce_interleaved(x)
        invh=np.float32(1.0/width);eps=np.float32(1.0e-5)
        mean_square=np.asarray(sumsq*invh,dtype=np.float32)
        argument=np.asarray(mean_square+eps,dtype=np.float32)
        inverse=nr2_rsqrt(model,argument)
        mixed=model.float_to_bits(np.asarray(np.asarray(x*inverse[:,None],dtype=np.float32)*gamma[None,:],dtype=np.float32))
        reference_inv=np.asarray(np.float32(1.0)/np.sqrt(np.mean(np.asarray(x*x,dtype=np.float32),axis=1,dtype=np.float32)+eps),dtype=np.float32)
        reference=model.float_to_bits(np.asarray(np.asarray(x*reference_inv[:,None],dtype=np.float32)*gamma[None,:],dtype=np.float32))
        for suffix,values in (("x",xb.reshape(-1)),("gamma",gb),("beta",bb),("mixed_expected",mixed.reshape(-1)),("reference_expected",reference.reshape(-1))):
            write_hex(OUT/f"{profile}_{suffix}.hex",values)
        item={"profile_id":profile,"rows":rows,"hidden_size":width,"vectors_per_bank":width//128,
              "inv_hidden_fp32":f"{fp32_bits(1.0/width):08x}","epsilon_fp32":f"{fp32_bits(1.0e-5):08x}"}
        cases.append(item);accuracy.append({**item,**metrics(model,mixed,reference)})
    with (OUT/"cases.csv").open("w",newline="",encoding="utf-8") as stream:
        writer=csv.DictWriter(stream,fieldnames=list(cases[0]));writer.writeheader();writer.writerows(cases)
    with (OUT/"numerical_accuracy.csv").open("w",newline="",encoding="utf-8") as stream:
        writer=csv.DictWriter(stream,fieldnames=list(accuracy[0]));writer.writeheader();writer.writerows(accuracy)
    (OUT/"manifest.json").write_text(json.dumps({"mode":"RMSNorm","dtype":"BF16","lanes":8,"cases":accuracy},indent=2)+"\n",encoding="utf-8")
    if max(row["max_abs"] for row in accuracy)>0.025: raise SystemExit("RMS vectors exceed accuracy threshold")
    print(f"RMSNORM_VECTORS PASS cases={len(cases)} max_abs={max(row['max_abs'] for row in accuracy):.8f}")
if __name__=="__main__": main()
