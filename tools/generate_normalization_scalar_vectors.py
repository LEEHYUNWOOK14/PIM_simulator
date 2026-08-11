#!/usr/bin/env python3
"""Generate bit-exact vectors for logic_normalization_scalar_engine."""

from __future__ import annotations

import importlib.util
import math
import random
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVALUATOR = ROOT / "tools" / "evaluate_rsqrt_candidates.py"
OUTPUT = ROOT / "verification" / "groot_normalization" / "normalization_scalar_vectors.hex"
VECTOR_COUNT = 2048


def load_evaluator():
    spec = importlib.util.spec_from_file_location("rsqrt_eval_scalar", EVALUATOR)
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


def qneg(value: float, q) -> float:
    encoded = bits(value) ^ 0x8000
    return struct.unpack("<e", struct.pack("<H", encoded))[0]


def make_vector(module, index: int, rng: random.Random) -> int:
    q = module.fp16
    mode = index & 1
    hidden = (64, 256, 1536, 2048)[(index // 2) % 4]
    inv_hidden = q(1.0 / hidden)
    epsilon = q(1.0e-6 if mode else 1.0e-5)
    mean_target = 0.0 if mode else rng.uniform(-1.5, 1.5)
    variance_target = 2.0 ** rng.uniform(-16.0, 2.0)
    if index < 8:
        mean_target = (0.0, 1.0, -1.0, 0.25)[index % 4] if not mode else 0.0
        variance_target = (0.0, 1.0e-6, 1.0e-4, 1.0)[index % 4]
    sum_value = q(mean_target / inv_hidden) if not mode else q(0.0)
    sumsq_value = q((variance_target + mean_target * mean_target) / inv_hidden)
    mean = q(sum_value * inv_hidden) if not mode else q(0.0)
    mean_square = q(sumsq_value * inv_hidden)
    if mode:
        variance = mean_square
        clamped = 0
    else:
        mean_squared = q(mean * mean)
        variance = q(mean_square + qneg(mean_squared, q))
        clamped = int(math.copysign(1.0, variance) < 0.0 and variance != 0.0)
        if clamped:
            variance = q(0.0)
    argument = q(variance + epsilon)
    inv_std = module.rsqrt_candidate(argument, "FP16", 0)
    packed = 0
    packed |= mode << 112
    packed |= bits(sum_value) << 96
    packed |= bits(sumsq_value) << 80
    packed |= bits(inv_hidden) << 64
    packed |= bits(epsilon) << 48
    packed |= bits(mean) << 32
    packed |= bits(inv_std) << 16
    packed |= clamped << 15
    packed |= index & 0x7FFF
    return packed


def main() -> None:
    module = load_evaluator()
    rng = random.Random(20260811)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="ascii", newline="\n") as stream:
        for index in range(VECTOR_COUNT):
            stream.write(f"{make_vector(module,index,rng):032x}\n")
    print(f"WROTE normalization_scalar_vectors={VECTOR_COUNT}")


if __name__ == "__main__":
    main()
