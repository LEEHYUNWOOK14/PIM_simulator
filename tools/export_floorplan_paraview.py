#!/usr/bin/env python3
"""Export the modeled HBM stack, temperature field, blocks, and TSVs as VTU."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SIGNAL = {"data": 0, "command_address": 1, "clock": 2, "power": 3, "ground": 4, "spare": 5, "unknown": 6}


def absolute(path: str | Path) -> Path:
    value = Path(path); return value if value.is_absolute() else ROOT / value


def add_array(parent: ET.Element, name: str, values, kind: str = "Float64", components: int | None = None) -> None:
    attributes = {"type": kind, "Name": name, "format": "ascii"}
    if components: attributes["NumberOfComponents"] = str(components)
    node = ET.SubElement(parent, "DataArray", attributes)
    node.text = " ".join(str(value) for value in values)


def write_vtu(path: Path, manifest: dict, temperature: np.ndarray, z_scale: float) -> dict:
    nz, ny, nx = temperature.shape
    widths = [180.0, 100.0, 100.0] + sum(([15.0, 32.0] for _ in range(8)), []) + [50.0, 500.0]
    if len(widths) != nz: raise ValueError(f"temperature has {nz} layers but geometry defines {len(widths)}")
    die_w, die_h = float(manifest["die"]["width_um"]), float(manifest["die"]["height_um"])
    xs = np.linspace(0, die_w, nx + 1); ys = np.linspace(0, die_h, ny + 1); zs = np.r_[0.0, np.cumsum(widths)] * z_scale
    points = [(x, y, z) for z in zs for y in ys for x in xs]
    def point_index(z, y, x): return (z * (ny + 1) + y) * (nx + 1) + x
    connectivity, offsets, types = [], [], []
    cell_temperature, object_type, signal_class, diameter_um = [], [], [], []
    for z in range(nz):
        for y in range(ny):
            for x in range(nx):
                connectivity += [point_index(z,y,x), point_index(z,y,x+1), point_index(z,y+1,x+1), point_index(z,y+1,x), point_index(z+1,y,x), point_index(z+1,y,x+1), point_index(z+1,y+1,x+1), point_index(z+1,y+1,x)]
                offsets.append(len(connectivity)); types.append(12); cell_temperature.append(float(temperature[z,y,x])); object_type.append(0); signal_class.append(-1); diameter_um.append(0.0)
    logic_bottom, logic_top = zs[2], zs[3]
    for block in manifest["blocks"]:
        base = len(points); x0=float(block["x_um"]); y0=float(block["y_um"]); x1=x0+float(block["width_um"]); y1=y0+float(block["height_um"])
        points += [(x0,y0,logic_bottom),(x1,y0,logic_bottom),(x1,y1,logic_bottom),(x0,y1,logic_bottom),(x0,y0,logic_top),(x1,y0,logic_top),(x1,y1,logic_top),(x0,y1,logic_top)]
        connectivity += list(range(base,base+8)); offsets.append(len(connectivity)); types.append(12)
        cx=min(nx-1,max(0,int((x0+x1)/2/die_w*nx))); cy=min(ny-1,max(0,int((y0+y1)/2/die_h*ny)))
        cell_temperature.append(float(temperature[2,cy,cx])); object_type.append(1); signal_class.append(-1); diameter_um.append(0.0)
    tsv_top = zs[19]
    for bundle in manifest["tsv_bundles"]:
        for column in range(int(bundle["columns"])):
            for row in range(int(bundle["rows"])):
                x=float(bundle["x_um"])+column*float(bundle["pitch_um"]); y=float(bundle["y_um"])+row*float(bundle["pitch_um"]); base=len(points)
                points += [(x,y,logic_top),(x,y,tsv_top)]; connectivity += [base,base+1]; offsets.append(len(connectivity)); types.append(3)
                cx=min(nx-1,max(0,int(x/die_w*nx))); cy=min(ny-1,max(0,int(y/die_h*ny)))
                cell_temperature.append(float(np.max(temperature[2:19,cy,cx]))); object_type.append(2); signal_class.append(SIGNAL[bundle["signal_class"]]); diameter_um.append(float(bundle["diameter_um"]))
    vtk = ET.Element("VTKFile", {"type":"UnstructuredGrid","version":"1.0","byte_order":"LittleEndian"}); grid=ET.SubElement(vtk,"UnstructuredGrid")
    piece=ET.SubElement(grid,"Piece",{"NumberOfPoints":str(len(points)),"NumberOfCells":str(len(types))}); point_node=ET.SubElement(piece,"Points")
    add_array(point_node,"Points",(value for point in points for value in point),components=3)
    cells=ET.SubElement(piece,"Cells"); add_array(cells,"connectivity",connectivity,"Int64"); add_array(cells,"offsets",offsets,"Int64"); add_array(cells,"types",types,"UInt8")
    cell_data=ET.SubElement(piece,"CellData",{"Scalars":"temperature_K"}); add_array(cell_data,"temperature_K",cell_temperature); add_array(cell_data,"object_type",object_type,"Int32"); add_array(cell_data,"signal_class",signal_class,"Int32"); add_array(cell_data,"diameter_um",diameter_um)
    ET.indent(vtk); ET.ElementTree(vtk).write(path,encoding="utf-8",xml_declaration=True)
    return {"path":str(path.relative_to(ROOT)).replace("\\","/"),"points":len(points),"cells":len(types),"z_scale":z_scale}


def export(manifest_path: str, thermal_field: str, output_dir: str) -> dict:
    manifest=json.loads(absolute(manifest_path).read_text(encoding="utf-8-sig")); output=absolute(output_dir); output.mkdir(parents=True,exist_ok=True)
    with np.load(absolute(thermal_field)) as fields: temperature=fields["temperature_K"]
    files=[write_vtu(output/"stack_temperature_physical_z.vtu",manifest,temperature,1.0),write_vtu(output/"stack_temperature_z20_exaggerated.vtu",manifest,temperature,20.0)]
    metadata={"status":"PASS","manifest":str(absolute(manifest_path)),"thermal_field":str(absolute(thermal_field)),"temperature_range_K":[float(temperature.min()),float(temperature.max())],"files":files,"object_type":{"0":"thermal grid cell","1":"conceptual logic block overlay","2":"TSV centerline; use Tube filter with diameter_um"},"signal_class":SIGNAL,"coordinate_units":"um","classification":"modeled/illustrative","gpu_note":"ParaView rendering may use RTX GPU; export and thermal solve are CPU operations","signoff":False}
    (output/"paraview_manifest.json").write_text(json.dumps(metadata,indent=2),encoding="utf-8"); print(f"FLOORPLAN_PARAVIEW_EXPORT PASS cells={files[0]['cells']} output={output}"); return metadata


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("--manifest",required=True); parser.add_argument("--thermal-field",required=True); parser.add_argument("--output",required=True)
    args=parser.parse_args(); export(args.manifest,args.thermal_field,args.output); return 0


if __name__=="__main__": raise SystemExit(main())
