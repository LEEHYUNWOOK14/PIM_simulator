#!/usr/bin/env python3
"""Generate lane-specific C11 golden vectors for the multi-row prototype."""
from __future__ import annotations
import argparse,csv,importlib.util,json,math,struct,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];TRACE=ROOT/"reports/groot_normalization/results/actual_groot/action_head_trace"

def load_model():
  path=ROOT/"tools/explore_groot_mixed_precision.py";spec=importlib.util.spec_from_file_location("mixed_model",path);m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m);return m
def fp32_bits(v):return struct.unpack(">I",struct.pack(">f",float(v)))[0]
def write_hex(path,values,width=4):path.write_text("\n".join(f"{int(v):0{width}x}" for v in values)+"\n",encoding="ascii")
def add32(a,b):return np.asarray(a+b,dtype=np.float32)
def reduce_interleaved(x:np.ndarray,lanes:int):
  rows,hidden=x.shape;vectors=hidden//(16*lanes);layout=x.reshape(rows,vectors,16,lanes);slots=np.zeros((rows,16,4),np.float32);sqslots=np.zeros_like(slots)
  for vector in range(vectors):
    level=layout[:,vector];sq=np.asarray(level*level,dtype=np.float32)
    while level.shape[-1]>1:level=add32(level[...,0::2],level[...,1::2]);sq=add32(sq[...,0::2],sq[...,1::2])
    slot=vector%4;slots[:,:,slot]=add32(slots[:,:,slot],level[...,0]);sqslots[:,:,slot]=add32(sqslots[:,:,slot],sq[...,0])
  total=add32(add32(slots[:,:,0],slots[:,:,1]),add32(slots[:,:,2],slots[:,:,3]));sumsq=add32(add32(sqslots[:,:,0],sqslots[:,:,1]),add32(sqslots[:,:,2],sqslots[:,:,3]))
  while total.shape[1]>1:total=add32(total[:,0::2],total[:,1::2]);sumsq=add32(sumsq[:,0::2],sumsq[:,1::2])
  return total[:,0],sumsq[:,0]
def main():
  ap=argparse.ArgumentParser();ap.add_argument("--lanes",type=int,choices=(4,8,16),required=True);args=ap.parse_args();lanes=args.lanes;m=load_model()
  out=ROOT/f"reports/groot_normalization/results/multirow_l{lanes}_vectors";out.mkdir(parents=True,exist_ok=True);manifest=json.loads((TRACE/"trace_manifest.json").read_text());cases=[];accuracy=[]
  for profile,sample in manifest["samples"].items():
    hidden=int(sample["shape"][-1]);rows=math.prod(sample["shape"][:-1]);xb=m.read_hex(TRACE/sample["input_hex"]).reshape(rows,hidden);gb=m.read_hex(TRACE/sample["gamma_hex"]);bb=m.read_hex(TRACE/sample["beta_hex"]);pb=m.read_hex(TRACE/sample["output_hex"]).reshape(rows,hidden)
    x=m.bits_to_float(xb);gamma=m.bits_to_float(gb);beta=m.bits_to_float(bb);eps=1e-6 if profile=="action_dit_norm_out" else 1e-5
    total,sumsq=reduce_interleaved(x,lanes);mean,inv=m.scalar_fp32(total,sumsq,hidden,eps,"FP32_NR2");mixed=m.apply_fp32(x,gamma,beta,mean,inv)
    for suffix,values in (("x",xb.reshape(-1)),("gamma",gb),("beta",bb),("mixed_expected",mixed.reshape(-1)),("pytorch_expected",pb.reshape(-1))):write_hex(out/f"{profile}_{suffix}.hex",values)
    write_hex(out/f"{profile}_mean_fp32.hex",mean.view(np.uint32),8);write_hex(out/f"{profile}_inv_std_fp32.hex",inv.view(np.uint32),8)
    mixed_float=m.bits_to_float(mixed);py_float=m.bits_to_float(pb);max_abs=float(np.max(np.abs(mixed_float-py_float)));mismatches=int(np.count_nonzero(mixed!=pb))
    accuracy.append({"lanes":lanes,"profile_id":profile,"elements":rows*hidden,"bit_mismatches":mismatches,"max_abs":max_abs,"pass":max_abs<=0.025})
    cases.append({"profile_id":profile,"rows":rows,"hidden_size":hidden,"vectors_per_bank":hidden//(16*lanes),"inv_hidden_fp32":f"{fp32_bits(1/hidden):08x}","epsilon_fp32":f"{fp32_bits(eps):08x}","source_classification":manifest["classification"]})
  for name,data in (("cases.csv",cases),("numerical_accuracy.csv",accuracy)):
    with(out/name).open("w",newline="",encoding="utf-8")as f:w=csv.DictWriter(f,fieldnames=list(data[0]));w.writeheader();w.writerows(data)
  if not all(r["pass"] for r in accuracy):raise SystemExit(f"MULTIROW_VECTORS FAIL lanes={lanes}")
  print(f"MULTIROW_VECTORS PASS lanes={lanes} profiles={len(cases)} mismatches={sum(r['bit_mismatches'] for r in accuracy)} max_abs={max(r['max_abs'] for r in accuracy)}")
if __name__=="__main__":main()
