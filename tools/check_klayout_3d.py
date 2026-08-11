"""KLayout-headless smoke test for the gds3xtrude integration."""

import shutil
import sys
import os

import pya
from gds3xtrude.openscad import render_scad_to_file  # noqa: F401
from gds3xtrude.types import Material  # noqa: F401


print(f"KLayout Python: {sys.version.split()[0]}")
print("gds3xtrude: OK")
print(f"OpenSCAD: {shutil.which('openscad') or 'not on PATH'}")

gds_path = os.environ.get("STOB_3D_SMOKE_GDS")
stack_path = os.environ.get("STOB_3D_SMOKE_STACK")
scad_path = os.environ.get("STOB_3D_SMOKE_SCAD")
if gds_path and stack_path and scad_path:
    layout = pya.Layout()
    layout.read(gds_path)
    top_cell = layout.top_cell()
    render_scad_to_file(layout, top_cell, stack_path, scad_path, centered=True)
    print(f"OpenSCAD model: {scad_path}")
