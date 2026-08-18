# B10 residual congestion analysis

Generated: `2026-08-18T08:07:08.691735+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **478**
- Overflow edges/tracks: **360 / 434**
- Congestion windows: **862**; at capacity: **502**
- Maximum congestion: **4**
- Layers: `{"met1": 459, "met2": 239, "met3": 117, "met4": 47}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q1_fence": 4, "Q2_fence": 2, "Q3_fence": 6, "central_corridor": 348}`
- Source quad, non-exclusive: `{"Q0": 1, "Q1": 8, "Q2": 213, "Q3": 200, "unassigned": 96}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 4 | met1 | central_corridor | 4954.2, 4664.4, 4961.1, 4671.3 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0728_ |
| 4 | met1 | central_corridor | 4933.5, 4664.4, 4940.4, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0705_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 3 | met1 | central_corridor | 4926.6, 4664.4, 4933.5, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0719_ |
| 3 | met1 | central_corridor | 4919.7, 4692.0, 4926.6, 4698.9 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0719_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0727_ |
| 3 | met1 | central_corridor | 4981.8, 4678.2, 4988.7, 4685.1 | u_b2_implementation/u_pcu/_0817_, u_b2_implementation/u_pcu/_0821_, u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_0863_ |
| 3 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_2723_, u_b2_implementation/u_pcu/_2724_ |
| 3 | met1 | central_corridor | 4961.1, 4636.8, 4968.0, 4643.7 | u_b2_implementation/u_pcu/_0710_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_0776_, u_b2_implementation/u_pcu/_0797_ |
| 3 | met1 | central_corridor | 4974.9, 4636.8, 4981.8, 4643.7 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0804_ |
| 3 | met1 | central_corridor | 4974.9, 4623.0, 4981.8, 4629.9 | u_b2_implementation/u_pcu/_0492_, u_b2_implementation/u_pcu/_0804_, u_b2_implementation/u_pcu/_0808_, u_b2_implementation/u_pcu/_2072_ |
| 3 | met1 | central_corridor | 4981.8, 4623.0, 4988.7, 4629.9 | u_b2_implementation/u_pcu/_0492_, u_b2_implementation/u_pcu/_0496_, u_b2_implementation/u_pcu/_0497_, u_b2_implementation/u_pcu/_0808_ |
| 3 | met1 | central_corridor | 4974.9, 4664.4, 4981.8, 4671.3 | u_b2_implementation/u_pcu/_0809_, u_b2_implementation/u_pcu/_1542_, u_b2_implementation/u_pcu/_2405_, u_b2_implementation/u_pcu/_2419_ |
| 2 | met1 | central_corridor | 4892.1, 4671.3, 4899.0, 4678.2 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0713_, u_b2_implementation/u_pcu/_0717_ |
| 2 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 2 | met1 | central_corridor | 4981.8, 4650.6, 4988.7, 4657.5 | u_b2_implementation/u_pcu/_0797_, u_b2_implementation/u_pcu/_0801_, u_b2_implementation/u_pcu/_0802_, u_b2_implementation/u_pcu/_0805_ |
| 2 | met1 | central_corridor | 4905.9, 4636.8, 4912.8, 4643.7 | u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0742_, u_b2_implementation/u_pcu/_0745_, u_b2_implementation/u_pcu/_0748_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
