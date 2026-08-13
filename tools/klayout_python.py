#!/usr/bin/env python3
"""Load KLayout's Python API from portable project and system locations."""
from __future__ import annotations

import os
import sys
from pathlib import Path


def _candidate_paths() -> list[Path]:
    candidates: list[Path] = []
    configured = os.environ.get("KLAYOUT_PYTHON_PATH")
    if configured:
        candidates.extend(Path(item) for item in configured.split(os.pathsep) if item)

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        candidates.append(
            Path(local_app_data) / "STOB_EDA/gds-merge/venv/Lib/site-packages"
        )

    # KLayout's Debian/Ubuntu package keeps its Python modules outside the
    # interpreter's default dist-packages search path.
    candidates.extend(
        [Path("/usr/lib/klayout/pymod"), Path("/usr/local/lib/klayout/pymod")]
    )
    return candidates


try:
    import klayout.db as kdb
except ModuleNotFoundError as first_error:
    if first_error.name not in {"klayout", "klayout.db"}:
        raise
    for candidate in _candidate_paths():
        if candidate.is_dir() and str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))
        try:
            import klayout.db as kdb
            break
        except ModuleNotFoundError as error:
            if error.name not in {"klayout", "klayout.db"}:
                raise
    else:
        raise ModuleNotFoundError(
            "KLayout Python API not found; set KLAYOUT_PYTHON_PATH or install "
            "the project gds-merge environment"
        ) from first_error


__all__ = ["kdb"]
