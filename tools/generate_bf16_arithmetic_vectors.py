#!/usr/bin/env python3
"""Generate deterministic BF16 add/multiply vectors from a float32 reference."""
from __future__ import annotations

import math
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "verification" / "groot_normalization" / "bf16_arithmetic_vectors.hex"
RANDOM_CASES = 20000


def bf16_to_float(bits: int) -> float:
    return struct.unpack(">f", struct.pack(">I", bits << 16))[0]


def float_to_bf16(value: float) -> int:
    if math.isnan(value):
        return 0x7FC0
    try:
        word = struct.unpack(">I", struct.pack(">f", value))[0]
    except OverflowError:
        return 0xFF80 if value < 0 else 0x7F80
    if (word & 0x7F800000) == 0x7F800000:
        return 0xFF80 if word & 0x80000000 else 0x7F80
    word += 0x7FFF + ((word >> 16) & 1)
    return (word >> 16) & 0xFFFF


def expected(a: int, b: int, multiply: bool) -> int:
    lhs, rhs = bf16_to_float(a), bf16_to_float(b)
    try:
        value = lhs * rhs if multiply else lhs + rhs
    except OverflowError:
        value = math.copysign(math.inf, lhs * rhs if multiply else lhs + rhs)
    return float_to_bf16(value)


def main() -> None:
    rng = random.Random(0xB16A2026)
    edges = [
        0x0000, 0x8000, 0x0001, 0x007F, 0x0080, 0x3F00, 0x3F80,
        0x4000, 0x4040, 0x7F7F, 0xFF7F, 0x7F80, 0xFF80, 0x7FC0,
        0x7F81, 0xFFC1,
    ]
    pairs = [(a, b) for a in edges for b in edges]
    pairs.extend((rng.randrange(1 << 16), rng.randrange(1 << 16))
                 for _ in range(RANDOM_CASES))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="ascii", newline="\n") as stream:
        for a, b in pairs:
            stream.write(f"{a:04x}{b:04x}{expected(a,b,False):04x}{expected(a,b,True):04x}\n")
    print(f"WROTE bf16_arithmetic_vectors={len(pairs)}")


if __name__ == "__main__":
    main()
