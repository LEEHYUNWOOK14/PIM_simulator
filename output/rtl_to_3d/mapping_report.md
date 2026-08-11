# RTL-to-3D power mapping report

- Status: **PASS**
- Mapped blocks: 5
- Unmapped blocks: 0
- Input power: 4 W
- Mapped power: 4 W
- Conservation error: 0 W

| Instance | 3D target | Rectangle (um) | Area (um^2) | Power (W) | Density (W/mm^2) |
|---|---|---:|---:|---:|---:|
| `top.logic_pcu` | stack 0 / logic | (400,1000) 2400x2000 | 4800000 | 2 | 0.4166667 |
| `top.logic_shared_buffer` | stack 0 / logic | (4200,7200) 1800x2000 | 3600000 | 0.8 | 0.2222222 |
| `top.logic_die_link_arbiter` | stack 0 / logic | (6500,1000) 1000x1000 | 1000000 | 0.2 | 0.2 |
| `top.bank_pim_core_ch0_bank0` | stack 0 / dram 0 / ch 0 / bank 0 | (0,0) 250x3000 | 750000 | 0.7 | 0.9333333 |
| `top.bank_local_reduction_buffer_ch7_bank15` | stack 0 / dram 0 / ch 7 / bank 15 | (7750,9000) 250x3000 | 750000 | 0.3 | 0.4 |

## Validation

- Units are explicit and implicit conversion is rejected.
- Every rectangle is checked against die bounds.
- Input power is conserved across mapped and explicitly reported unmapped blocks.
- Unknown module names fail by default.

> Power is only as accurate as the supplied RTL activity and power reports; mapping is architectural, not thermal signoff.
