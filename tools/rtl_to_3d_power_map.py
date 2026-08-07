#!/usr/bin/env python3
"""Map normalized synthesis/placement/activity power data onto the HBM2 stack."""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_UNITS = {"length": "um", "area": "um^2", "power": "W"}


class MappingError(ValueError):
    pass


def read_json(path: str | Path) -> dict:
    p = Path(path)
    if not p.is_absolute():
        p = ROOT / p
    return json.loads(p.read_text(encoding="utf-8"))


def finite_nonnegative(value, name: str, positive: bool = False) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise MappingError(f"{name} must be numeric") from exc
    if not math.isfinite(number) or number < 0 or (positive and number == 0):
        raise MappingError(f"{name} must be {'positive' if positive else 'non-negative'} and finite")
    return number


def validate_document(doc: dict) -> None:
    if doc.get("schema_version") != 1:
        raise MappingError("schema_version must be 1")
    if doc.get("units") != EXPECTED_UNITS:
        raise MappingError(f"units must be exactly {EXPECTED_UNITS}; implicit conversion is forbidden")
    sources = doc.get("sources", {})
    missing_sources = [x for x in ("synthesis", "placement", "activity", "power") if not sources.get(x)]
    if missing_sources:
        raise MappingError("missing source provenance: " + ", ".join(missing_sources))
    blocks = doc.get("blocks")
    if not isinstance(blocks, list) or not blocks:
        raise MappingError("blocks must be a non-empty array")
    names = set()
    for index, block in enumerate(blocks):
        prefix = f"blocks[{index}]"
        for key in ("instance", "module", "area_um2", "power"):
            if key not in block:
                raise MappingError(f"{prefix} missing {key}")
        if block["instance"] in names:
            raise MappingError(f"duplicate instance: {block['instance']}")
        names.add(block["instance"])
        finite_nonnegative(block["area_um2"], f"{prefix}.area_um2", positive=True)
        for key in ("dynamic_W", "leakage_W"):
            finite_nonnegative(block["power"].get(key), f"{prefix}.power.{key}")
        if "placement" in block:
            for key in ("x_um", "y_um", "width_um", "height_um"):
                finite_nonnegative(block["placement"].get(key), f"{prefix}.placement.{key}", positive=key in ("width_um", "height_um"))


