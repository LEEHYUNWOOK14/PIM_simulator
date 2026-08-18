# B9 residual congestion analysis

Generated: `2026-08-18T07:35:31.604315+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **448**
- Overflow edges/tracks: **346 / 412**
- Congestion windows: **813**; at capacity: **467**
- Maximum congestion: **3**
- Layers: `{"met1": 449, "met2": 226, "met3": 109, "met4": 29}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 1, "Q1_fence": 3, "Q2_fence": 1, "Q3_fence": 3, "central_corridor": 338}`
- Source quad, non-exclusive: `{"Q0": 4, "Q1": 5, "Q2": 209, "Q3": 179, "unassigned": 106}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 3 | met1 | central_corridor | 4974.9, 4636.8, 4981.8, 4643.7 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0804_ |
| 3 | met1 | central_corridor | 4878.3, 4678.2, 4885.2, 4685.1 | u_b2_implementation/u_pcu/_0713_, u_b2_implementation/u_pcu/_0826_, u_b2_implementation/u_pcu/_0828_, u_b2_implementation/u_pcu/_0834_ |
| 3 | met1 | central_corridor | 4981.8, 4636.8, 4988.7, 4643.7 | u_b2_implementation/u_pcu/_0486_, u_b2_implementation/u_pcu/_0487_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_ |
| 3 | met1 | central_corridor | 4871.4, 4678.2, 4878.3, 4685.1 | u_b2_implementation/u_pcu/_0826_, u_b2_implementation/u_pcu/_0828_, u_b2_implementation/u_pcu/_0831_, u_b2_implementation/u_pcu/_0834_ |
| 2 | met1 | central_corridor | 4926.6, 4657.5, 4933.5, 4664.4 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 2 | met1 | central_corridor | 4947.3, 4719.6, 4954.2, 4726.5 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0730_, u_b2_implementation/u_pcu/_0812_, u_b2_implementation/u_pcu/_0840_ |
| 2 | met1 | central_corridor | 4981.8, 4705.8, 4988.7, 4712.7 | u_b2_implementation/u_pcu/_0824_, u_b2_implementation/u_pcu/_1277_, u_b2_implementation/u_pcu/_1280_, u_b2_implementation/u_pcu/_1281_ |
| 2 | met1 | central_corridor | 4961.1, 4636.8, 4968.0, 4643.7 | u_b2_implementation/u_pcu/_0710_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_0776_ |
| 2 | met1 | central_corridor | 4905.9, 4636.8, 4912.8, 4643.7 | u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0741_, u_b2_implementation/u_pcu/_0742_, u_b2_implementation/u_pcu/_0745_ |
| 2 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 2 | met1 | central_corridor | 4926.6, 4664.4, 4933.5, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0719_ |
| 2 | met1 | central_corridor | 4885.2, 4705.8, 4892.1, 4712.7 | u_b2_implementation/u_pcu/_0527_, u_b2_implementation/u_pcu/_0528_, u_b2_implementation/u_pcu/_0729_, u_b2_implementation/u_pcu/_0792_ |
| 2 | met1 | central_corridor | 4947.3, 4650.6, 4954.2, 4657.5 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0703_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0715_ |
| 2 | met1 | central_corridor | 4926.6, 4671.3, 4933.5, 4678.2 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0707_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0730_ |
| 2 | met2 | central_corridor | 4947.3, 4629.9, 4954.2, 4636.8 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0703_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0716_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
