# OpenROAD + KLayout Environment Setup

This workspace is set up so the final OpenROAD layout can be opened in KLayout
for zooming, panning, layer inspection, and manual editing.

## Goal

1. Generate the final layout in OpenROAD.
2. Place the result at `output/output.gds`.
3. Open that GDS in KLayout.
4. Inspect and edit the layout if needed.
5. Re-run verification after any edits.

## What this repository provides

- [`tools/open_klayout.ps1`](../tools/open_klayout.ps1)
- [`tools/open_klayout.cmd`](../tools/open_klayout.cmd)
- [`tools/open_output_gds.cmd`](../tools/open_output_gds.cmd)
- [`tools/check_output_gds.ps1`](../tools/check_output_gds.ps1)

These launchers default to:

```text
output/output.gds
```

## Recommended output layout

```text
<workspace>
  output/
    output.gds
    output.def
    output.lef
    output.v
    tech.lyt
    layers.lyp
```

`output.gds` is enough to open the design.
`output.def`, `output.lef`, `tech.lyt`, and `layers.lyp` make inspection easier.

## How to launch

### One-time 3D dependency setup

KLayout embeds its own Python interpreter, so installing `gds3xtrude` into the
project `.venv` does not make it available to KLayout. Run this once (and again
after changing the KLayout Python version):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\setup_klayout_3d.ps1
```

This installs `requirements-klayout-3d.txt` into KLayout's embedded Python
`site-packages`, installs OpenSCAD when needed, and runs a headless import test.
Restart KLayout afterward, open the GDS, and select `Tools > gds3xtrude`.
When prompted for a layer stack, choose `design/stob.layerstack`.

### PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\open_klayout.ps1
```

To verify the expected GDS first:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check_output_gds.ps1
```

### Double-click launcher

Run `tools/open_output_gds.cmd` for a one-click entrypoint.

## What you can do in KLayout

- Zoom in and out with the mouse wheel
- Pan by dragging
- Toggle layers
- Inspect hierarchy
- Make manual edits

Any edited layout should still be checked again with DRC/LVS and the rest of
the signoff flow.

## RTL reference points

These RTL files describe the logic-die structure that maps into the final
layout:

- `rtl/logic_die_64ch_reduction_top.sv`
- `rtl/hierarchical_reduction_path.sv`
- `rtl/shared_fp16_reduction_cluster.sv`
- `rtl/shared_fp16_pipeline_fabric.sv`
- `rtl/bank_local_reduction_buffer.sv`

## Notes

- If KLayout is not installed, the launcher prints a clear error.
- If `output/output.gds` does not exist yet, the launcher stops and tells you
  which file is missing.
- Large GDS files can take a while to load the first time.
