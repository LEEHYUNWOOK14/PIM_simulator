#!/usr/bin/env python3
"""Generate FP16 local-reduction and normalization-apply vectors."""
from __future__ import annotations
import importlib.util,math,random,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location("rsqrt_eval_bank",ROOT/"tools"/"evaluate_rsqrt_candidates.py")
if SPEC is None or SPEC.loader is None: raise RuntimeError("evaluator unavailable")
E=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=E;SPEC.loader.exec_module(E)
OUT=ROOT/"verification"/"groot_normalization"
ROWS=128;MAX_ELEMENTS=16
def bits(v): return 0x7e00 if math.isnan(v) else struct.unpack("<H",struct.pack("<e",v))[0]
def qadd(a,b): return E.fp16(E.fp16(a)+E.fp16(b))
def main():
    rng=random.Random(20260813);meta=[];elements=[]
    for row in range(ROWS):
        mode=row&1;length=1+(row%MAX_ELEMENTS);mean=E.fp16(rng.uniform(-1,1));inv=E.fp16(2**rng.uniform(-2,2))
        total=E.fp16(0);sumsq=E.fp16(0)
        row_elements=[]
        for i in range(MAX_ELEMENTS):
            if i<length:
                x=E.fp16(rng.uniform(-3,3));gamma=E.fp16(rng.uniform(0.5,1.5));beta=E.fp16(rng.uniform(-0.5,0.5))
                total=qadd(total,x);sumsq=qadd(sumsq,E.fp16(x*x))
                centered=x if mode else E.fp16(x-mean)
                expected=E.fp16(E.fp16(E.fp16(centered*inv)*gamma)+(0 if mode else beta))
            else:x=gamma=beta=expected=E.fp16(0)
            row_elements.append((bits(x)<<48)|(bits(gamma)<<32)|(bits(beta)<<16)|bits(expected))
        word=(mode<<127)|(length<<120)|(bits(mean)<<104)|(bits(inv)<<88)|(bits(total)<<72)|(bits(sumsq)<<56)|row
        meta.append(word);elements.extend(row_elements)
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/"bank_normalization_meta.hex").open("w",encoding="ascii",newline="\n") as f:
        for v in meta:f.write(f"{v:032x}\n")
    with (OUT/"bank_normalization_elements.hex").open("w",encoding="ascii",newline="\n") as f:
        for v in elements:f.write(f"{v:016x}\n")
    print(f"WROTE bank_normalization_rows={ROWS} elements={len(elements)}")
if __name__=="__main__":main()
