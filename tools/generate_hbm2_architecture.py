from __future__ import annotations

import argparse
import configparser
import json
import re
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import gdstk


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "design" / "hbm2_architecture.json"
DEFAULT_OUTPUT = ROOT / "output" / "hbm2_arch"
DISCLAIMER = "HBM2 PIM architectural visualization - not signoff layout"

LAYERS = {
    "package_substrate": (10, 0),
    "silicon_interposer": (11, 0),
    "logic_base_die": (20, 0),
    "logic_die_pim": (30, 0),
    "channel_interface": (31, 0),
    "bank_side_pim": (32, 0),
    "micro_bump": (40, 0),
    "tsv": (50, 0),
    "peripheral_logic": (60, 0),
    "bank_array": (61, 0),
    "labels": (250, 0),
}

SAIT_COMMIT = "3703d1f19c8f027360cc33a3243eb271e3bb6898"
DRAMSIM_COMMIT = "29817593b3389f1337235d63cac515024ab8fd6e"


def read_simple_ini(path: Path) -> tuple[dict[str, str], dict[str, int]]:
    values: dict[str, str] = {}
    lines: dict[str, int] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
        clean = raw.split(";", 1)[0].split("#", 1)[0].strip()
        if "=" not in clean or clean.startswith("["):
            continue
        key, value = clean.split("=", 1)
        values[key.strip()] = value.strip()
        lines[key.strip()] = number
    return values, lines


def read_dramsim(path: Path) -> configparser.ConfigParser:
    parser = configparser.ConfigParser()
    parser.optionxform = str
    parser.read(path, encoding="utf-8")
    return parser


def as_number(value: str) -> int | float | str:
    try:
        return int(value, 0)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return value


def detect_rtl_modules(root: Path, requested: list[str]) -> dict[str, Any]:
    found: dict[str, Any] = {}
    module_re = re.compile(r"\bmodule\s+([A-Za-z_]\w*)")
    parameter_re = re.compile(
        r"\bparameter(?:\s+(?:int|bit|logic|string))?(?:\s+unsigned)?\s+([A-Za-z_]\w*)\s*=\s*([^,\n\)]+)"
    )
    for path in sorted((root / "rtl").glob("*.sv")):
        text = path.read_text(encoding="utf-8", errors="replace")
        match = module_re.search(text)
        if not match or match.group(1) not in requested:
            continue
        found[match.group(1)] = {
            "file": path.relative_to(root).as_posix(),
            "parameters": {name: expression.strip() for name, expression in parameter_re.findall(text)},
        }
    return found


def source_record(value: Any, unit: str, classification: str, source_type: str,
                  source: str, location: str, commit: str | None, confidence: str) -> dict[str, Any]:
    return {
        "value": value,
        "unit": unit,
        "source_type": source_type,
        "source_repository_or_document": source,
        "source_file_line_or_section": location,
        "upstream_commit_hash": commit,
        "confidence": confidence,
        "classification": classification,
    }


