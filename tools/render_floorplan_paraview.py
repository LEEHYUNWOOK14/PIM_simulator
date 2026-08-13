#!/usr/bin/env python3
"""Render a reproducible ParaView paper image from the exported VTU."""
from __future__ import annotations

import argparse
from pathlib import Path

from paraview.simple import (ColorBy, GetActiveViewOrCreate, GetColorTransferFunction,
                             GetOpacityTransferFunction, Hide, OpenDataFile, SaveScreenshot,
                             Show, Threshold, _DisableFirstRenderCameraReset)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True); parser.add_argument("--output", required=True)
    parser.add_argument("--title", default="Modeled HBM stack temperature — not signoff")
    args = parser.parse_args(); _DisableFirstRenderCameraReset()
    source = OpenDataFile(str(Path(args.input).resolve()))
    view = GetActiveViewOrCreate("RenderView"); view.ViewSize = [2400, 1800]; view.Background = [0.035, 0.04, 0.055]; view.OrientationAxesVisibility = 1
    stack = Threshold(Input=source); stack.Scalars = ["CELLS", "object_type"]; stack.LowerThreshold = -0.1; stack.UpperThreshold = 0.1
    stack_display = Show(stack, view); stack_display.Representation = "Surface With Edges"; stack_display.Opacity = 0.82; stack_display.EdgeColor = [0.18, 0.18, 0.22]
    ColorBy(stack_display, ("CELLS", "temperature_K")); lut = GetColorTransferFunction("temperature_K"); lut.RGBPoints = [300.0, 0.0015, 0.0005, 0.0139, 305.0, 0.3415, 0.0623, 0.4294, 310.0, 0.7357, 0.2159, 0.3302, 316.0, 0.9884, 0.9984, 0.6449]; lut.RescaleTransferFunction(300.0, 316.0)
    opacity = GetOpacityTransferFunction("temperature_K"); opacity.RescaleTransferFunction(300.0, 316.0); stack_display.SetScalarBarVisibility(view, True)
    tsv = Threshold(Input=source); tsv.Scalars = ["CELLS", "object_type"]; tsv.LowerThreshold = 1.9; tsv.UpperThreshold = 2.1
    tsv_display = Show(tsv, view); tsv_display.Representation = "Wireframe"; tsv_display.LineWidth = 3.0; ColorBy(tsv_display, ("CELLS", "signal_class")); signal_lut = GetColorTransferFunction("signal_class"); signal_lut.RGBPoints = [0, 0.267, 0.005, 0.329, 3, 0.128, 0.567, 0.551, 6, 0.993, 0.906, 0.144]; signal_lut.RescaleTransferFunction(0, 6)
    blocks = Threshold(Input=source); blocks.Scalars = ["CELLS", "object_type"]; blocks.LowerThreshold = 0.9; blocks.UpperThreshold = 1.1
    block_display = Show(blocks, view); block_display.Representation = "Wireframe"; block_display.LineWidth = 2.0; block_display.AmbientColor = [0.2, 1.0, 0.35]; block_display.DiffuseColor = [0.2, 1.0, 0.35]; ColorBy(block_display, None)
    Hide(source, view); view.ResetCamera(); view.CameraPosition = [16000, -19000, 12500]; view.CameraFocalPoint = [4000, 6000, 6000]; view.CameraViewUp = [0, 0, 1]; view.CameraParallelProjection = 1; view.CameraParallelScale = 8500
    view.Update(); SaveScreenshot(str(Path(args.output).resolve()), view, ImageResolution=[2400, 1800], TransparentBackground=0)
    print(f"PARAVIEW_RENDER PASS output={Path(args.output).resolve()}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
