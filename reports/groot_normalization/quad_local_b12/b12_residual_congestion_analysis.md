# B12 residual congestion analysis

Generated: `2026-08-18T10:57:53.481813+00:00`

The congestion report was parsed as numeric `capacity` and `usage` values; legacy AWK string comparisons were not used.

## Direct result

- RRR residual: **104341**
- Overflow edges/tracks: **8571 / 9134**
- Congestion windows: **20000**; at capacity: **11429**
- Maximum congestion: **4**
- Layers: `{"met2": 10000, "met3": 10000}`
- Global-route invocation count: **1**

## Overflow distribution

- Spatial: `{"Q0_fence": 3518, "Q2_fence": 4931, "central_corridor": 88, "edge_guardband": 12, "outside_core": 22}`
- Source quad, non-exclusive: `{"Q0": 3621, "Q2": 5157}`

## Leading overflow hotspots

| Overflow | Layer | Region | bbox (um) | Leading sources |
| --- | --- | --- | --- | --- |
| 4 | met2 | Q2_fence | 1007.4, 6824.1, 1014.3, 6831.0 | u_b2_implementation/replay_x[1139], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[5].uc/_0765_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[5].uc/_0768_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[5].uc/_0770_ |
| 3 | met2 | Q2_fence | 1166.1, 5547.6, 1173.0, 5554.5 | u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[5].un/_00387_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[5].un/_00434_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[5].un/_00435_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[5].un/_00456_ |
| 3 | met2 | Q2_fence | 1262.7, 6941.4, 1269.6, 6948.3 | u_b2_implementation/reduction_data[1135], u_b2_implementation/reduction_data[1437], u_b2_implementation/reduction_data[1524], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[0].u_reduce/g_lane[5].um/_3741_ |
| 3 | met2 | Q2_fence | 1276.5, 7141.5, 1283.4, 7148.4 | u_b2_implementation/reduction_data[1177], u_b2_implementation/reduction_data[1303], u_b2_implementation/reduction_data[1431], u_b2_implementation/reduction_data[1526] |
| 3 | met2 | Q0_fence | 952.2, 2035.5, 959.1, 2042.4 | u_b2_implementation/replay_x[345], u_b2_implementation/replay_x[83], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[0].u_bank_slice/g_bank[1].u_apply/g_lane[0].uc/_1120_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[0].u_bank_slice/g_bank[1].u_apply/g_lane[0].uc/_1121_ |
| 3 | met2 | Q2_fence | 1476.6, 7320.9, 1483.5, 7327.8 | u_b2_implementation/reduction_data[1044], u_b2_implementation/reduction_data[1297], u_b2_implementation/reduction_data[1430], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[0].u_reduce/square[121] |
| 3 | met2 | Q2_fence | 1228.2, 6920.7, 1235.1, 6927.6 | u_b2_implementation/reduction_data[1268], u_b2_implementation/reduction_data[1388], u_b2_implementation/reduction_data[1492], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[0].u_reduce/g_lane[5].um/_0062_ |
| 3 | met2 | Q2_fence | 1345.5, 6941.4, 1352.4, 6948.3 | u_b2_implementation/reduction_data[1121], u_b2_implementation/reduction_data[1386], u_b2_implementation/reduction_data[1505], u_b2_implementation/reduction_data[1518] |
| 3 | met2 | Q2_fence | 1145.4, 6023.7, 1152.3, 6030.6 | u_b2_implementation/replay_x[1232], u_b2_implementation/replay_x[1235], u_b2_implementation/replay_x[1241], u_b2_implementation/replay_x[1242] |
| 3 | met3 | Q0_fence | 2214.9, 1455.9, 2221.8, 1462.8 | u_b2_implementation/reduction_data[108], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[0].u_bank_slice/g_bank[0].u_reduce/g_lane[6].um/_2928_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[0].u_bank_slice/g_bank[0].u_reduce/g_lane[6].um/_3019_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[0].u_bank_slice/g_bank[1].u_apply/g_lane[2].uc/_0859_ |
| 3 | met3 | Q2_fence | 1821.6, 6037.5, 1828.5, 6044.4 | u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[0].u_apply/mean_q[5], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/mean_q[22], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].un/_00457_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].un/_00463_ |
| 3 | met3 | Q2_fence | 1835.4, 5561.4, 1842.3, 5568.3 | u_b2_implementation/u_pcu/u_quad_datapath/quad_scalar_mean[76], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[6].un/_00022_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[6].un/_00361_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[1].u_apply/g_lane[6].un/_00366_ |
| 3 | met3 | Q2_fence | 2201.1, 5195.7, 2208.0, 5202.6 | u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[2].u_apply/narrowed[124], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].us/_00409_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].us/_01585_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].us/_01589_ |
| 3 | met3 | Q2_fence | 2228.7, 5237.1, 2235.6, 5244.0 | read_data_i[10], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].us/_00421_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].us/_00964_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].us/_01223_ |
| 3 | met3 | Q2_fence | 1835.4, 6134.1, 1842.3, 6141.0 | u_b2_implementation/replay_x[1171], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].un/_00392_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].un/_00422_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[2].u_bank_slice/g_bank[3].u_apply/g_lane[6].un/_00426_ |

## Preservation

- frozen_A: `964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad` — MATCH
- B: `ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235` — MATCH
- B2: `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` — MATCH

Physical zero-congestion evidence: **FAIL**.
This analysis does not itself issue the explicit Phase 6 PASS; the separate strict decision gate must also validate every input hash.
