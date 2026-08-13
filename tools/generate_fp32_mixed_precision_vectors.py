#!/usr/bin/env python3
"""Generate deterministic IEEE-754 vectors for mixed-precision RTL primitives."""

from __future__ import annotations

import math
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification/groot_normalization/fp32_mixed_precision_vectors.hex"
SEED = 20260812


def bits(value: float) -> int:
    try:
        return struct.unpack(">I", struct.pack(">f", value))[0]
    except OverflowError:
        return 0xFF800000 if value < 0 else 0x7F800000


def value(word: int) -> float:
    return struct.unpack(">f", struct.pack(">I", word))[0]


def canonical(word: int) -> int:
    exponent = (word >> 23) & 0xFF
    fraction = word & 0x7FFFFF
    return 0x7FC00000 if exponent == 0xFF and fraction else word


def bf16(word: int) -> int:
    exponent = word & 0x7F800000
    if exponent == 0x7F800000:
        return 0x7FC0 if word & 0x007FFFFF else (word >> 16) & 0xFFFF
    rounded = (word + 0x7FFF + ((word >> 16) & 1)) & 0xFFFFFFFF
    return (rounded >> 16) & 0xFFFF


def operation(lhs: int, rhs: int, op: str) -> int:
    a, b = value(lhs), value(rhs)
    result = a + b if op == "add" else a * b
    return canonical(bits(result))


def main() -> None:
    rng = random.Random(SEED)
    directed = [
        0x00000000, 0x80000000, 0x3F800000, 0xBF800000,
        0x40000000, 0x3F000000, 0x3727C5AC, 0x358637BD,
        0x7F800000, 0xFF800000, 0x7FC00000,
        0x00800000, 0x007FFFFF, 0x00000001, 0x7F7FFFFF,
    ]
    pairs = [(a, b) for a in directed for b in directed]
    for _ in range(20000):
        # Most vectors reflect BF16-expanded operands and FP32 normalization
        # intermediates while retaining broad exponent coverage.
        if rng.random() < 0.65:
            a = (rng.randrange(0, 1 << 16) << 16) & 0xFFFFFFFF
            b = (rng.randrange(0, 1 << 16) << 16) & 0xFFFFFFFF
        else:
            a = rng.randrange(0, 1 << 32)
            b = rng.randrange(0, 1 << 32)
        pairs.append((a, b))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="ascii") as stream:
        for lhs, rhs in pairs:
            stream.write(f"{lhs:08x}{rhs:08x}{operation(lhs,rhs,'add'):08x}{operation(lhs,rhs,'mul'):08x}{bf16(lhs):04x}\n")
    print(f"WROTE fp32_mixed_precision_vectors={len(pairs)}")


if __name__ == "__main__":
    main()
