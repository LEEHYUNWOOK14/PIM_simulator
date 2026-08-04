# Emulator API

## Overview

`emulator_api` contains test and support code for recording memory-access traces from host-side PIM kernel execution and replaying those traces through PIMSimulator.

In practical terms, the API converts memory requests produced by a host program or PIM SDK-style flow into simulator transactions. This makes it possible to analyze PIM behavior at cycle level using a memory access pattern that resembles an actual execution environment.

The Emulator API is included in the default build. If it is not needed, it can be excluded with:

```bash
scons NO_EMUL=1
```

For the broader simulator workflow, build options, and source-map overview, see the root-level [PIMSimulator Project Guide](../../PIMSimulator_GUIDE.md).