def bank_tile(arch: dict, channel: int, bank: int) -> dict:
    channels = int(arch["physical_channels_per_stack"])
    cols = int(arch["layout"]["bank_columns"])
    rows = int(arch["layout"]["bank_rows"])
    if not 0 <= channel < channels or not 0 <= bank < cols * rows:
        raise MappingError(f"HBM target out of range: channel={channel}, bank={bank}")
    width = float(arch["geometry_um"]["die_width"]["value"])
    height = float(arch["geometry_um"]["die_height"]["value"])
    channel_w = width / channels
    bank_w = channel_w / cols
    bank_h = height / rows
    return {"x_um": channel * channel_w + (bank % cols) * bank_w,
            "y_um": (bank // cols) * bank_h, "width_um": bank_w, "height_um": bank_h}


def find_rule(block: dict, rules: dict) -> tuple[dict | None, re.Match | None]:
    haystack = f"{block['instance']} {block['module']}"
    for rule in rules["rules"]:
        match = re.search(rule["match"], haystack, re.IGNORECASE)
        if match:
            return rule, match
    return None, None


def target_for(block: dict, rule: dict, match: re.Match, arch: dict) -> tuple[dict, dict]:
    target = {"stack": int(rule.get("stack", 0)), "layer": rule["target"]}
    hint = block.get("target_hint", {})
    if target["layer"] == "dram":
        groups = match.groupdict()
        try:
            channel = int(groups.get("channel") if groups.get("channel") is not None else hint["channel"])
            bank = int(groups.get("bank") if groups.get("bank") is not None else hint["bank"])
        except (KeyError, TypeError) as exc:
            raise MappingError(f"{block['instance']}: DRAM mapping requires channel and bank in name or target_hint") from exc
        die = int(hint.get("die", rule.get("die", 0)))
        if not 0 <= die < int(arch["dram_dies_per_stack"]):
            raise MappingError(f"{block['instance']}: DRAM die {die} out of range")
        target.update({"die": die, "channel": channel, "bank": bank})
        placement = bank_tile(arch, channel, bank)
    else:
        target.update({"die": -1, "channel": -1, "bank": -1})
        if "placement" not in block:
            raise MappingError(f"{block['instance']}: logic block requires OpenROAD placement")
        placement = {k: float(block["placement"][k]) for k in ("x_um", "y_um", "width_um", "height_um")}
    target["stack"] = int(hint.get("stack", target["stack"]))
    return target, placement


def map_document(doc: dict, rules: dict, arch: dict, allow_unmapped: bool = False) -> dict:
    validate_document(doc)
    die_w = float(arch["geometry_um"]["die_width"]["value"])
    die_h = float(arch["geometry_um"]["die_height"]["value"])
    stacks = int(arch["stack_count"])
    mapped, unmapped, warnings = [], [], []
    input_power = 0.0
    for block in doc["blocks"]:
        dynamic = float(block["power"]["dynamic_W"])
        leakage = float(block["power"]["leakage_W"])
        total = dynamic + leakage
        input_power += total
        rule, match = find_rule(block, rules)
        if rule is None:
            unmapped.append({"instance": block["instance"], "module": block["module"], "power_W": total})
            continue
        target, placement = target_for(block, rule, match, arch)
        if not 0 <= target["stack"] < stacks:
            raise MappingError(f"{block['instance']}: stack {target['stack']} out of range")
        if placement["x_um"] + placement["width_um"] > die_w + 1e-9 or placement["y_um"] + placement["height_um"] > die_h + 1e-9:
            raise MappingError(f"{block['instance']}: placement outside {die_w:g} x {die_h:g} um die")
        placed_area = placement["width_um"] * placement["height_um"]
        synth_area = float(block["area_um2"])
        mismatch = abs(placed_area - synth_area) / synth_area
        if target["layer"] == "logic" and mismatch > float(rules["area_mismatch_tolerance_ratio"]):
            warnings.append({"instance": block["instance"], "type": "area_mismatch", "ratio": mismatch,
                             "message": "placed rectangle area differs from synthesis area"})
        mapped.append({
            "instance": block["instance"], "module": block["module"], "rule_id": rule["id"],
            "target": target, "rectangle_um": placement, "synthesis_area_um2": synth_area,
            "mapped_area_um2": placed_area, "dynamic_power_W": dynamic, "leakage_power_W": leakage,
            "total_power_W": total, "power_density_W_mm2": total / placed_area * 1e6,
            "activity": block.get("activity", {"format": "normalized"})
        })
    unmapped_power = sum(x["power_W"] for x in unmapped)
    mapped_power = sum(x["total_power_W"] for x in mapped)
    if unmapped and not allow_unmapped and rules.get("unmapped_policy", "error") == "error":
        raise MappingError("unmapped RTL blocks: " + ", ".join(x["instance"] for x in unmapped))
    tolerance = float(rules["power_conservation_tolerance_W"])
    conservation_error = abs(input_power - mapped_power - unmapped_power)
    if conservation_error > tolerance:
        raise MappingError(f"power conservation failed: {conservation_error:.12g} W")
    return {
        "schema_version": 1,
        "status": "PASS" if not unmapped else "PASS_WITH_UNMAPPED",
        "coordinate_system": rules["coordinate_system"], "units": EXPECTED_UNITS,
        "architecture": {"die_width_um": die_w, "die_height_um": die_h, "stack_count": stacks,
                         "dram_dies_per_stack": int(arch["dram_dies_per_stack"])},
        "sources": doc["sources"], "blocks": mapped, "unmapped_blocks": unmapped, "warnings": warnings,
        "checks": {
            "unit_validation": "PASS", "bounds_validation": "PASS",
            "input_power_W": input_power, "mapped_power_W": mapped_power,
            "unmapped_power_W": unmapped_power, "power_conservation_error_W": conservation_error,
            "power_conservation_tolerance_W": tolerance,
            "power_conservation": "PASS", "unmapped_detection": "PASS" if not unmapped else "DETECTED"
        },
        "disclaimer": "Power is only as accurate as the supplied RTL activity and power reports; mapping is architectural, not thermal signoff."
    }


def write_report(result: dict, path: Path) -> None:
    c = result["checks"]
    rows = ["# RTL-to-3D power mapping report", "", f"- Status: **{result['status']}**",
            f"- Mapped blocks: {len(result['blocks'])}", f"- Unmapped blocks: {len(result['unmapped_blocks'])}",
            f"- Input power: {c['input_power_W']:.9g} W", f"- Mapped power: {c['mapped_power_W']:.9g} W",
            f"- Conservation error: {c['power_conservation_error_W']:.3g} W", "",
            "| Instance | 3D target | Rectangle (um) | Area (um^2) | Power (W) | Density (W/mm^2) |",
            "|---|---|---:|---:|---:|---:|"]
    for b in result["blocks"]:
        t = b["target"]
        where = f"stack {t['stack']} / {t['layer']}"
        if t["layer"] == "dram": where += f" {t['die']} / ch {t['channel']} / bank {t['bank']}"
        r = b["rectangle_um"]
        rect = f"({r['x_um']:g},{r['y_um']:g}) {r['width_um']:g}x{r['height_um']:g}"
        rows.append(f"| `{b['instance']}` | {where} | {rect} | {b['mapped_area_um2']:.7g} | {b['total_power_W']:.7g} | {b['power_density_W_mm2']:.7g} |")
    rows += ["", "## Validation", "", "- Units are explicit and implicit conversion is rejected.",
             "- Every rectangle is checked against die bounds.", "- Input power is conserved across mapped and explicitly reported unmapped blocks.",
             "- Unknown module names fail by default.", "", f"> {result['disclaimer']}"]
    path.write_text("\n".join(rows) + "\n", encoding="utf-8")


def run(input_path: str, rules_path: str, architecture_path: str, output: str, allow_unmapped: bool = False) -> dict:
    result = map_document(read_json(input_path), read_json(rules_path), read_json(architecture_path), allow_unmapped)
    out = Path(output)
    if not out.is_absolute(): out = ROOT / out
    out.mkdir(parents=True, exist_ok=True)
    (out / "mapped_power.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    write_report(result, out / "mapping_report.md")
    print(json.dumps(result["checks"], indent=2))
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", default="verification/rtl_to_3d/fixtures/synthetic_input.json")
    ap.add_argument("--rules", default="design/rtl_to_3d/mapping_rules.json")
    ap.add_argument("--architecture", default="design/hbm2_architecture.json")
    ap.add_argument("--output", default="output/rtl_to_3d")
    ap.add_argument("--allow-unmapped", action="store_true")
    args = ap.parse_args()
    try:
        run(args.input, args.rules, args.architecture, args.output, args.allow_unmapped)
    except MappingError as exc:
        print(f"ERROR: {exc}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
