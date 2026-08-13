#!/usr/bin/env python3
"""Create a manifest-driven fixed-macro OpenROAD harness for candidate comparison.

The harness preserves block rectangles and channel connectivity but is not a
gate-level implementation of the RTL modules. It is therefore physical/model
evidence only and cannot provide RTL timing closure or silicon signoff.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CHANNEL_RE = re.compile(r"dram\.channel\[(\d+)]")
ORFS_PLATFORM = "/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd"


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def sanitize(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", value)


def wsl_path(path: Path) -> str:
    resolved = path.resolve()
    if resolved.drive:
        drive = resolved.drive[0].lower()
        relative = resolved.as_posix().split(":", 1)[1]
        return f"/mnt/{drive}{relative}"
    return resolved.as_posix()


def macro_lef(name: str, width: float, height: float, channels: int) -> str:
    lines = [f"MACRO {name}", "  CLASS BLOCK ;", "  ORIGIN 0 0 ;", f"  FOREIGN {name} 0 0 ;", f"  SIZE {width:.6f} BY {height:.6f} ;", "  SYMMETRY X Y ;"]
    step = height / (channels + 1)
    pin_size = min(0.4, max(0.1, step * 0.15))
    for channel in range(channels):
        y = (channel + 1) * step
        for suffix, direction, x in (("IN", "INPUT", 0.0), ("OUT", "OUTPUT", width)):
            x0 = max(0.0, x - pin_size / 2)
            x1 = min(width, x + pin_size / 2)
            lines += [f"  PIN CH{channel}_{suffix}", f"    DIRECTION {direction} ;", "    USE SIGNAL ;", "    PORT", "      LAYER met3 ;", f"        RECT {x0:.6f} {y-pin_size/2:.6f} {x1:.6f} {y+pin_size/2:.6f} ;", "    END", f"  END CH{channel}_{suffix}"]
    lines += ["  OBS", "    LAYER met1 ;", f"      RECT 0 0 {width:.6f} {height:.6f} ;", "    LAYER met2 ;", f"      RECT 0 0 {width:.6f} {height:.6f} ;", "    LAYER met4 ;", f"      RECT 0 0 {width:.6f} {height:.6f} ;", "  END", f"END {name}"]
    return "\n".join(lines)


def tsv_lef(name: str, width: float, height: float, block_count: int) -> str:
    lines = [f"MACRO {name}", "  CLASS BLOCK ;", "  ORIGIN 0 0 ;", f"  FOREIGN {name} 0 0 ;", f"  SIZE {width:.6f} BY {height:.6f} ;", "  SYMMETRY X Y ;"]
    pins = [("TO_LOGIC", "OUTPUT")] + [(f"FROM_B{index}", "INPUT") for index in range(block_count)]
    step = height / (len(pins) + 1)
    for index, (pin, direction) in enumerate(pins, 1):
        y = index * step
        lines += [f"  PIN {pin}", f"    DIRECTION {direction} ;", "    USE SIGNAL ;", "    PORT", "      LAYER met3 ;", f"        RECT 0 {y-0.1:.6f} 0.3 {y+0.1:.6f} ;", "    END", f"  END {pin}"]
    lines += ["  OBS", "    LAYER met1 ;", f"      RECT 0 0 {width:.6f} {height:.6f} ;", "    LAYER met2 ;", f"      RECT 0 0 {width:.6f} {height:.6f} ;", "    LAYER met4 ;", f"      RECT 0 0 {width:.6f} {height:.6f} ;", "  END", f"END {name}"]
    return "\n".join(lines)


def export(manifest_path: str, output_dir: str, scale: float = 0.1) -> dict[str, Any]:
    manifest = json.loads(absolute(manifest_path).read_text(encoding="utf-8-sig"))
    output = absolute(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    channels = len([endpoint for endpoint in manifest["external_endpoints"] if CHANNEL_RE.fullmatch(endpoint)])
    blocks = manifest["blocks"]
    lef_lines = ["VERSION 5.8 ;", "BUSBITCHARS \"[]\" ;", "DIVIDERCHAR \"/\" ;"]
    macro_names = []
    for index, block in enumerate(blocks):
        name = f"STOB_BLOCK_{index}"
        macro_names.append(name)
        lef_lines.append(macro_lef(name, float(block["width_um"]) * scale, float(block["height_um"]) * scale, channels))
    lef_lines.append(tsv_lef("STOB_TSV_ENDPOINT", 3.0, 30.0, len(blocks)))
    lef_lines.append("END LIBRARY")
    (output / "floorplan_macros.lef").write_text("\n\n".join(lef_lines) + "\n", encoding="ascii")

    wires = []
    instances = []
    for channel in range(channels):
        wires.append(f"  wire ch{channel}_to_logic;")
        for index in range(len(blocks)):
            wires.append(f"  wire ch{channel}_from_b{index};")
    for index, block in enumerate(blocks):
        channels_for_block = [int(match.group(1)) for endpoint in block["traffic_endpoints"] if (match := CHANNEL_RE.fullmatch(endpoint))]
        ports = []
        for channel in channels_for_block:
            ports += [f".CH{channel}_IN(ch{channel}_to_logic)", f".CH{channel}_OUT(ch{channel}_from_b{index})"]
        instances.append(f"  {macro_names[index]} u_block_{index} ({', '.join(ports)});")
    for channel in range(channels):
        ports = [f".TO_LOGIC(ch{channel}_to_logic)"] + [f".FROM_B{index}(ch{channel}_from_b{index})" for index in range(len(blocks))]
        instances.append(f"  STOB_TSV_ENDPOINT u_tsv_ch{channel} ({', '.join(ports)});")
    verilog = ["module STOB_FLOORPLAN_PROXY();", *wires, *instances, "endmodule"]
    (output / "floorplan_proxy.v").write_text("\n".join(verilog) + "\n", encoding="ascii")

    data_bundles = {}
    for bundle in manifest["tsv_bundles"]:
        match = CHANNEL_RE.fullmatch(bundle["source"])
        if match and bundle["signal_class"] == "data":
            data_bundles[int(match.group(1))] = bundle
    orientation = {"N": "R0", "S": "R180", "E": "R90", "W": "R270", "FN": "MY", "FS": "MX", "FE": "MXR90", "FW": "MYR90"}
    tcl = [
        f"read_lef {ORFS_PLATFORM}/lef/sky130_fd_sc_hd.tlef",
        f"read_lef {wsl_path(output / 'floorplan_macros.lef')}",
        f"read_liberty {ORFS_PLATFORM}/lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
        f"read_verilog {wsl_path(output / 'floorplan_proxy.v')}",
        "link_design STOB_FLOORPLAN_PROXY",
        f"initialize_floorplan -die_area {{0 0 {float(manifest['die']['width_um'])*scale:.6f} {float(manifest['die']['height_um'])*scale:.6f}}} -core_area {{2 2 {float(manifest['die']['width_um'])*scale-2:.6f} {float(manifest['die']['height_um'])*scale-2:.6f}}} -site unithd",
        f"source {ORFS_PLATFORM}/make_tracks.tcl",
    ]
    expected_placements = []
    for index, block in enumerate(blocks):
        tcl.append(f"place_inst -name u_block_{index} -location {{{float(block['x_um'])*scale:.6f} {float(block['y_um'])*scale:.6f}}} -orientation {orientation[block['orientation']]} -status FIRM")
        expected_placements.append({
            "instance": f"u_block_{index}",
            "x_um": float(block["x_um"]) * scale,
            "y_um": float(block["y_um"]) * scale,
            "orientation": block["orientation"],
            "kind": "conceptual_logic_block",
        })
    for channel, bundle in sorted(data_bundles.items()):
        x = (float(bundle["x_um"]) + (int(bundle["columns"]) - 1) * float(bundle["pitch_um"]) / 2) * scale - 1.5
        y = (float(bundle["y_um"]) + (int(bundle["rows"]) - 1) * float(bundle["pitch_um"]) / 2) * scale - 15.0
        tcl.append(f"place_inst -name u_tsv_ch{channel} -location {{{x:.6f} {y:.6f}}} -orientation R0 -status FIRM")
        expected_placements.append({
            "instance": f"u_tsv_ch{channel}", "x_um": x, "y_um": y,
            "orientation": "N", "kind": "channel_data_tsv_endpoint_proxy",
        })
    tcl += [
        f"source {ORFS_PLATFORM}/setRC.tcl",
        "set_routing_layers -signal met2-met5 -clock met3-met5",
        "global_route -allow_congestion -guide_file " + wsl_path(output / "route.guide") + " -congestion_report_file " + wsl_path(output / "congestion.rpt"),
        "report_wire_length -global_route -summary -file " + wsl_path(output / "wire_length.rpt"),
        "check_placement -verbose -report_file_name " + wsl_path(output / "placement_check.rpt"),
        "write_def " + wsl_path(output / "floorplan_proxy.def"),
        "write_db " + wsl_path(output / "floorplan_proxy.odb"),
        "puts \"STOB_OPENROAD_PROXY PASS\"",
        "exit",
    ]
    (output / "run_openroad.tcl").write_text("\n".join(tcl) + "\n", encoding="utf-8")
    metadata = {
        "status": "GENERATED", "manifest": str(absolute(manifest_path)), "scale": scale,
        "die_um_in_proxy": [float(manifest["die"]["width_um"]) * scale, float(manifest["die"]["height_um"]) * scale],
        "blocks": [{"instance": block["instance"], "proxy_instance": f"u_block_{index}", "macro": macro_names[index], "classification": block["classification"]} for index, block in enumerate(blocks)],
        "tsv_endpoints": channels,
        "expected_placements": expected_placements,
        "evidence_class": "modeled physical proxy",
        "limitations": ["not synthesized RTL gates", "no Liberty timing model for conceptual macros", "no signoff PDN/IR-drop", "routing reflects manifest connectivity only"]
    }
    (output / "proxy_manifest.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"OPENROAD_PROXY_EXPORTED blocks={len(blocks)} channels={channels} output={output}")
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--scale", type=float, default=0.1)
    args = parser.parse_args()
    export(args.manifest, args.output, args.scale)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