def build_provenance(cfg: dict[str, Any], sait: dict[str, str], sait_lines: dict[str, int],
                     system: dict[str, str], system_lines: dict[str, int],
                     dramsim: configparser.ConfigParser, rtl: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    standard = "JEDEC JESD235 family"
    result["physical_channels_per_stack"] = source_record(
        cfg["physical_channels_per_stack"], "channels/stack", "standard", "standard",
        standard, "HBM2 stack/channel organization", None, "high")
    result["channel_width_bits"] = source_record(
        cfg["channel_width_bits"], "bit/channel", "standard", "standard",
        standard, "HBM2 channel interface", None, "high")
    result["stack_interface_width_bits"] = source_record(
        cfg["physical_channels_per_stack"] * cfg["channel_width_bits"], "bit/stack", "standard", "derived",
        standard, "physical_channels_per_stack * channel_width_bits", None, "high")
    result["dram_dies_per_stack"] = source_record(
        cfg["dram_dies_per_stack"], "dies/stack", "project_config", "configuration",
        "local model configuration", "design/hbm2_architecture.json", None, "high")
    result["pseudo_channel_mode"] = source_record(
        cfg["pseudo_channel_mode"], "boolean", "project_config", "configuration",
        "local model configuration", "design/hbm2_architecture.json", None, "high")
    result["logical_channels"] = source_record(
        cfg["logical_channel_mapping"]["logical_channels"], "logical partitions", "project_config", "configuration",
        "local simulator configuration", "design/hbm2_architecture.json logical_channel_mapping", None, "high")

    sait_map = {
        "bank_groups": "NUM_BANK_GROUPS", "banks": "NUM_BANKS", "rows": "NUM_ROWS",
        "columns": "NUM_COLS", "pim_blocks": "NUM_PIM_BLOCKS", "device_width": "DEVICE_WIDTH",
        "burst_length": "BL", "tRCDRD": "tRCDRD", "tRCDWR": "tRCDWR", "tRAS": "tRAS",
        "tRP": "tRP", "tRC": "tRC", "tRFC": "tRFC", "tREFI": "tREFI", "tREFISB": "tREFISB",
    }
    for name, key in sait_map.items():
        result[name] = source_record(
            as_number(sait[key]), "cycles" if key.startswith("t") else "count", "project_config",
            "open_source_model", "SAITPublic/PIMSimulator",
            f"ini/HBM2_samsung_2M_16B_x64.ini:{sait_lines[key]}", SAIT_COMMIT, "high")
    if "NUM_CHANS" in system:
        result["system_num_chans"] = source_record(
            as_number(system["NUM_CHANS"]), "logical channels", "project_config", "project_config",
            "STOB PIMSimulator working tree", f"{cfg['sait_system_file']}:{system_lines['NUM_CHANS']}", None, "high")

    for section, keys in {
        "dram_structure": ["bankgroups", "banks_per_group", "rows", "columns", "device_width", "BL", "num_dies"],
        "system": ["channels", "bus_width", "address_mapping"],
        "timing": ["tRCDRD", "tRCDWR", "tRP", "tRAS", "tRFC", "tREFI"],
    }.items():
        for key in keys:
            result[f"dramsim3.{key}"] = source_record(
                as_number(dramsim[section][key]), "reference value", "open_source_model", "open_source_model",
                "umd-memsys/DRAMsim3", f"configs/HBM2_8Gb_x128.ini [{section}] {key}",
                DRAMSIM_COMMIT, "high")
    for module, info in rtl.items():
        result[f"rtl.{module}"] = source_record(
            info["parameters"], "SystemVerilog parameter expressions", "rtl_derived", "rtl_derived",
            "STOB PIM2 working tree", info["file"], None, "medium")
    for key, meta in cfg["geometry_um"].items():
        result[f"geometry.{key}"] = source_record(
            meta["value"], "scale" if "scale" in key else "um", meta["classification"], "configuration",
            "local architectural visualization", f"design/hbm2_architecture.json geometry_um.{key}", None,
            "low" if meta["classification"] == "illustrative" else "medium")
    return result


def add_rect(cell: gdstk.Cell, xy: tuple[float, float, float, float], layer_key: str, datatype: int | None = None) -> None:
    layer, default_dtype = LAYERS[layer_key]
    cell.add(gdstk.rectangle(xy[:2], xy[2:], layer=layer, datatype=default_dtype if datatype is None else datatype))


def build_gds(cfg: dict[str, Any], facts: dict[str, int], rtl: dict[str, Any], out: Path) -> dict[str, Any]:
    lib = gdstk.Library(unit=1e-6, precision=1e-9)
    geometry = {key: value["value"] for key, value in cfg["geometry_um"].items()}
    die_w, die_h = geometry["die_width"], geometry["die_height"]
    bank_count = facts["banks"]
    channels = cfg["physical_channels_per_stack"]
    pim_blocks = facts["pim_blocks"]
    bank_cols = cfg["layout"]["bank_columns"]
    bank_rows = cfg["layout"]["bank_rows"]
    if bank_cols * bank_rows != bank_count:
        raise ValueError(f"bank grid {bank_cols}x{bank_rows} does not equal {bank_count} banks")

    die_cells = []
    channel_gap = 20.0
    channel_w = (die_w - channel_gap * (channels - 1)) / channels
    periph_h = die_h * 0.12
    bank_area_h = die_h - periph_h - 30
    bank_w = channel_w / bank_cols
    bank_h = bank_area_h / bank_rows
    bank_template = lib.new_cell("HBM2_CHANNEL_BANK_ARRAY_16BANKS")
    for bank in range(bank_count):
        col, row = bank % bank_cols, bank // bank_cols
        bx0, by0 = col * bank_w + 2, row * bank_h + 2
        add_rect(bank_template, (bx0, by0, bx0 + bank_w - 4, by0 + bank_h - 4),
                 "bank_array", bank + 1)
    add_rect(bank_template, (0, bank_area_h, channel_w, die_h), "peripheral_logic")
    for pim in range(pim_blocks):
        px0 = pim * channel_w / pim_blocks + 2
        add_rect(bank_template, (px0, bank_area_h + 3,
                                 px0 + channel_w / pim_blocks - 4, die_h - 3), "bank_side_pim")
    for die_index in range(cfg["dram_dies_per_stack"]):
        die = lib.new_cell(f"DRAM_DIE_{die_index:02d}_8PHYSICAL_CHANNELS")
        dram_layer = 100 + die_index
        for channel in range(channels):
            x0 = -die_w / 2 + channel * (channel_w + channel_gap)
            die.add(gdstk.rectangle((x0, -die_h / 2), (x0 + channel_w, die_h / 2), layer=dram_layer))
            die.add(gdstk.Reference(bank_template, origin=(x0, -die_h / 2)))
            channel_suffix = " / PC0+PC1" if cfg["pseudo_channel_mode"] else ""
            die.add(gdstk.Label(f"CH{channel}{channel_suffix}: {bank_count} banks", (x0 + 10, die_h / 2 - periph_h / 2),
                                layer=LAYERS["labels"][0]))
        die.add(gdstk.Label(f"HBM2 DRAM DIE {die_index} - ARCHITECTURAL", (-die_w / 2, die_h / 2 + 60),
                            layer=LAYERS["labels"][0]))
        die_cells.append(die)

    logic = lib.new_cell("HBM2_BASE_LOGIC_DIE")
    add_rect(logic, (-die_w / 2, -die_h / 2, die_w / 2, die_h / 2), "logic_base_die")
    block_names = list(rtl) or ["RTL analysis unavailable"]
    cols = 2
    rows = (len(block_names) + cols - 1) // cols
    bw, bh = die_w / cols, die_h / rows
    for index, name in enumerate(block_names):
        col, row = index % cols, index // cols
        x0, y0 = -die_w / 2 + col * bw + 30, -die_h / 2 + row * bh + 30
        add_rect(logic, (x0, y0, x0 + bw - 60, y0 + bh - 60), "logic_die_pim", index + 1)
        logic.add(gdstk.Label(name, (x0 + 20, y0 + bh / 2), layer=LAYERS["labels"][0]))
    for channel in range(channels):
        x0 = -die_w / 2 + channel * die_w / channels
        add_rect(logic, (x0 + 3, -die_h / 2 + 5, x0 + die_w / channels - 3, -die_h / 2 + 180),
                 "channel_interface")

    top = lib.new_cell("HBM2_PIM_ARCHITECTURE_NOT_SIGNOFF")
    stack_count = cfg["stack_count"]
    stack_pitch = geometry["interposer_width"] * 1.05
    package_w = max(geometry["package_width"], stack_count * stack_pitch + 500)
    package_h = geometry["package_height"]
    inter_w, inter_h = geometry["interposer_width"], geometry["interposer_height"]
    add_rect(top, (-package_w / 2, -package_h / 2, package_w / 2, package_h / 2), "package_substrate")
    add_rect(top, (-inter_w / 2, -inter_h / 2, inter_w / 2, inter_h / 2), "silicon_interposer")
    stack_origins = [(stack - (stack_count - 1) / 2) * stack_pitch for stack in range(stack_count)]
    for stack, origin_x in enumerate(stack_origins):
        top.add(gdstk.Reference(logic, origin=(origin_x, 0)))
        for die in die_cells:
            top.add(gdstk.Reference(die, origin=(origin_x, 0)))
        top.add(gdstk.Label(f"HBM2 STACK {stack}", (origin_x - die_w / 2, -die_h / 2 - 100),
                            layer=LAYERS["labels"][0]))

    bump_cols, bump_rows = cfg["layout"]["microbump_columns"], cfg["layout"]["microbump_rows"]
    bump_size = geometry["microbump_size"]
    for origin_x in stack_origins:
        for col in range(bump_cols):
            x = origin_x - die_w * 0.46 + col * die_w * 0.92 / max(bump_cols - 1, 1)
            for row in range(bump_rows):
                y = -die_h * 0.46 + row * die_h * 0.92 / max(bump_rows - 1, 1)
                add_rect(top, (x - bump_size / 2, y - bump_size / 2, x + bump_size / 2, y + bump_size / 2),
                         "micro_bump")
    tsv_size = geometry["tsv_size"]
    groups_per_channel = cfg["layout"]["tsv_groups_per_channel"]
    tsvs_per_group = cfg["layout"]["tsvs_per_group"]
    tsv_count_per_stack = channels * groups_per_channel * tsvs_per_group
    for origin_x in stack_origins:
        for index in range(tsv_count_per_stack):
            channel = index // (groups_per_channel * tsvs_per_group)
            group = (index // tsvs_per_group) % groups_per_channel
            within = index % tsvs_per_group
            group_offset = (group - (groups_per_channel - 1) / 2) * tsv_size * 1.5
            x = origin_x - die_w * 0.44 + channel * die_w * 0.88 / max(channels - 1, 1) + group_offset
            y = -die_h * 0.35 + within * die_h * 0.70 / max(tsvs_per_group - 1, 1)
            add_rect(top, (x - tsv_size / 2, y - tsv_size / 2, x + tsv_size / 2, y + tsv_size / 2), "tsv")
    top.add(gdstk.Label(DISCLAIMER, (-package_w / 2 + 100, package_h / 2 - 150), layer=LAYERS["labels"][0]))
    # gdstk's Windows backend cannot reliably open non-ASCII output paths.
    # Write through an ASCII-only temporary path, then copy with pathlib.
    temp_gds = Path(tempfile.gettempdir()) / "stob_hbm2_pim_architecture.gds"
    lib.write_gds(temp_gds)
    shutil.copyfile(temp_gds, out)
    return {
        "top_cell": top.name,
        "stack_count": cfg["stack_count"],
        "dram_dies": len(die_cells),
        "total_dram_die_instances": stack_count * len(die_cells),
        "physical_channels_per_stack": channels,
        "pseudo_channels_per_stack": channels * 2 if cfg["pseudo_channel_mode"] else 0,
        "banks_per_channel": bank_count,
        "pim_blocks_per_channel": pim_blocks,
        "bank_to_pim_mapping": [
            {"pim_block": pim, "banks": list(range(pim, bank_count, pim_blocks))}
            for pim in range(pim_blocks)
        ],
        "tsv_groups": stack_count * channels * cfg["layout"]["tsv_groups_per_channel"],
        "tsv_shapes": stack_count * tsv_count_per_stack,
        "microbump_shapes": stack_count * bump_cols * bump_rows,
        "rtl_blocks": block_names,
        "cell_names": [cell.name for cell in lib.cells],
    }


def scad_cube(handle, name: str, color: str, x: float, y: float, z: float,
              width: float, height: float, depth: float) -> None:
    handle.write(f"// {name}\ncolor(\"{color}\") translate([{x:.4f},{y:.4f},{z:.4f}]) cube([{width:.4f},{height:.4f},{depth:.4f}]);\n")


def scad_bump_plane(handle, cfg: dict[str, Any], g: dict[str, float], sx: float,
                    die_w: float, die_h: float, origin_x: float, z: float, name: str) -> None:
    handle.write(f"// {name}\n")
    bump_depth = max(g["die_gap"] * g["visual_scale_z"] * 0.45, 0.4)
    for col in range(cfg["layout"]["microbump_columns"]):
        x = origin_x - die_w * 0.46 + col * die_w * 0.92 / max(cfg["layout"]["microbump_columns"] - 1, 1)
        for row in range(cfg["layout"]["microbump_rows"]):
            y = -die_h * 0.46 + row * die_h * 0.92 / max(cfg["layout"]["microbump_rows"] - 1, 1)
            handle.write(f"color(\"Goldenrod\") translate([{x:.3f},{y:.3f},{z:.3f}]) cylinder(h={bump_depth:.3f},r={max(g['microbump_size']*sx/2,0.08):.3f});\n")


def write_scad(cfg: dict[str, Any], facts: dict[str, int], rtl: dict[str, Any], path: Path) -> None:
    g = {key: value["value"] for key, value in cfg["geometry_um"].items()}
    sx, sz = g["visual_scale_xy"], g["visual_scale_z"]
    die_w, die_h = g["die_width"] * sx, g["die_height"] * sx
    stack_pitch = g["interposer_width"] * sx * 1.05
    package_w = max(g["package_width"] * sx, cfg["stack_count"] * stack_pitch + 5)
    stack_origins = [(stack - (cfg["stack_count"] - 1) / 2) * stack_pitch
                     for stack in range(cfg["stack_count"])]
    with path.open("w", encoding="utf-8") as out:
        out.write(f"// {DISCLAIMER}\n$fn=16;\n")
        scad_cube(out, "package substrate", "DimGray", -package_w / 2,
                  -g["package_height"] * sx / 2, 0, package_w,
                  g["package_height"] * sx, g["substrate_thickness"] * sz)
        block_names = list(rtl) or ["RTL analysis unavailable"]
        bw, bh = die_w / 2, die_h / ((len(block_names) + 1) // 2)
        channel_w = die_w / cfg["physical_channels_per_stack"]
        tsv_h = (cfg["dram_dies_per_stack"] * g["dram_die_thickness"] +
                 (cfg["dram_dies_per_stack"] - 1) * g["die_gap"]) * sz
        for stack, origin_x in enumerate(stack_origins):
            z = g["substrate_thickness"] * sz
            scad_cube(out, f"stack {stack} silicon interposer", "SlateGray",
                      origin_x - g["interposer_width"] * sx / 2, -g["interposer_height"] * sx / 2,
                      z, g["interposer_width"] * sx, g["interposer_height"] * sx,
                      g["interposer_thickness"] * sz)
            z += g["interposer_thickness"] * sz
            scad_bump_plane(out, cfg, g, sx, die_w, die_h, origin_x, z,
                            f"stack {stack} interposer-to-base micro-bumps")
            z += g["die_gap"] * sz
            scad_cube(out, f"stack {stack} base logic die", "SeaGreen", origin_x - die_w / 2,
                      -die_h / 2, z, die_w, die_h, g["logic_die_thickness"] * sz)
            for index, name in enumerate(block_names):
                col, row = index % 2, index // 2
                scad_cube(out, f"stack {stack} RTL functional block: {name}", "LimeGreen",
                          origin_x - die_w / 2 + col * bw + 0.5, -die_h / 2 + row * bh + 0.5,
                          z + g["logic_die_thickness"] * sz, bw - 1, bh - 1, 0.4)
            z += g["logic_die_thickness"] * sz
            scad_bump_plane(out, cfg, g, sx, die_w, die_h, origin_x, z,
                            f"stack {stack} base-to-DRAM micro-bumps")
            z += g["die_gap"] * sz
            tsv_z = z
            for die in range(cfg["dram_dies_per_stack"]):
                for channel in range(cfg["physical_channels_per_stack"]):
                    pseudo_suffix = " pseudo-channels 0+1" if cfg["pseudo_channel_mode"] else ""
                    scad_cube(out, f"stack {stack} die {die} physical channel {channel}{pseudo_suffix}",
                              ["RoyalBlue", "DodgerBlue", "SteelBlue", "CornflowerBlue"][die % 4],
                              origin_x - die_w / 2 + channel * channel_w + 0.15, -die_h / 2, z,
                              channel_w - 0.3, die_h, g["dram_die_thickness"] * sz)
                z += g["dram_die_thickness"] * sz
                if die != cfg["dram_dies_per_stack"] - 1:
                    scad_bump_plane(out, cfg, g, sx, die_w, die_h, origin_x, z,
                                    f"stack {stack} DRAM die {die}-to-{die + 1} micro-bumps")
                    z += g["die_gap"] * sz
            for channel in range(cfg["physical_channels_per_stack"]):
                for group in range(cfg["layout"]["tsv_groups_per_channel"]):
                    group_offset = (group - (cfg["layout"]["tsv_groups_per_channel"] - 1) / 2) * max(g["tsv_size"] * sx * 1.5, 0.3)
                    x = (origin_x - die_w * 0.44 +
                         channel * die_w * 0.88 / max(cfg["physical_channels_per_stack"] - 1, 1) + group_offset)
                    for within in range(cfg["layout"]["tsvs_per_group"]):
                        y = -die_h * 0.35 + within * die_h * 0.70 / max(cfg["layout"]["tsvs_per_group"] - 1, 1)
                        out.write(f"color(\"Gold\") translate([{x:.3f},{y:.3f},{tsv_z:.3f}]) cylinder(h={tsv_h:.3f},r={max(g['tsv_size']*sx/2,0.1):.3f});\n")


def write_layerstack(cfg: dict[str, Any], path: Path) -> None:
    lines = ["from gds3xtrude.include import layer", "", f"# {DISCLAIMER}", ""]
    for name, (number, datatype) in LAYERS.items():
        if name == "labels":
            continue
        lines.append(f"{name} = layer({number}, {datatype})")
    for die in range(cfg["dram_dies_per_stack"]):
        lines.append(f"dram_die_{die} = layer({100 + die}, 0)")
    lines += ["", "layerstack = [", "    (180, package_substrate),", "    (100, silicon_interposer),",
              "    (100, [logic_base_die, logic_die_pim, channel_interface, tsv]),",
              "    (12, [micro_bump, tsv]),"]
    for die in range(cfg["dram_dies_per_stack"]):
        lines.append(f"    (50, [dram_die_{die}, bank_array, peripheral_logic, bank_side_pim, tsv]),")
        if die != cfg["dram_dies_per_stack"] - 1:
            lines.append("    (12, [micro_bump, tsv]),")
    lines += ["]", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def write_layer_properties(cfg: dict[str, Any], path: Path) -> None:
    colors = {
        "package_substrate": "#4b5563", "silicon_interposer": "#708090",
        "logic_base_die": "#2e8b57", "logic_die_pim": "#32cd32",
        "channel_interface": "#00ced1", "bank_side_pim": "#ff8c00",
        "micro_bump": "#daa520", "tsv": "#ffd700", "peripheral_logic": "#ba55d3",
        "bank_array": "#4169e1",
        "labels": "#ffffff",
    }
    entries = []
    for name, (layer, datatype) in LAYERS.items():
        entries.append((name, layer, datatype, colors[name]))
    die_colors = ("#4169e1", "#1e90ff", "#4682b4", "#6495ed")
    for die in range(cfg["dram_dies_per_stack"]):
        entries.append((f"dram_die_{die}", 100 + die, 0, die_colors[die % len(die_colors)]))
    xml = ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", "<layer-properties>"]
    for name, layer, datatype, color in entries:
        xml.extend([
            "  <properties>", f"    <name>{name}</name>", f"    <source>{layer}/{datatype}@1</source>",
            f"    <frame-color>{color}</frame-color>", f"    <fill-color>{color}</fill-color>",
            "    <visible>true</visible>", "  </properties>",
        ])
    xml.append("</layer-properties>")
    path.write_text("\n".join(xml) + "\n", encoding="utf-8")


def compare_models(sait: dict[str, str], system: dict[str, str], dramsim: configparser.ConfigParser,
                   cfg: dict[str, Any]) -> list[dict[str, Any]]:
    ds = dramsim["dram_structure"]
    dt = dramsim["timing"]
    comparisons = [
        ("physical channels", cfg["physical_channels_per_stack"], int(dramsim["system"]["channels"]), "standard/config chosen"),
        ("channel width", cfg["channel_width_bits"], int(dramsim["system"]["bus_width"]), "standard/config chosen"),
        ("bank groups", int(sait["NUM_BANK_GROUPS"]), int(ds["bankgroups"]), "SAIT chosen"),
        ("banks", int(sait["NUM_BANKS"]), int(ds["bankgroups"]) * int(ds["banks_per_group"]), "SAIT chosen"),
        ("rows", int(sait["NUM_ROWS"]), int(ds["rows"]), "SAIT chosen for project compatibility"),
        ("columns", int(sait["NUM_COLS"]), int(ds["columns"]), "SAIT chosen for project compatibility"),
        ("burst length", int(sait["BL"]), int(ds["BL"]), "SAIT chosen"),
        ("bank-level refresh interval", int(sait["tREFISB"]), int(dt["tREFIb"]),
         "SAIT tREFISB chosen; DRAMsim3 tREFIb retained as cross-check"),
        ("address mapping", system.get("ADDRESS_MAPPING_SCHEME", "not set"),
         dramsim["system"]["address_mapping"], "project Scheme8 chosen for simulator compatibility"),
        ("logical vs physical channels", int(system.get("NUM_CHANS", cfg["logical_channel_mapping"]["logical_channels"])),
         int(dramsim["system"]["channels"]), f"kept separate via {cfg['logical_channel_mapping']['type']}"),
    ]
    for key in ("tRCDRD", "tRCDWR", "tRP", "tRAS", "tRFC", "tREFI"):
        comparisons.append((key, int(sait[key]), int(dt[key]), "SAIT chosen for simulator compatibility"))
    return [{"parameter": name, "selected_or_sait": left, "dramsim3": right,
             "match": left == right, "selection": reason} for name, left, right, reason in comparisons]


def write_reports(cfg: dict[str, Any], provenance: dict[str, Any], comparisons: list[dict[str, Any]],
                  manifest: dict[str, Any], upstream_differences: dict[str, dict[str, str]], output: Path) -> None:
    mismatches = [item for item in comparisons if not item["match"]]
    summary = f"""# HBM2 PIM Architecture Model

> **{DISCLAIMER}**

Generated: {datetime.now(timezone.utc).isoformat()}

## Structure

- HBM2 stacks: {manifest['stack_count']}
- DRAM dies per stack: {manifest['dram_dies']}
- Physical channels per stack: {manifest['physical_channels_per_stack']} x {cfg['channel_width_bits']}-bit = {manifest['physical_channels_per_stack'] * cfg['channel_width_bits']}-bit
- Pseudo-channel mode: {cfg['pseudo_channel_mode']} ({manifest['pseudo_channels_per_stack']} pseudo-channels/stack when enabled)
- Logical simulator partitions: {cfg['logical_channel_mapping']['logical_channels']} (`{cfg['logical_channel_mapping']['type']}`)
- Banks per physical channel: {manifest['banks_per_channel']}
- Bank-side PIM blocks per physical channel: {manifest['pim_blocks_per_channel']}
- Bank-to-PIM mapping: {json.dumps(manifest['bank_to_pim_mapping'], ensure_ascii=False)}
- TSV groups: {manifest['tsv_groups']}
- RTL functional blocks detected: {len(manifest['rtl_blocks'])}

The 64 logical simulator channels are **not** represented as 64 physical HBM2 channels. The default model retains the standard eight physical channels and records the 64-way simulator partition separately.

## Evidence boundaries

- Standard-derived: stack interface organization (8 physical channels, 128-bit/channel, 1024-bit total).
- SAIT/project-derived: bank, row/column, timing and PIM block parameters.
- DRAMsim3: independent open-source cross-check for organization, timing, refresh and address mapping.
- RTL-derived: module names and parameter expressions only; no gate placement or routed wire is claimed.
- Estimated/illustrative: all package dimensions, die thicknesses, bump/TSV sizes and floorplan placement.

No public manufacturing HBM2 DRAM-cell GDS, PHY GDS, exact TSV floorplan, or signoff layout is used. See `parameter_provenance.json` and `cross_validation_report.md`.
"""
    output.joinpath("model_summary.md").write_text(summary, encoding="utf-8")
    rows = "\n".join(
        f"| {x['parameter']} | {x['selected_or_sait']} | {x['dramsim3']} | {'yes' if x['match'] else 'no'} | {x['selection']} |"
        for x in comparisons)
    cross = f"""# SAIT / DRAMsim3 HBM2 Cross-validation

| Parameter | Selected/SAIT | DRAMsim3 | Match | Resolution |
|---|---:|---:|:---:|---|
{rows}

Mismatches: {len(mismatches)}. Differences are retained and explained rather than silently normalized.

## Local SAIT device configuration versus pinned upstream

Changed keys: {json.dumps(upstream_differences, ensure_ascii=False, indent=2)}

An empty object proves that the parsed local device values match the vendored upstream snapshot at the pinned commit. Comments and formatting are intentionally ignored. Thermal-capable DRAMsim3 behavior is a validation reference only; this visualization does not perform thermal simulation.
"""
    output.joinpath("cross_validation_report.md").write_text(cross, encoding="utf-8")
    output.joinpath("parameter_provenance.json").write_text(
        json.dumps({"disclaimer": DISCLAIMER, "parameters": provenance}, indent=2, ensure_ascii=False), encoding="utf-8")
    output.joinpath("generation_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=DISCLAIMER)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    config_path = args.config.resolve()
    output = args.output.resolve()
    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    sait_path = ROOT / cfg["sait_device_file"]
    sait_upstream_path = ROOT / cfg["sait_upstream_reference_file"]
    system_path = ROOT / cfg["sait_system_file"]
    dramsim_path = ROOT / cfg["dramsim3_reference_file"]
    sait, sait_lines = read_simple_ini(sait_path)
    sait_upstream, _ = read_simple_ini(sait_upstream_path)
    system, system_lines = read_simple_ini(system_path)
    dramsim = read_dramsim(dramsim_path)
    rtl = detect_rtl_modules(ROOT, cfg["rtl_modules"])
    missing = sorted(set(cfg["rtl_modules"]) - set(rtl))
    output.mkdir(parents=True, exist_ok=True)
    facts = {"banks": int(sait["NUM_BANKS"]), "pim_blocks": int(sait["NUM_PIM_BLOCKS"])}
    provenance = build_provenance(cfg, sait, sait_lines, system, system_lines, dramsim, rtl)
    comparisons = compare_models(sait, system, dramsim, cfg)
    all_sait_keys = set(sait) | set(sait_upstream)
    upstream_differences = {
        key: {"local": sait.get(key, "<missing>"), "upstream": sait_upstream.get(key, "<missing>")}
        for key in sorted(all_sait_keys) if sait.get(key) != sait_upstream.get(key)
    }
    gds_path = output / "hbm2_pim_architecture.gds"
    manifest = build_gds(cfg, facts, rtl, gds_path)
    manifest.update({
        "disclaimer": DISCLAIMER, "config": config_path.as_posix(), "missing_requested_rtl_modules": missing,
        "logical_channel_mapping": cfg["logical_channel_mapping"], "gds": gds_path.as_posix(),
    })
    write_scad(cfg, facts, rtl, output / "hbm2_pim_architecture.scad")
    write_layerstack(cfg, output / "hbm2_pim_architecture.layerstack")
    write_layer_properties(cfg, output / "hbm2_pim_architecture.lyp")
    write_reports(cfg, provenance, comparisons, manifest, upstream_differences, output)
    thermal_metadata = {
        "status": "metadata_only_no_thermal_solver",
        "source": "umd-memsys/DRAMsim3 HBM2_8Gb_x128.ini",
        "upstream_commit_hash": DRAMSIM_COMMIT,
        "stack": {
            "stack_count": cfg["stack_count"],
            "dram_dies_per_stack": cfg["dram_dies_per_stack"],
            "configured_die_thickness_um": cfg["geometry_um"]["dram_die_thickness"],
            "configured_die_gap_um": cfg["geometry_um"]["die_gap"],
        },
        "dramsim3_power_reference": {key: as_number(value) for key, value in dramsim["power"].items()},
        "warning": "Power values are source metadata only. Geometry is estimated/illustrative and no temperature field is computed.",
    }
    output.joinpath("thermal_metadata.json").write_text(
        json.dumps(thermal_metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Generated HBM2 architecture in {output}")
    if missing:
        print("WARNING: requested RTL modules not found: " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
