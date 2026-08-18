# B21 residual congestion analysis

Generated: `2026-08-18T13:14:21.019548+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **455**
- Overflow edges/tracks: **345 / 404**
- Congestion windows: **833**; at capacity: **488**
- Maximum congestion: **4**
- Layers: `{"met1": 437, "met2": 224, "met3": 122, "met4": 50}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 1, "Q1_fence": 5, "Q2_fence": 1, "Q3_fence": 2, "central_corridor": 336}`
- Source quad, non-exclusive: `{"Q0": 5, "Q1": 8, "Q2": 195, "Q3": 183, "unassigned": 102}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 4 | met1 | central_corridor | 4981.8, 4636.8, 4988.7, 4643.7 | u_b2_implementation/u_pcu/_0486_, u_b2_implementation/u_pcu/_0487_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_ |
| 3 | met1 | central_corridor | 4912.8, 4623.0, 4919.7, 4629.9 | u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0736_ |
| 3 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_2723_, u_b2_implementation/u_pcu/_2724_ |
| 3 | met1 | central_corridor | 4974.9, 4636.8, 4981.8, 4643.7 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0804_ |
| 2 | met1 | central_corridor | 4926.6, 4657.5, 4933.5, 4664.4 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 2 | met1 | central_corridor | 4947.3, 4705.8, 4954.2, 4712.7 | u_b2_implementation/u_pcu/_0721_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0730_, u_b2_implementation/u_pcu/_0736_ |
| 2 | met1 | central_corridor | 4947.3, 4719.6, 4954.2, 4726.5 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0730_, u_b2_implementation/u_pcu/_0812_, u_b2_implementation/u_pcu/_0840_ |
| 2 | met1 | central_corridor | 4961.1, 4671.3, 4968.0, 4678.2 | u_b2_implementation/u_pcu/_0736_, u_b2_implementation/u_pcu/_0741_, u_b2_implementation/u_pcu/_0749_, u_b2_implementation/u_pcu/_0750_ |
| 2 | met1 | central_corridor | 4988.7, 4678.2, 4995.6, 4685.1 | u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_1341_, u_b2_implementation/u_pcu/_1342_, u_b2_implementation/u_pcu/_1345_ |
| 2 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 2 | met1 | central_corridor | 4926.6, 4664.4, 4933.5, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0719_ |
| 2 | met1 | central_corridor | 4933.5, 4657.5, 4940.4, 4664.4 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0703_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0718_ |
| 2 | met1 | central_corridor | 4926.6, 4671.3, 4933.5, 4678.2 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0707_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0730_ |
| 2 | met2 | central_corridor | 4940.4, 4692.0, 4947.3, 4698.9 | u_b2_implementation/u_pcu/_0700_, u_b2_implementation/u_pcu/_0709_, u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0716_ |
| 2 | met1 | central_corridor | 4954.2, 4643.7, 4961.1, 4650.6 | u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0730_, u_b2_implementation/u_pcu/_0733_, u_b2_implementation/u_pcu/_0734_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
