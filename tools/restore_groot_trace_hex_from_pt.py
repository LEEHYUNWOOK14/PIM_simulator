#!/usr/bin/env python3
"""Restore captured BF16 hex files from the self-contained torch zip archives.

The trace directory keeps the original ``torch.save`` archives even when the
redundant text hex files have been pruned.  BF16 tensor storages are raw
little-endian uint16 arrays, so restoring them does not require importing
PyTorch.  Input/output storages are authenticated against trace_manifest.json.
"""

from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "reports/groot_normalization/results/actual_groot/action_head_trace"


def storage(archive: Path, index: int) -> bytes:
    prefix = archive.stem
    with zipfile.ZipFile(archive) as handle:
        return handle.read(f"{prefix}/data/{index}")


def write_bf16_hex(path: Path, raw: bytes) -> None:
    if len(raw) & 1:
        raise RuntimeError(f"odd BF16 storage length: {path} ({len(raw)} bytes)")
    path.write_text(
        "\n".join(f"{int.from_bytes(raw[i:i + 2], 'little'):04x}" for i in range(0, len(raw), 2))
        + "\n",
        encoding="ascii",
    )


def main() -> int:
    manifest = json.loads((TRACE / "trace_manifest.json").read_text(encoding="utf-8"))
    restored = 0
    for profile, sample in manifest["samples"].items():
        archive = TRACE / sample["sample_file"]
        if not archive.is_file():
            raise RuntimeError(f"missing source archive for {profile}: {archive}")
        tensors = {
            "input_hex": storage(archive, 0),
            "output_hex": storage(archive, 1),
            "gamma_hex": storage(archive, 2),
            "beta_hex": storage(archive, 3),
        }
        elements = 1
        for extent in sample["shape"]:
            elements *= int(extent)
        hidden = int(sample["shape"][-1])
        expected_bytes = {
            "input_hex": elements * 2,
            "output_hex": elements * 2,
            "gamma_hex": hidden * 2,
            "beta_hex": hidden * 2,
        }
        for field, raw in tensors.items():
            if len(raw) != expected_bytes[field]:
                raise RuntimeError(
                    f"storage size mismatch for {profile}/{field}: "
                    f"got={len(raw)} expected={expected_bytes[field]}"
                )
        for field, hash_field in (("input_hex", "input_sha256"), ("output_hex", "output_sha256")):
            digest = hashlib.sha256(tensors[field]).hexdigest()
            if digest != sample[hash_field]:
                raise RuntimeError(
                    f"authenticated storage mismatch for {profile}/{field}: "
                    f"got={digest} expected={sample[hash_field]}"
                )
        for field, raw in tensors.items():
            destination = TRACE / sample[field]
            write_bf16_hex(destination, raw)
            restored += 1
    print(
        "GROOT_TRACE_HEX_RESTORE PASS "
        f"profiles={len(manifest['samples'])} files={restored} input_output_sha256=verified"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"GROOT_TRACE_HEX_RESTORE FAIL: {error}", file=sys.stderr)
        raise
