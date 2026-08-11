# OpenROAD Physical Inputs Checklist

To turn the RTL in this repository into a real `output/output.gds`, OpenROAD needs:

1. A top module name
   - Current target: `logic_die_64ch_reduction_top`
2. Synthesizable RTL sources
   - Present in `rtl/`
3. A technology LEF
4. A standard-cell LEF
5. A standard-cell liberty file
6. PDK tech files for routing and DRC
7. A constraint file, usually `SDC`
8. An OpenROAD script that performs:
   - import
   - floorplan
   - placement
   - CTS
   - routing
   - extraction / signoff checks

Repository status as of now:

- RTL sources: present
- synthesis scaffold: present
- OpenROAD flow scaffold: present
- real PDK-backed physical-design inputs: missing

