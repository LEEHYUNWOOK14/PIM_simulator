# B23 residual congestion analysis

Generated: `2026-08-18T14:12:06.731970+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **463**
- Overflow edges/tracks: **351 / 415**
- Congestion windows: **860**; at capacity: **509**
- Maximum congestion: **4**
- Layers: `{"met1": 449, "met2": 243, "met3": 120, "met4": 48}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 1, "Q1_fence": 3, "Q3_fence": 2, "central_corridor": 345}`
- Source quad, non-exclusive: `{"Q0": 6, "Q1": 7, "Q2": 211, "Q3": 207, "unassigned": 83}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 4 | met1 | central_corridor | 4933.5, 4664.4, 4940.4, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0705_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_ |
| 3 | met1 | central_corridor | 4905.9, 4678.2, 4912.8, 4685.1 | u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0726_, u_b2_implementation/u_pcu/_0728_ |
| 3 | met1 | central_corridor | 4933.5, 4657.5, 4940.4, 4664.4 | u_b2_implementation/u_pcu/_0703_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0721_ |
| 3 | met1 | central_corridor | 4988.7, 4678.2, 4995.6, 4685.1 | u_b2_implementation/u_pcu/_0822_, u_b2_implementation/u_pcu/_1341_, u_b2_implementation/u_pcu/_1342_, u_b2_implementation/u_pcu/_1345_ |
| 3 | met1 | central_corridor | 4981.8, 4636.8, 4988.7, 4643.7 | u_b2_implementation/u_pcu/_0486_, u_b2_implementation/u_pcu/_0487_, u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_ |
| 3 | met1 | central_corridor | 4974.9, 4650.6, 4981.8, 4657.5 | u_b2_implementation/u_pcu/_0797_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0799_, u_b2_implementation/u_pcu/_0801_ |
| 3 | met1 | central_corridor | 4926.6, 4664.4, 4933.5, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0719_ |
| 3 | met1 | central_corridor | 4954.2, 4623.0, 4961.1, 4629.9 | u_b2_implementation/u_pcu/_0736_, u_b2_implementation/u_pcu/_0744_, u_b2_implementation/u_pcu/_0774_, u_b2_implementation/u_pcu/_0778_ |
| 2 | met1 | central_corridor | 4926.6, 4657.5, 4933.5, 4664.4 | u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0715_ |
| 2 | met1 | central_corridor | 4954.2, 4678.2, 4961.1, 4685.1 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0719_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0725_ |
| 2 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_0870_, u_b2_implementation/u_pcu/_2723_ |
| 2 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 2 | met1 | central_corridor | 4885.2, 4705.8, 4892.1, 4712.7 | u_b2_implementation/u_pcu/_0527_, u_b2_implementation/u_pcu/_0528_, u_b2_implementation/u_pcu/_0729_, u_b2_implementation/u_pcu/_0733_ |
| 2 | met1 | central_corridor | 4912.8, 4671.3, 4919.7, 4678.2 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0736_, u_b2_implementation/u_pcu/_0741_ |
| 2 | met1 | central_corridor | 4912.8, 4678.2, 4919.7, 4685.1 | u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0725_, u_b2_implementation/u_pcu/_0726_, u_b2_implementation/u_pcu/_0728_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
