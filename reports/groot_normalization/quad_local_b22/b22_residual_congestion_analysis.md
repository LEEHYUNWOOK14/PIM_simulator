# B22 residual congestion analysis

Generated: `2026-08-18T13:43:34.902357+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **480**
- Overflow edges/tracks: **382 / 454**
- Congestion windows: **870**; at capacity: **488**
- Maximum congestion: **4**
- Layers: `{"met1": 447, "met2": 239, "met3": 140, "met4": 44}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q1_fence": 4, "Q3_fence": 3, "central_corridor": 375}`
- Source quad, non-exclusive: `{"Q0": 2, "Q1": 8, "Q2": 235, "Q3": 216, "unassigned": 97}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 3 | met1 | central_corridor | 4988.7, 4678.2, 4995.6, 4685.1 | u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_0863_, u_b2_implementation/u_pcu/_1341_, u_b2_implementation/u_pcu/_1342_ |
| 3 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 3 | met1 | central_corridor | 4905.9, 4636.8, 4912.8, 4643.7 | u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0742_, u_b2_implementation/u_pcu/_0745_, u_b2_implementation/u_pcu/_0748_ |
| 3 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_2723_, u_b2_implementation/u_pcu/_2724_ |
| 3 | met1 | central_corridor | 4974.9, 4636.8, 4981.8, 4643.7 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0800_ |
| 3 | met1 | central_corridor | 4961.1, 4636.8, 4968.0, 4643.7 | u_b2_implementation/u_pcu/_0710_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_0776_ |
| 3 | met1 | central_corridor | 4981.8, 4636.8, 4988.7, 4643.7 | u_b2_implementation/u_pcu/_0486_, u_b2_implementation/u_pcu/_0487_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_ |
| 3 | met1 | central_corridor | 4954.2, 4623.0, 4961.1, 4629.9 | u_b2_implementation/u_pcu/_0736_, u_b2_implementation/u_pcu/_0742_, u_b2_implementation/u_pcu/_0774_, u_b2_implementation/u_pcu/_0778_ |
| 3 | met1 | central_corridor | 4933.5, 4664.4, 4940.4, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0705_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 2 | met1 | central_corridor | 4926.6, 4657.5, 4933.5, 4664.4 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 2 | met1 | central_corridor | 4919.7, 4657.5, 4926.6, 4664.4 | u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0713_, u_b2_implementation/u_pcu/_0715_ |
| 2 | met1 | central_corridor | 4954.2, 4678.2, 4961.1, 4685.1 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0719_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0725_ |
| 2 | met1 | central_corridor | 4926.6, 4664.4, 4933.5, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0719_ |
| 2 | met1 | central_corridor | 4974.9, 4629.9, 4981.8, 4636.8 | u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_, u_b2_implementation/u_pcu/_0807_, u_b2_implementation/u_pcu/_0808_ |
| 2 | met1 | central_corridor | 4926.6, 4636.8, 4933.5, 4643.7 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0710_, u_b2_implementation/u_pcu/_0741_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
