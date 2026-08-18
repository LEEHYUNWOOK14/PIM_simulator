# B24 residual congestion analysis

Generated: `2026-08-18T14:38:22.627313+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **487**
- Overflow edges/tracks: **363 / 441**
- Congestion windows: **871**; at capacity: **508**
- Maximum congestion: **4**
- Layers: `{"met1": 461, "met2": 243, "met3": 123, "met4": 42, "met5": 2}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q1_fence": 4, "Q2_fence": 1, "Q3_fence": 2, "central_corridor": 356}`
- Source quad, non-exclusive: `{"Q0": 3, "Q1": 6, "Q2": 212, "Q3": 195, "unassigned": 110}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 4 | met1 | central_corridor | 4974.9, 4636.8, 4981.8, 4643.7 | u_b2_implementation/u_pcu/_0493_, u_b2_implementation/u_pcu/_0798_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0804_ |
| 3 | met1 | central_corridor | 4912.8, 4623.0, 4919.7, 4629.9 | u_b2_implementation/u_pcu/_0706_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0723_, u_b2_implementation/u_pcu/_0736_ |
| 3 | met2 | central_corridor | 4926.6, 4692.0, 4933.5, 4698.9 | u_b2_implementation/u_pcu/_0727_, u_b2_implementation/u_pcu/_0746_, u_b2_implementation/u_pcu/_0749_, u_b2_implementation/u_pcu/_0786_ |
| 3 | met1 | central_corridor | 4899.0, 4664.4, 4905.9, 4671.3 | u_b2_implementation/u_pcu/_0715_, u_b2_implementation/u_pcu/_0739_, u_b2_implementation/u_pcu/_2723_, u_b2_implementation/u_pcu/_2724_ |
| 3 | met1 | central_corridor | 4981.8, 4629.9, 4988.7, 4636.8 | u_b2_implementation/u_pcu/_0495_, u_b2_implementation/u_pcu/_0499_, u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_ |
| 3 | met1 | central_corridor | 4988.7, 4650.6, 4995.6, 4657.5 | u_b2_implementation/u_pcu/_1373_, u_b2_implementation/u_pcu/_1374_, u_b2_implementation/u_pcu/_1375_, u_b2_implementation/u_pcu/_1377_ |
| 3 | met1 | central_corridor | 4974.9, 4623.0, 4981.8, 4629.9 | u_b2_implementation/u_pcu/_0492_, u_b2_implementation/u_pcu/_0804_, u_b2_implementation/u_pcu/_0808_, u_b2_implementation/u_pcu/_2072_ |
| 3 | met1 | central_corridor | 4974.9, 4664.4, 4981.8, 4671.3 | u_b2_implementation/u_pcu/_0809_, u_b2_implementation/u_pcu/_1542_, u_b2_implementation/u_pcu/_2405_, u_b2_implementation/u_pcu/_2419_ |
| 3 | met2 | central_corridor | 4974.9, 4609.2, 4981.8, 4616.1 | u_b2_implementation/u_pcu/_0776_, u_b2_implementation/u_pcu/_0783_, u_b2_implementation/u_pcu/_0869_, u_b2_implementation/u_pcu/_0873_ |
| 2 | met1 | central_corridor | 4892.1, 4692.0, 4899.0, 4698.9 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0707_, u_b2_implementation/u_pcu/_0718_, u_b2_implementation/u_pcu/_0723_ |
| 2 | met1 | central_corridor | 4974.9, 4719.6, 4981.8, 4726.5 | u_b2_implementation/u_pcu/_0501_, u_b2_implementation/u_pcu/_0502_, u_b2_implementation/u_pcu/_0813_, u_b2_implementation/u_pcu/_0814_ |
| 2 | met1 | central_corridor | 4940.4, 4705.8, 4947.3, 4712.7 | u_b2_implementation/u_pcu/_0700_, u_b2_implementation/u_pcu/_0709_, u_b2_implementation/u_pcu/_0721_, u_b2_implementation/u_pcu/_0725_ |
| 2 | met1 | central_corridor | 4926.6, 4664.4, 4933.5, 4671.3 | u_b2_implementation/u_pcu/_0702_, u_b2_implementation/u_pcu/_0708_, u_b2_implementation/u_pcu/_0711_, u_b2_implementation/u_pcu/_0719_ |
| 2 | met1 | central_corridor | 4974.9, 4629.9, 4981.8, 4636.8 | u_b2_implementation/u_pcu/_0800_, u_b2_implementation/u_pcu/_0806_, u_b2_implementation/u_pcu/_0807_, u_b2_implementation/u_pcu/_0808_ |
| 2 | met1 | central_corridor | 4926.6, 4636.8, 4933.5, 4643.7 | u_b2_implementation/u_pcu/_0701_, u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0710_, u_b2_implementation/u_pcu/_0741_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
