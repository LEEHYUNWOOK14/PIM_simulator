# B11 residual congestion analysis

Generated: `2026-08-18T08:39:24.357516+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **485**
- Overflow edges/tracks: **381 / 451**
- Congestion windows: **849**; at capacity: **468**
- Maximum congestion: **4**
- Layers: `{"met1": 466, "met2": 222, "met3": 119, "met4": 41, "met5": 1}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 1, "Q1_fence": 6, "Q2_fence": 1, "Q3_fence": 3, "central_corridor": 370}`
- Source quad, non-exclusive: `{"Q0": 9, "Q1": 9, "Q2": 220, "Q3": 217, "unassigned": 96}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 3 | met1 | central_corridor | 4954.2, 4623.0, 4961.1, 4629.9 | u_b2_implementation/u_pcu/_0736_, u_b2_implementation/u_pcu/_0744_, u_b2_implementation/u_pcu/_0774_, u_b2_implementation/u_pcu/_0778_ |
| 3 | met2 | central_corridor | 4947.3, 4629.9, 4954.2, 4636.8 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0703_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0716_ |
| 3 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_2723_, u_b2_implementation/u_pcu/_2724_ |
| 3 | met1 | central_corridor | 4926.6, 4650.6, 4933.5, 4657.5 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0721_, u_b2_implementation/u_pcu/_0722_ |
| 3 | met1 | central_corridor | 4954.2, 4664.4, 4961.1, 4671.3 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0731_ |
| 3 | met1 | central_corridor | 4974.9, 4650.6, 4981.8, 4657.5 | u_b2_implementation/u_pcu/_0797_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0799_, u_b2_implementation/u_pcu/_0801_ |
| 3 | met1 | central_corridor | 4981.8, 4636.8, 4988.7, 4643.7 | u_b2_implementation/u_pcu/_0486_, u_b2_implementation/u_pcu/_0487_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_ |
| 3 | met1 | central_corridor | 4878.3, 4650.6, 4885.2, 4657.5 | u_b2_implementation/u_pcu/_0851_, u_b2_implementation/u_pcu/_0852_, u_b2_implementation/u_pcu/_0853_, u_b2_implementation/u_pcu/_0859_ |
| 2 | met1 | central_corridor | 4947.3, 4719.6, 4954.2, 4726.5 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0730_, u_b2_implementation/u_pcu/_0812_, u_b2_implementation/u_pcu/_0840_ |
| 2 | met1 | central_corridor | 4981.8, 4705.8, 4988.7, 4712.7 | u_b2_implementation/u_pcu/_0824_, u_b2_implementation/u_pcu/_1277_, u_b2_implementation/u_pcu/_1280_, u_b2_implementation/u_pcu/_1281_ |
| 2 | met1 | central_corridor | 4974.9, 4719.6, 4981.8, 4726.5 | u_b2_implementation/u_pcu/_0501_, u_b2_implementation/u_pcu/_0502_, u_b2_implementation/u_pcu/_0813_, u_b2_implementation/u_pcu/_0814_ |
| 2 | met1 | central_corridor | 4912.8, 4719.6, 4919.7, 4726.5 | u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0784_, u_b2_implementation/u_pcu/_0788_, u_b2_implementation/u_pcu/_0791_ |
| 2 | met1 | central_corridor | 4968.0, 4705.8, 4974.9, 4712.7 | u_b2_implementation/u_pcu/_0714_, u_b2_implementation/u_pcu/_0812_, u_b2_implementation/u_pcu/_0815_, u_b2_implementation/u_pcu/_0820_ |
| 2 | met1 | central_corridor | 4981.8, 4671.3, 4988.7, 4678.2 | u_b2_implementation/u_pcu/_0819_, u_b2_implementation/u_pcu/_0820_, u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_0864_ |
| 2 | met1 | central_corridor | 4988.7, 4678.2, 4995.6, 4685.1 | u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_0863_, u_b2_implementation/u_pcu/_1341_, u_b2_implementation/u_pcu/_1342_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
