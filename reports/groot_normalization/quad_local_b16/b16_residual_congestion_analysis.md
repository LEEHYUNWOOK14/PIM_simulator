# B16 residual congestion analysis

Generated: `2026-08-18T11:44:34.926172+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **492**
- Overflow edges/tracks: **386 / 446**
- Congestion windows: **885**; at capacity: **499**
- Maximum congestion: **4**
- Layers: `{"met1": 446, "met2": 247, "met3": 138, "met4": 54}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 1, "Q1_fence": 5, "Q2_fence": 1, "Q3_fence": 3, "central_corridor": 376}`
- Source quad, non-exclusive: `{"Q0": 6, "Q1": 8, "Q2": 222, "Q3": 214, "unassigned": 102}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 4 | met1 | central_corridor | 4981.8, 4636.8, 4988.7, 4643.7 | u_b2_implementation/u_pcu/_0486_, u_b2_implementation/u_pcu/_0487_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_ |
| 3 | met1 | central_corridor | 4974.9, 4664.4, 4981.8, 4671.3 | u_b2_implementation/u_pcu/_0809_, u_b2_implementation/u_pcu/_1542_, u_b2_implementation/u_pcu/_2405_, u_b2_implementation/u_pcu/_2419_ |
| 3 | met1 | central_corridor | 4954.2, 4664.4, 4961.1, 4671.3 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0731_ |
| 3 | met1 | central_corridor | 4954.2, 4623.0, 4961.1, 4629.9 | u_b2_implementation/u_pcu/_0736_, u_b2_implementation/u_pcu/_0744_, u_b2_implementation/u_pcu/_0774_, u_b2_implementation/u_pcu/_0778_ |
| 3 | met1 | central_corridor | 4947.3, 4664.4, 4954.2, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0726_, u_b2_implementation/u_pcu/_0728_, u_b2_implementation/u_pcu/_0731_ |
| 3 | met1 | central_corridor | 4988.7, 4623.0, 4995.6, 4629.9 | clk_i, u_b2_implementation/u_pcu/_0492_, u_b2_implementation/u_pcu/_0496_, u_b2_implementation/u_pcu/_0497_ |
| 3 | met3 | central_corridor | 4981.8, 4664.4, 4988.7, 4671.3 | u_b2_implementation/u_pcu/_0863_, u_b2_implementation/u_pcu/_1591_, u_b2_implementation/u_pcu/_2484_, u_b2_implementation/u_pcu/ctx_valid_q[3] |
| 2 | met1 | central_corridor | 4954.2, 4636.8, 4961.1, 4643.7 | u_b2_implementation/u_pcu/_0709_, u_b2_implementation/u_pcu/_0710_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0720_ |
| 2 | met1 | central_corridor | 4968.0, 4657.5, 4974.9, 4664.4 | u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0733_, u_b2_implementation/u_pcu/_0735_, u_b2_implementation/u_pcu/_0801_ |
| 2 | met1 | central_corridor | 4919.7, 4678.2, 4926.6, 4685.1 | u_b2_implementation/u_pcu/_0707_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0719_ |
| 2 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 2 | met1 | central_corridor | 4905.9, 4636.8, 4912.8, 4643.7 | u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0742_, u_b2_implementation/u_pcu/_0745_, u_b2_implementation/u_pcu/_0748_ |
| 2 | met1 | central_corridor | 4981.8, 4650.6, 4988.7, 4657.5 | u_b2_implementation/u_pcu/_0797_, u_b2_implementation/u_pcu/_0801_, u_b2_implementation/u_pcu/_0802_, u_b2_implementation/u_pcu/_0805_ |
| 2 | met1 | central_corridor | 4885.2, 4685.1, 4892.1, 4692.0 | u_b2_implementation/u_pcu/_0726_, u_b2_implementation/u_pcu/_0728_, u_b2_implementation/u_pcu/_0732_, u_b2_implementation/u_pcu/_0829_ |
| 2 | met1 | central_corridor | 4912.8, 4678.2, 4919.7, 4685.1 | u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0726_, u_b2_implementation/u_pcu/_0728_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
