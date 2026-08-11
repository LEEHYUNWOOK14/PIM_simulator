# Source-traceable HBM2 PIM architecture model

> **HBM2 PIM architectural visualization — not signoff layout**

This model separates four kinds of evidence:

1. JEDEC HBM2 organization defines the eight 128-bit physical channels and 1024-bit stack interface.
2. SAITPublic/PIMSimulator supplies project-compatible bank, row/column, timing and PIM-block parameters.
3. DRAMsim3 `HBM2_8Gb_x128.ini` independently checks organization, timing, refresh and address mapping.
4. Local RTL contributes module names and parameter expressions as functional blocks only.

It does not contain a manufacturing DRAM cell array, HBM PHY, exact TSV floorplan or signoff GDS. Package dimensions, die thickness, bump size, TSV size and block placement are explicitly classified as `estimated` or `illustrative`.

## Generate and validate

From the repository root:

```powershell
.\tools\generate_hbm2_architecture.ps1
```

The command performs configuration and RTL read-only extraction, creates GDS/layerstack/native SCAD/reports, validates hierarchy/counts/provenance, loads the GDS in headless KLayout and evaluates the SCAD with OpenSCAD.

Use `-SkipKLayout` or `-SkipOpenSCAD` only on machines without those viewers. Install dependencies with:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\tools\setup_klayout_3d.ps1
```

## Open the model

```powershell
.\tools\open_hbm2_architecture.ps1 -View gds
.\tools\open_hbm2_architecture.ps1 -View scad
```

KLayout shows the 2D hierarchy and material layers. OpenSCAD shows the separated 8Hi stack, vertical TSV columns, micro-bumps, interposer and base logic die.

## Configuration and channel semantics

Edit `design/hbm2_architecture.json`. The default is one 8Hi HBM2 stack with eight 128-bit physical channels. `logical_channel_mapping` records the project's 64 channels as `simulator_only_logical_partition`; they are not drawn as 64 physical HBM2 channels.

Supported explicit mappings are `multiple_hbm2_stacks`, `pseudo_channel_split`, `simulator_only_logical_partition` and `research_extension`. For a standard multiple-stack mapping, set logical channels to `stack_count × 8`. A contradictory multiple-stack mapping fails validation.

## Outputs

All outputs are isolated below `output/hbm2_arch/`:

- `hbm2_pim_architecture.gds`: hierarchical 2D architecture GDS
- `hbm2_pim_architecture.layerstack`: gds3xtrude material stack
- `hbm2_pim_architecture.lyp`: KLayout layer names and colors
- `hbm2_pim_architecture.scad`: native 3D stack
- `hbm2_pim_architecture.csg`: OpenSCAD-evaluated artifact
- `model_summary.md`: interpretation and evidence boundaries
- `parameter_provenance.json`: source, commit, location, confidence and classification per value
- `cross_validation_report.md`: SAIT/DRAMsim3 comparison and selection rationale
- `generation_manifest.json`: generated quantities and hierarchy
- `thermal_metadata.json`: pinned DRAMsim3 power metadata and explicit no-solver warning

## Sources and licenses

- SAITPublic/PIMSimulator, commit `3703d1f19c8f027360cc33a3243eb271e3bb6898`. Its local license restricts use to non-commercial, personal, academic or research purposes. See `LICENSE-PIMSimulator`.
- umd-memsys/DRAMsim3, commit `29817593b3389f1337235d63cac515024ab8fd6e`, MIT License. A source-identified snapshot is stored at `references/hbm2/DRAMsim3_HBM2_8Gb_x128.ini`.
- JEDEC JESD235-family structure is referenced but copyrighted standard text is not redistributed.

Machine-readable source records are in `references/hbm2/SOURCES.json`.

## Thermal and physical-layout boundary

DRAMsim3 is thermal-capable, but this generator does not run a thermal solver. Colors and heights are not temperature results. No public manufacturing HBM2 DRAM-cell GDS, PHY GDS, exact TSV floorplan or signoff layout is included or claimed.

## Replacing the logic placeholder with OpenROAD GDS

The architecture GDS isolates the placeholder in `HBM2_BASE_LOGIC_DIE`. When a real OpenROAD result exists:

1. complete RTL-to-GDS with verified PDK, Liberty, LEF and signoff GDS libraries;
2. import the OpenROAD top cell as a separate library without flattening it;
3. replace the functional-block reference inside `HBM2_BASE_LOGIC_DIE`;
4. retain package, DRAM, TSV and bump cells as architectural layers;
5. state that the HBM package portion remains non-signoff.

Do not translate synthetic functional rectangles into standard cells or claim routed connectivity from their positions.
