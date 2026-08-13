# SAIT / DRAMsim3 HBM2 Cross-validation

| Parameter | Selected/SAIT | DRAMsim3 | Match | Resolution |
|---|---:|---:|:---:|---|
| physical channels | 8 | 8 | yes | standard/config chosen |
| channel width | 128 | 128 | yes | standard/config chosen |
| bank groups | 4 | 4 | yes | SAIT chosen |
| banks | 16 | 16 | yes | SAIT chosen |
| rows | 16384 | 32768 | no | SAIT chosen for project compatibility |
| columns | 128 | 64 | no | SAIT chosen for project compatibility |
| burst length | 4 | 4 | yes | SAIT chosen |
| bank-level refresh interval | 121 | 128 | no | SAIT tREFISB chosen; DRAMsim3 tREFIb retained as cross-check |
| address mapping | Scheme8 | rorabgbachco | no | project Scheme8 chosen for simulator compatibility |
| logical vs physical channels | 64 | 8 | no | kept separate via simulator_only_logical_partition |
| tRCDRD | 14 | 14 | yes | SAIT chosen for simulator compatibility |
| tRCDWR | 10 | 14 | no | SAIT chosen for simulator compatibility |
| tRP | 14 | 14 | yes | SAIT chosen for simulator compatibility |
| tRAS | 33 | 34 | no | SAIT chosen for simulator compatibility |
| tRFC | 350 | 260 | no | SAIT chosen for simulator compatibility |
| tREFI | 3900 | 3900 | yes | SAIT chosen for simulator compatibility |

Mismatches: 8. Differences are retained and explained rather than silently normalized.

## Local SAIT device configuration versus pinned upstream

Changed keys: {
  "BANK_LOCAL_ACCUMULATOR_BANKS": {
    "local": "1",
    "upstream": "<missing>"
  },
  "BANK_LOCAL_ACCUMULATOR_ENTRIES": {
    "local": "0",
    "upstream": "<missing>"
  },
  "BANK_LOCAL_ACCUMULATOR_LATENCY": {
    "local": "1",
    "upstream": "<missing>"
  },
  "BANK_LOCAL_ACCUMULATOR_PORTS": {
    "local": "0",
    "upstream": "<missing>"
  },
  "BANK_LOCAL_AGGREGATION_TAPS": {
    "local": "1",
    "upstream": "<missing>"
  },
  "ENABLE_BANK_SIDE_PIM": {
    "local": "true",
    "upstream": "<missing>"
  },
  "ENABLE_LOGIC_DIE_PIM": {
    "local": "true",
    "upstream": "<missing>"
  },
  "HIERARCHY_PIM_BW": {
    "local": "64",
    "upstream": "<missing>"
  },
  "HIERARCHY_READY_BYPASS": {
    "local": "true",
    "upstream": "<missing>"
  },
  "HIERARCHY_SOURCE_QUEUES": {
    "local": "false",
    "upstream": "<missing>"
  },
  "LOGIC_ACCUMULATOR_BW": {
    "local": "64",
    "upstream": "<missing>"
  },
  "LOGIC_ACCUMULATOR_ENTRIES": {
    "local": "0",
    "upstream": "<missing>"
  },
  "LOGIC_ACCUMULATOR_LATENCY": {
    "local": "1",
    "upstream": "<missing>"
  },
  "LOGIC_ACCUMULATOR_OVERLAP": {
    "local": "false",
    "upstream": "<missing>"
  },
  "LOGIC_BROADCAST_QUEUE_DEPTH": {
    "local": "128",
    "upstream": "<missing>"
  },
  "LOGIC_CMD_COALESCING": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_CMD_OVERHEAD": {
    "local": "4",
    "upstream": "<missing>"
  },
  "LOGIC_COMPACT_OUTPUT": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_DEPTHWISE_ACCUMULATION": {
    "local": "false",
    "upstream": "<missing>"
  },
  "LOGIC_DIRECT_STAGING_COMMAND_PATH": {
    "local": "false",
    "upstream": "<missing>"
  },
  "LOGIC_EPOCH_RELEASE": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_GLOBAL_SCHEDULER": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_ONLINE_QUEUE_BACKPRESSURE": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_PIM_BW": {
    "local": "64",
    "upstream": "<missing>"
  },
  "LOGIC_PIM_LATENCY": {
    "local": "2",
    "upstream": "<missing>"
  },
  "LOGIC_POST_FILL_GUARD_CYCLES": {
    "local": "0",
    "upstream": "<missing>"
  },
  "LOGIC_SHARED_WEIGHT_BUFFER": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_SPATIAL_GROUPING": {
    "local": "true",
    "upstream": "<missing>"
  },
  "LOGIC_WEIGHT_BUFFER_BYTES": {
    "local": "65536",
    "upstream": "<missing>"
  },
  "LOGIC_WEIGHT_BUFFER_WRITE_LATENCY": {
    "local": "1",
    "upstream": "<missing>"
  },
  "LOGIC_WEIGHT_BUFFER_WRITE_PORTS": {
    "local": "0",
    "upstream": "<missing>"
  },
  "LOGIC_WEIGHT_FILL_CHANNELS": {
    "local": "32",
    "upstream": "<missing>"
  },
  "LOGIC_WEIGHT_FILL_POLICY": {
    "local": "row_interleaved",
    "upstream": "<missing>"
  },
  "LOGIC_WEIGHT_STAGING_ROW": {
    "local": "2048",
    "upstream": "<missing>"
  },
  "NUM_LOGIC_PIM_UNITS": {
    "local": "16",
    "upstream": "<missing>"
  },
  "PIM_TARGET": {
    "local": "hybrid",
    "upstream": "<missing>"
  }
}

An empty object proves that the parsed local device values match the vendored upstream snapshot at the pinned commit. Comments and formatting are intentionally ignored. Thermal-capable DRAMsim3 behavior is a validation reference only; this visualization does not perform thermal simulation.
