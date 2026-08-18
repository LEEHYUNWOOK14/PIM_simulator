# B17 residual congestion analysis

Generated: `2026-08-18T12:10:54.843484+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **481**
- Overflow edges/tracks: **352 / 423**
- Congestion windows: **862**; at capacity: **510**
- Maximum congestion: **4**
- Layers: `{"met1": 450, "met2": 232, "met3": 128, "met4": 50, "met5": 2}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 1, "Q1_fence": 3, "Q2_fence": 1, "Q3_fence": 1, "central_corridor": 346}`
- Source quad, non-exclusive: `{"Q0": 7, "Q1": 5, "Q2": 210, "Q3": 209, "unassigned": 86}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 3 | met1 | central_corridor | 4974.9, 4664.4, 4981.8, 4671.3 | u_b2_implementation/u_pcu/_0809_, u_b2_implementation/u_pcu/_1542_, u_b2_implementation/u_pcu/_2405_, u_b2_implementation/u_pcu/_2419_ |
| 3 | met1 | central_corridor | 4912.8, 4623.0, 4919.7, 4629.9 | u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0736_ |
| 3 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_2723_, u_b2_implementation/u_pcu/_2724_ |
| 3 | met1 | central_corridor | 4954.2, 4664.4, 4961.1, 4671.3 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0731_ |
| 3 | met1 | central_corridor | 4988.7, 4678.2, 4995.6, 4685.1 | u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_0863_, u_b2_implementation/u_pcu/_1274_, u_b2_implementation/u_pcu/_1341_ |
| 3 | met1 | central_corridor | 4919.7, 4671.3, 4926.6, 4678.2 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0707_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0730_ |
| 3 | met1 | central_corridor | 4974.9, 4636.8, 4981.8, 4643.7 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0804_ |
| 3 | met1 | central_corridor | 4974.9, 4623.0, 4981.8, 4629.9 | u_b2_implementation/u_pcu/_0492_, u_b2_implementation/u_pcu/_0804_, u_b2_implementation/u_pcu/_0808_, u_b2_implementation/u_pcu/_2072_ |
| 3 | met1 | central_corridor | 4988.7, 4657.5, 4995.6, 4664.4 | clk_i, u_b2_implementation/u_pcu/_0485_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0645_ |
| 3 | met1 | central_corridor | 4947.3, 4664.4, 4954.2, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0726_, u_b2_implementation/u_pcu/_0728_, u_b2_implementation/u_pcu/_0731_ |
| 2 | met1 | central_corridor | 4919.7, 4657.5, 4926.6, 4664.4 | u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0713_, u_b2_implementation/u_pcu/_0715_ |
| 2 | met1 | central_corridor | 4926.6, 4657.5, 4933.5, 4664.4 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 2 | met1 | central_corridor | 4954.2, 4678.2, 4961.1, 4685.1 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0719_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0725_ |
| 2 | met1 | central_corridor | 4981.8, 4657.5, 4988.7, 4664.4 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0720_, u_b2_implementation/u_pcu/_0797_, u_b2_implementation/u_pcu/_0801_ |
| 2 | met1 | central_corridor | 4905.9, 4636.8, 4912.8, 4643.7 | u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0742_, u_b2_implementation/u_pcu/_0745_, u_b2_implementation/u_pcu/_0748_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
