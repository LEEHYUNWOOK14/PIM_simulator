# HBM2 PIM architectural thermal pipeline

This pipeline runs independently of the changing RTL. It is a research/architecture model, **not a vendor HBM2 layout, calibrated silicon model, or signoff result**.

## Run

```powershell
.\tools\run_hbm2_thermal.ps1 -Transient -Profile bank_pim_hotspot
```

User events use `design/thermal/power_events_example.csv`; fields identify time interval, logic/DRAM target, stack, die, physical channel, bank, and watts. `design/thermal/rtl_floorplan_mapping.json` reserves the later VCD/SAIF/OpenROAD adapter boundary without coupling the solver to RTL.

The finite-volume solver uses SI units, anisotropic layer conductivity, lateral/vertical conduction, heat capacity, sparse steady-state solve, and backward-Euler transient solve. The default model contains substrate, interposer, base logic, eight DRAM dies, inter-die bump/underfill planes, TSV effective conductivity, TIM, and copper lid. Eight physical channels and sixteen banks per channel map onto the 32×16 grid. The project's 64 logical simulator partitions are deliberately not treated as physical HBM channels.

Inputs are in `design/thermal/`. Each uncertain value includes a classification and source/confidence metadata. Public references and pinned external solvers are listed in `references/thermal/SOURCES.md`. The HotSpot adapter exports a floorplan and power trace with `python tools/export_hbm2_hotspot.py`; it does not claim numerical equivalence to the 3-D reference model.

Outputs under `output/hbm2_thermal/` include JSON/CSV summaries, compressed temperature fields, VTK, PNG heatmaps, OpenSCAD stacks, and KLayout-readable temperature-bin GDS. Run `python tools/validate_hbm2_thermal.py` for equation residual, symmetry, zero-power, grid/timestep convergence, and 4/8/12Hi checks. Run `python tools/sweep_hbm2_thermal.py` for best/nominal/worst and parameter sweeps.

Absolute temperatures are conditional on illustrative power, package geometry, effective TSV/bump properties, TIM and convection. Use them for relative architecture comparison only. Before hardware prediction, replace these with measured/vendor data and correlate against a calibrated solver or test vehicle.

열 이외의 면적·패키지·수율·전력/성능 비용은 [`hardware_cost/README.md`](../hardware_cost/README.md)의 독립 파이프라인에서 분석한다.
