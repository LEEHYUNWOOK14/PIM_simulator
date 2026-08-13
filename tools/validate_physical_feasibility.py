#!/usr/bin/env python3
"""Validate a captured physical-feasibility result and all source hashes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from physical_feasibility_contract import ROOT, PhysicalFeasibilityError, require_valid_physical_feasibility


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="reports/hardware_cost_physical_feasibility/physical_feasibility.json")
    args = parser.parse_args()
    path = Path(args.input)
    path = path if path.is_absolute() else ROOT / path
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
        require_valid_physical_feasibility(document)
    except (OSError, json.JSONDecodeError, PhysicalFeasibilityError) as exc:
        print(f"ERROR: {exc}")
        return 2
    print(f"PHYSICAL_FEASIBILITY_VALIDATION PASS status={document['status']} freeze={document['rtl_freeze_allowed']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

