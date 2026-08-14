# Partial placement archive manifest

Archive time: 2026-08-14 07:46:14 UTC (directory timestamp convention)

This directory preserves the interrupted/recovered Phase 3 placement attempt. Logs, JSON, SDC, and this manifest are versioned. The two ODB files remain in the local archive because each exceeds GitHub's normal Git single-file limit and Git LFS is not installed in the execution environment.

| Local artifact | Size (byte) | SHA-256 | Git status |
|---|---:|---|---|
| `results/3_5_place_dp.odb` | 2,935,363,098 | `2debf80b1917e212d27f090ada86aab0f04f0f0eab3bff9005e033632858d07b` | local only, ignored by `*.odb` |
| `results/3_place.odb` | 2,935,363,098 | `2debf80b1917e212d27f090ada86aab0f04f0f0eab3bff9005e033632858d07b` | local only, ignored by `*.odb` |

The identical hash shows that the two names refer to the same serialized design state. Their presence does not by itself establish a valid final placement; use the accompanying logs and independent legality audit before making a completion claim.
