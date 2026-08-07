# RTL-to-3D power mapping adapter

This adapter converts synthesis area, physical placement, and VCD/SAIF-derived
block power into the spatial power input consumed by the HBM2 3-D thermal
solver. It does not depend on the RTL being complete: the checked synthetic
fixture exercises the same contract that final tool reports will use.

## Data flow

```text
Yosys/OpenROAD area CSV ─┐
OpenROAD placement CSV ──┼─ collect_rtl_physical_inputs.py
VCD/SAIF + power CSV ────┘       │ normalized_input.json
                                 ▼
                         rtl_to_3d_power_map.py
                                 │ mapped_power.json
                                 ▼
                         run_hbm2_thermal.py
                                 │ summary.json / power map / temperature field
                                 ▼
                         run_hbm2_hardware_cost.py
```

VCD or SAIF contains switching activity, not physical power by itself. A power
tool must combine activity with the synthesized netlist, cell library,
capacitance, voltage, and frequency. Therefore `block_power.csv` is the numeric
power input and the VCD/SAIF path is retained as provenance. Treating raw toggle
count as watts would be dimensionally invalid and is intentionally unsupported.

## Replaceable input reports

Pass a manifest like
`verification/rtl_to_3d/fixtures/report_manifest.json`. Relative paths are
resolved from the manifest directory.

`synthesis_area.csv`:

```csv
instance,module,area_um2
top.logic_pcu,logic_pcu,4800000
```

`placement.csv` contains logic-die blocks placed by OpenROAD:

```csv
instance,x_um,y_um,width_um,height_um
top.logic_pcu,400,1000,2400,2000
```

`block_power.csv` contains power derived with VCD/SAIF activity. Optional
`stack,die,channel,bank` columns disambiguate DRAM targets when hierarchy names
do not encode them.

```csv
instance,dynamic_W,leakage_W,toggle_count,duration_s,activity_format,stack,die,channel,bank
top.logic_pcu,1.8,0.2,180000,0.001,VCD,,,,
```

The normalized JSON contract is in `input_schema.json`. Units are fixed to
micrometres, square micrometres, and watts; implicit conversion is rejected.

## Coordinates and mapping

- Origin is the lower-left corner of each die; x points right and y points up.
- Logic blocks use the OpenROAD rectangle directly.
- Bank-side PIM blocks map to the corresponding physical HBM channel and bank
  tile. The default HBM2 model uses 8 channels and a 4 x 4 bank grid per channel.
- `stack` and `die` are zero-based.
- Rules are ordered regular expressions in `mapping_rules.json`; the first match
  wins. Add a rule whenever RTL hierarchy naming changes.
- Unknown blocks fail by default. `--allow-unmapped` exists for diagnosis only;
  the thermal solver still rejects any input containing unmapped blocks.

The adapter reports synthesis area separately from the mapped rectangle area.
An area mismatch does not silently rescale power; it is recorded as a warning.
Power density is based on the mapped rectangle.

## Run

From PowerShell:

```powershell
.\tools\run_rtl_to_3d_analysis.ps1
```

This performs collection, mapping, 3-D thermal analysis, unit tests, and the
hardware-cost analysis using the newly generated thermal summary. To use real
reports, replace the four paths in a manifest and run:

```powershell
.\tools\run_rtl_to_3d_analysis.ps1 -Manifest path\to\report_manifest.json
```

Important outputs:

- `output/rtl_to_3d/normalized_input.json`
- `output/rtl_to_3d/mapped_power.json`
- `output/rtl_to_3d/mapping_report.md`
- `output/hbm2_thermal/rtl_mapped/summary.json`
- `output/hbm2_thermal/rtl_mapped/power_map.png`
- `output/hbm2_thermal/rtl_mapped/temperature_heatmap.png`
- `output/hbm2_hardware_cost/rtl_mapped/hardware_cost_report.md`

## Validation gates

The run fails on unsupported units, negative or non-finite values, duplicate
instances, missing provenance, missing power rows, unknown modules, invalid
stack/die/channel/bank indices, rectangles outside the die, or loss of power
during mapping/rasterization. Tests also demonstrate the diagnostic unmapped
mode and derived bank coordinates.

The result remains architectural until OpenROAD placement, a characterized cell
library, extracted parasitics, real workload VCD/SAIF, package material data, and
measurement calibration are supplied. It is not manufacturing or thermal
signoff.
