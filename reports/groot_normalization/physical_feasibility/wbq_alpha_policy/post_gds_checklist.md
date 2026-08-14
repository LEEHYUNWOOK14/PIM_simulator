# Post-GDS alpha-policy checklist

- [ ] Record the completed global-alpha 3_4 manifest and artifact hashes.
- [ ] Confirm Phase 4 remained blocked until the 3_4 result was classified.
- [ ] Implement and test `subtree_alpha = original_net_alpha`.
- [ ] Rerun 3_4 with inherited alpha from the identical 3_3 ODB.
- [ ] Compare runtime, buffer count, resize count, repaired nets, and area.
- [ ] Compare legalization, HPWL, displacement, and congestion.
- [ ] Compare pre-CTS timing only as provisional evidence.
- [ ] Compare routed timing, DRC, and final-GDS geometry.
- [ ] If inherited alpha passes, mark it as the accepted result lineage.
- [ ] If global alpha is retained, document why its QoR change is immaterial.
- [ ] If neither passes, evaluate alpha candidates only on the problem nets.
- [ ] Any changed alpha policy requires regeneration beginning at stage 3_4.
