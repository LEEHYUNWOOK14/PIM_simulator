# PIMSimulator Project Guide

> This project is an HBM2-based Processing-in-Memory (PIM) simulator used for the STOB semiconductor competition PIM problem.

## 1. Project Overview

`PIMSimulator` is a cycle-level C++ simulator for an HBM2-based Processing-in-Memory system. It models normal host memory transactions and PIM computation inside one memory system, including channels, ranks, banks, buses, commands, address mapping, timing, and statistics.

The repository is derived from [DRAMSim2](https://github.com/umd-memsys/DRAMSim2) and extends it with PIM blocks, PIM command generation, PIM kernels, and benchmark/test infrastructure.

Main goals:

- Evaluate PIM execution using HBM2 channel and bank parallelism.
- Verify interaction between PIM instructions and normal memory commands.
- Validate GEMV and element-wise ADD, MUL, and RELU kernels.
- Analyze latency, bandwidth, bank behavior, PIM execution, and power/energy statistics.
- Reproduce PIM kernel traces and memory traces inside the simulator.

## 2. Competition Context

The target problem asks for a practical PIM architecture for AI workloads in edge-server and on-device environments. The broader goal is not only to optimize one fixed application, but also to reason about a general-purpose PIM architecture, memory controller 설계, interfaces, software/hardware implementation, and PPA analysis.

This simulator provides the modeling basis for that work:

1. Compare normal DRAM accesses with PIM execution at cycle level.
2. Evaluate how channel and bank parallelism affect throughput and latency.
3. Measure the benefit of PIM for GEMV and element-wise AI kernels.
4. Include PIM ALU energy and DRAM power/energy statistics where supported.
5. Validate improvements to memory-controller policy, address mapping, PIM interfaces, and topology ideas.

The simulator is therefore best understood as an 실험al platform for quantitative comparison and validation, not as a complete final PIM product by itself.

## 3. Hardware And Execution Model

The high-level execution path is:

```text
HOST
  -> normal read/write or PIM read/write
  -> MultiChannelMemorySystem
  -> address distribution across channels
  -> MemoryController x NUM_CHANS
  -> transactions, DRAM commands, buses
  -> Rank / PIMRank
  -> HBM2 DRAM behavior and PIM mode control
  -> PIMBlock x NUM_PIM_BLOCKS
  -> CRF, GRF, SRF, and ALU
  -> ADD / MUL / MAC / MAD / MOV / FILL / control instructions
```

Each channel owns an independent memory controller. The default HBM2 model uses 16 logical channels, a 64-bit data bus, 16 banks, and 8 PIM blocks. In the baseline configuration, the PIM block assignment is derived from `NUM_BANKS / NUM_PIM_BLOCKS`, so one PIM block corresponds to two banks.

## 4. Address Mapping

PIM execution expects `Scheme8` address mapping.

```text
| rank | row | column high | bank group | bank | channel | column low | offset |
```

`AddressMapping` decomposes host addresses into channel, rank, bank, row, and column fields. PIM transactions use the decoded bank and bank-group fields to select data placement and to decide which PIM block participates in execution and result return.

## 5. PIM Instruction Model

PIM instructions use a compact RISC-style encoding. `PIMCmd` is responsible for instruction encoding, decoding, validation, and operand interpretation.

| Category | Instruction | Role |
|---|---|---|
| Arithmetic | `ADD` | Vector addition |
| Arithmetic | `MUL` | Vector multiplication |
| Arithmetic | `MAC` | Multiply-accumulate |
| Arithmetic | `MAD` | Multiply-add |
| Data movement | `MOV` | Move data between registers or bank-related storage |
| Data movement | `FILL` | Fill or load register data from bank data |
| Control | `NOP` | No operation |
| Control | `JUMP` | Static branch for repeated instruction sequences |
| Control | `EXIT` | Terminate the PIM command sequence |

Operands may refer to GRF-A, GRF-B, SRF, and bank-related buffers depending on the instruction. `PIMRank` manages the Command Register File (CRF), program counter, PIM mode transitions, and PIM block dispatch. `PIMBlock` executes arithmetic and data movement according to `PIM_PRECISION`, such as FP16, INT8, or FP32.

## 6. DRAM/PIM Operation Modes

A typical PIM kernel runs in this order:

1. Place input data in DRAM.
2. Switch from normal memory mode (`SB`) to HAB mode.
3. Program the CRF with `programCrf()`.
4. Switch to `HAB_PIM` mode.
5. Execute PIM computation through PIM transactions.
6. Return to HAB mode and disable active PIM execution.
7. Switch back to `SB` and read results.

The memory API is conceptually:

```cpp
mem->addTransaction(false, address, tag, &buffer); // read
mem->addTransaction(true,  address, tag, &buffer); // write or PIM write
```

PIM write traffic can be broadcast to multiple PIM blocks depending on mode and address generation. `read_pim` returns accumulated PIM results to the host-facing path.

## 7. Important Source Directories

| Path | Description |
|---|---|
| `src/MemorySystem.*` | Single memory-system interface and transaction entry point |
| `src/MultiChannelMemorySystem.*` | Multi-channel construction, address distribution, and global statistics |
| `src/MemoryController.*` | Transaction queues, DRAM command scheduling, refresh, buses, and controller statistics |
| `src/Rank.*`, `src/Bank.*`, `src/BankState.*` | DRAM rank and bank state modeling |
| `src/PIMRank.*` | PIM mode transitions, CRF execution, and PIM block dispatch |
| `src/PIMBlock.*` | Vector arithmetic, registers, and PIM block state |
| `src/PIMCmd.*` | PIM instruction encoding, decoding, and validation |
| `src/AddressMapping.*` | Host address decoding into channel/rank/bank/row/column fields |
| `src/tests/PIMKernel.*` | GEMV and element-wise PIM kernel flow |
| `src/tests/PIMCmdGen.*` | PIM ISA command generation |
| `src/tests/KernelTestCases.cpp` | Functional kernel tests |
| `src/tests/PIMBenchTestCases.cpp` | Benchmark tests |
| `tools/emulator_api/` | API for replaying host/PIM traces into the simulator |
| `ini/` | HBM2 device timing and organization files |
| `system_*.ini` | Channel count, address mapping, debug, trace, and statistic flags |
| `data/` | NPY input and expected-output datasets |
| `dump/` | Optional trace and binary dump data |

## 8. Build

Core build requirements are SCons, a C++14-capable compiler, and Google Test development files.

Typical Ubuntu setup:

```bash
sudo apt install scons libgtest-dev
scons
```

The `Sconstruct` file uses compiler flags such as `-g -O2 -std=c++14 -Wall`.

Build outputs:

- executable: `sim`
- intermediate objects: `bin/`
- DRAMSim2 library: `libdramsim/dramsim2`

Useful build options:

```bash
scons NO_STORAGE=1  # skip memory data-storage checks
scons NO_EMUL=1     # exclude emulator API tests
scons NO_LIBRARY=1  # skip library build
```

## 9. Tests And Benchmarks

List available Google Test cases:

```bash
./sim --gtest_list_tests
```

Common targets:

```bash
./sim --gtest_filter=PIMKernelFixture.gemv
./sim --gtest_filter=PIMKernelFixture.mul
./sim --gtest_filter=PIMKernelFixture.add
./sim --gtest_filter=PIMKernelFixture.relu
./sim --gtest_filter=PIMBenchFixture.gemv
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=MemBandwidthFixture.hbm_read_bandwidth
```

Functional tests use NPY inputs and expected results under `data/`. To add new tensor sizes, update the relevant data generator and reflect the new shape in the corresponding test case.

## 10. Configuration Files

System-level and HBM device configuration are separated.

- `system_hbm.ini`: default 16-channel configuration
- `system_hbm_1ch.ini`: 1-channel 실험 configuration
- `system_hbm_64ch.ini`: 64-channel 실험 configuration
- `ini/HBM2_samsung_2M_16B_x64.ini`: HBM2 timing, capacity, and bank organization

Commonly adjusted options:

| Option | Meaning |
|---|---|
| `NUM_CHANS` | Logical memory channel count |
| `JEDEC_DATA_BUS_BITS` | Data bus width |
| `TRANS_QUEUE_DEPTH`, `CMD_QUEUE_DEPTH` | Host transaction and DRAM command queue depth |
| `ADDRESS_MAPPING_SCHEME` | Address decoding policy; PIM expects `Scheme8` |
| `ROW_BUFFER_POLICY` | Open-page or close-page row-buffer behavior |
| `SCHEDULING_POLICY` | Rank/bank command scheduling policy |
| `QUEUING_STRUCTURE` | Per-rank or per-bank queue organization |
| `PIM_PRECISION` | `FP16`, `INT8`, or `FP32` |
| `DEBUG_PIM_TIME`, `DEBUG_CMD_TRACE`, `DEBUG_PIM_BLOCK` | PIM debug output flags |
| `PRINT_CHAN_STAT`, `PRINT_MEM_TRACE` | Channel statistics and memory trace output flags |
| `SIM_TRACE_FILE` | Trace output filename |

## 11. Statistics And Validation

`MemoryController` and `MultiChannelMemorySystem` collect transaction counts, transferred bytes, average latency, channel bandwidth, refresh counts, bank access counts, and power/energy estimates where available. PIM-related statistics include PIM instruction execution and ALU energy when instrumentation and configuration flags enable them.

Debug and trace flags can produce large output. For performance comparisons, record the exact configuration files, channel count, precision, input size, build options, and statistic/debug flags for every run.

## 12. Emulator API

`tools/emulator_api` provides a path for recording memory traces from host-side or SDK-style PIM calls and replaying those traces through the cycle-level simulator. `PimSimulator` initializes the memory system and PIM kernel flow, converts trace records into simulator transactions, and collects PIM output bursts.

This path connects application-level kernel invocation order and memory access behavior to the simulator's DRAM/PIM timing model.

## 13. Suggested Reading Order

For new PIM kernels or 실험s, inspect these files first:

1. `src/tests/PIMKernel.cpp`: high-level PIM execution order and address calculation
2. `src/tests/PIMCmdGen.h/.cpp`: PIM instruction generation
3. `src/PIMCmd.h/.cpp`: instruction encoding and operand constraints
4. `src/PIMRank.cpp`: CRF execution and DRAM/PIM data movement
5. `src/PIMBlock.cpp`: arithmetic and register behavior
6. `src/tests/PIMBenchTestCases.cpp`: benchmark methodology
7. `system_hbm*.ini` and `ini/HBM2_samsung_2M_16B_x64.ini`: 실험 configuration

Start by validating a small single-channel functional test, then compare performance and parallelism under the 16-channel and 64-channel configurations.

## 14. License Notes

The repository includes `LICENSE-PIMSimulator` and `LICENSE-DRAMSIM2`. Check both license files before redistributing modified simulator code.

