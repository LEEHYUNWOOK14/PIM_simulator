# RTL-to-3D power mapping implementation report

## Outcome

The RTL-to-3D adapter is connected end to end:

```text
synthesis area + OpenROAD placement + VCD/SAIF-derived power
  -> normalized block contract
  -> HBM2 stack coordinates and power density
  -> finite-volume 3-D thermal input
  -> thermal result
  -> full hardware-cost analysis
```

The checked run uses synthetic reports because the RTL and physical flow are
still changing. The same manifest contract accepts final reports without code
changes.

## Synthetic verification result

| Item | Result |
|---|---:|
| Input blocks | 5 |
| Mapped blocks | 5 |
| Unmapped blocks | 0 |
| Input power | 4.0 W |
| Mapped power | 4.0 W |
| Power conservation error | 0.0 W |
| Thermal grid | 32 x 16 x 21 |
| Peak temperature | 322.581811 K |
| Peak rise above 300 K ambient | 22.581811 K |
| Hotspot | DRAM die 0, grid (0, 1) |

The mapped hotspot is intentionally different from the old uniform reference:
bank-side PIM power is localized rather than averaged over every DRAM die.

## Verification evidence

Seven adapter tests pass:

1. fixture mapping and exact power conservation;
2. HBM channel/bank coordinate derivation;
3. rejection of unsupported units;
4. rejection of out-of-die rectangles;
5. detection and default rejection of unmapped RTL blocks;
6. assembly of replaceable synthesis/placement/activity/power reports;
7. exact power conservation after thermal-grid rasterization.

The mapped thermal summary also passes the hardware-cost validator, including
formula checks, structural monotonicity, source resolution, output presence, and
2,000-sample deterministic uncertainty analysis. The hotter non-uniform thermal
reference revealed a previously unhandled case where no design is feasible in
some Monte Carlo samples. The pipeline now reports that state explicitly instead
of failing; the synthetic run has a 3.05% no-feasible probability.

## Files to replace after RTL completion

Only the paths in the report manifest need to change:

- synthesis area CSV from Yosys/OpenROAD;
- logic-block placement CSV from OpenROAD;
- workload VCD or SAIF;
- block power CSV generated from that activity, the synthesized netlist, cell
  library, voltage, frequency, and parasitics.

Raw VCD/SAIF toggle counts are not converted directly to watts. That conversion
requires a power-analysis tool and technology data; bypassing it would produce a
dimensionally valid-looking but physically unsupported heat input.

## Command

```powershell
.\tools\run_rtl_to_3d_analysis.ps1 -Manifest path\to\report_manifest.json
```

Detailed input formats, coordinate rules, output paths, and limitations are in
`design/rtl_to_3d/README.md`.

> These are architectural synthetic results, not calibrated silicon,
> manufacturing, reliability, or thermal-signoff results.
