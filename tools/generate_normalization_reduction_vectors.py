#!/usr/bin/env python3
"""Generate tagged multi-bank reduction vectors for the normalization engine."""

from __future__ import annotations

import importlib.util
import math
import random
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVALUATOR = ROOT / "tools" / "evaluate_rsqrt_candidates.py"
META = ROOT / "verification" / "groot_normalization" / "normalization_reduction_meta.hex"
PARTIALS = ROOT / "verification" / "groot_normalization" / "normalization_reduction_partials.hex"
TRANSACTIONS = 512
MAX_BANKS = 16


def load_evaluator():
    spec = importlib.util.spec_from_file_location("rsqrt_eval_reduction", EVALUATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load evaluator")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def bits(value: float) -> int:
    if math.isnan(value):
        return 0x7E00
    return struct.unpack("<H", struct.pack("<e", value))[0]


def half_from_bits(value: int) -> float:
    return struct.unpack("<e", struct.pack("<H", value))[0]


def qadd(a: float, b: float, q) -> float:
    return q(q(a) + q(b))


def make_transaction(module, index: int, rng: random.Random):
    q = module.fp16
    mode = index & 1
    banks = (2, 4, 8, 16)[(index // 2) % 4]
    expected_mask = (1 << banks) - 1
    hidden = (64, 256, 1536, 2048)[(index // 8) % 4]
    inv_hidden = q(1.0 / hidden)
    epsilon = q(1.0e-6 if mode else 1.0e-5)
    partial_values = []
    total_sum = q(0.0)
    total_sumsq = q(0.0)
    for bank in range(MAX_BANKS):
        if bank < banks:
            partial_sum = q(0.0 if mode else rng.uniform(-8.0,8.0))
            partial_sumsq = q(rng.uniform(0.01,16.0))
            total_sum = qadd(total_sum,partial_sum,q)
            total_sumsq = qadd(total_sumsq,partial_sumsq,q)
        else:
            partial_sum = q(0.0)
            partial_sumsq = q(0.0)
        partial_values.append((bits(partial_sum) << 16) | bits(partial_sumsq))
    mean = q(total_sum * inv_hidden) if not mode else q(0.0)
    mean_square = q(total_sumsq * inv_hidden)
    if mode:
        variance = mean_square
        clamped = 0
    else:
        mean_squared = q(mean * mean)
        variance = q(mean_square - mean_squared)
        clamped = int(math.copysign(1.0,variance) < 0.0 and variance != 0.0)
        if clamped:
            variance = q(0.0)
    argument = q(variance + epsilon)
    inv_std = module.rsqrt_candidate(argument,"FP16",0)
    meta = 0
    meta |= mode << 127
    meta |= expected_mask << 96
    meta |= bits(inv_hidden) << 80
    meta |= bits(epsilon) << 64
    meta |= bits(mean) << 48
    meta |= bits(inv_std) << 32
    meta |= clamped << 31
    meta |= index & 0x7FFFFFFF
    return meta, partial_values


def main() -> None:
    module = load_evaluator()
    rng = random.Random(20260812)
    META.parent.mkdir(parents=True,exist_ok=True)
    with META.open("w",encoding="ascii",newline="\n") as meta_stream, \
         PARTIALS.open("w",encoding="ascii",newline="\n") as partial_stream:
        for index in range(TRANSACTIONS):
            meta, partials = make_transaction(module,index,rng)
            meta_stream.write(f"{meta:032x}\n")
            for partial in partials:
                partial_stream.write(f"{partial:08x}\n")
    print(f"WROTE normalization_reduction_transactions={TRANSACTIONS} partials={TRANSACTIONS*MAX_BANKS}")


if __name__ == "__main__":
    main()
