# Full PIM RTL architecture and design rationale

## 1. Purpose and status

This document is the implementation ledger for the synthesizable bank-side and
logic-die PIM RTL.  Every block records whether its behaviour came from the C++
simulator or from an explicit hardware design decision.  The simulator remains
the functional reference; hardware-only details such as finite queues and
ready/valid handshakes are stated separately.

## 2. Simulator-derived contract

### 2.1 Command encoding

Source: `src/PIMCmd.h` and `src/PIMCmd.cpp`.

The CRF word is 32 bits. Bits `[31:28]` select `NOP, ADD, MUL, MAC, MAD, MOV,
FILL, JUMP, EXIT`. Arithmetic commands use destination `[27:25]`, source 0
`[24:22]`, source 1 `[21:19]`, optional MAD source 2 `[18:16]`, automatic mode
bit 15, and 4-bit register indices. The operand namespace is `A_OUT`, `M_OUT`,
even/odd bank data, `GRF_A`, `GRF_B`, multiplier scalar register `SRF_M`, and
adder scalar register `SRF_A`.

### 2.2 Bank-side register and arithmetic model

Source: `src/PIMBlock.h` and `src/PIMBlock.cpp`.

Each PIM block has eight 256-bit GRF-A registers, eight GRF-B registers, one
SRF burst, `M_OUT`, and `A_OUT`. In FP16 mode a burst contains 16 lanes. The
operations are lane-wise:

* `ADD`: `dst = src0 + src1`
* `MUL`: `dst = src0 * src1`
* `MAC`: `dst = src0 * src1 + old(dst)`
* `MAD`: `dst = src0 * src1 + src2`

The RTL retains these exact visible semantics. It adds a valid/ready command
interface because a finite circuit cannot use the simulator's instantaneous
method calls.

### 2.3 System sizing

Source: `system_hbm_64ch.ini` and `ini/HBM2_samsung_2M_16B_x64.ini`.

The reference configuration has 64 channels, 16 DRAM banks per rank, eight
bank-side PIM blocks per channel, 16 logic PCUs, two-cycle logic-PCU latency,
64 B/cycle logic and hierarchy bandwidth, a 65,536-byte shared weight buffer,
and a 128-entry broadcast-mask queue. DRAM timing defaults are tRCDRD=14,
tRCDWR=10, tRAS=33, and tRP=14 cycles.

### 2.4 Logic scheduling

Source: `src/LogicDieScheduler.h`, `src/PIMRank.cpp`,
`src/LogicDieWeightBuffer.h`, and `src/LogicDieOutputBuffer.h`.

Commands carry epoch, ordinal, stream/channel identity, and a command
signature. Commands with equal epoch, ordinal, and signature are coalesced by
OR-ing their channel masks. An epoch may issue only after its expected channel
mask is complete. Logic reservations use up to 16 PCUs and account separately
for command overhead, compute waves, and hierarchy transfer cycles.

## 3. Hardware decisions where the simulator is abstract

### 3.1 DRAM storage model

The C++ `Bank` is sparse software storage, not a circuit. The RTL therefore
uses a parameterised, finite bank/row/column behavioural memory with one open
row per bank and ACT/RD/WR/PRE/REF commands. Timing counters enforce tRCD,
tRAS, and tRP. This is a verification model and controller-interface reference;
it is not intended to synthesise into real DRAM cells.

### 3.2 Backpressure and atomicity

All state-changing commands use ready/valid. A command is accepted only when
its operands are available and its destination can commit. Results remain
stable while downstream ready is low. This prevents the partial updates that
would otherwise occur when queues fill.

### 3.3 Arithmetic pipelines

FP16 and INT8 share a PCU shell but have distinct datapaths. FP16 uses the
project's bit-level FP16 adder plus a bit-level multiplier; INT8 multiplies
signed bytes and accumulates into signed 32-bit lanes. Pipeline valid and
metadata advance together. No claim of fused single-rounding FMA is made:
matching `PIMBlock.cpp`, FP16 MAC performs a rounded multiply followed by a
rounded add.

### 3.4 Reset and memory inference

Only valid bits, pointers, and control state are reset. Large payload arrays are
not asynchronously cleared. Their contents are ignored until valid, allowing
SRAM inference in a standard-cell flow and avoiding reset fanout across the
entire weight/accumulator storage.

## 4. Verification obligations

The regression must cover command decode, FP16 special and ordinary values,
INT8 signed MAC, CRF control flow, DRAM legal/illegal timing, bank result
backpressure, epoch-mask completion, 16-PCU simultaneous issue, weight-buffer
read/write, cross-channel reduction, and prolonged random output stalls. Passing
small unit tests alone is not evidence for the integrated 64-channel contract.

## 4.1 Implemented hierarchy and rationale

`dram_bank_array_model` implements the finite ACT/RD/WR/PRE/REF state and also
provides internal PIM row-buffer read ports. The latter are not an external HBM
pin interface: they model the simulator's direct `rank->banks[pb*2]` and
`rank->banks[pb*2+1]` operand reads. Each `bank_side_pim_subsystem` consequently
pairs two DRAM banks with one PIM block, matching `PIMRank.cpp`.

The bank CRF is shared across the eight blocks in a channel. A command advances
only when every block is ready. This lockstep rule follows the simulator loop
that calls `doPIMBlock` for every PIM block for one CRF command, while adding the
atomicity needed when one hardware result port is stalled.

`logic_command_coalescer` stores at most 128 open contexts, the conservative
capacity selected by the simulator experiments. Equality is defined by epoch,
ordinal, and signature; command and expected-mask mismatches are errors. A
command becomes dispatchable only when its received channel mask exactly equals
the expected mask.

`logic_die_pim_top` stores one operand context per channel and converts a
completed channel mask into waves of at most 16 requests. `logic_pcu_scheduler`
uses a fixed issue-port-to-PCU mapping because the wave builder already produces
unique ports. This removes a combinational ready crossbar and still permits all
16 PCUs to accept work in the same cycle. The PCUs retain result and tag data
under output backpressure.

`channel_tsv_interconnect` has two independently stalled 256-bit lanes. This is
64 B/cycle when both transfer, matching `HIERARCHY_PIM_BW=64`. Unlike the older
dual arbiter, one blocked lane does not intentionally suppress the other lane.

`full_pim_system_top` is the integration boundary. It instantiates a DRAM and
bank-PIM subsystem per channel, arbitrates the eight block results, then routes
each channel either directly to the TSV interface or into the logic-die operand
context according to the placement input.

## 4.2 Final stabilization results (2026-08-06)

The self-checking `rtl/run_full_pim_tests.sh` regression currently covers:

* FP16 multiply, MAC, MAD, signed multiply, and `0 * infinity` NaN handling;
* signed INT8 MAC;
* rejection of a DRAM read before tRCD and successful ACT/WR/RD/PRE data flow;
* two bank PIM blocks executing one CRF ADD in lockstep;
* four channel commands coalescing and completing through a two-PCU, two-wave
  reduced test configuration;
* epoch/barrier, 64-KiB buffer, coalescer duplicate/context errors, and reduction;
* all 16 PCUs accepting work simultaneously;
* integrated direct-TSV and bank-to-logic-die paths; and
* 40 randomized batches producing 320 checked results under backpressure.

An initial regression exposed an incorrect special-value priority in FP16
multiplication (`0 * infinity` returned zero). NaN classification now precedes
zero classification. A second stabilization run exposed an avoidable
combinational ready crossbar in the scheduler; fixed port mapping removed the
delta-cycle loop while preserving simultaneous issue.

The full regression contains eight self-checking testbenches and all eight pass.
Yosys fully synthesizes `bank_pim_core` (32-bit scaled configuration, 22,653
generic cells) and `logic_pcu_scheduler` (two-PCU scaled configuration, 28,786
generic cells), with `check` reporting zero problems. The integrated two-channel
top passes hierarchy elaboration and structural `check` with zero problems
(7,031 hierarchical cells). It is intentionally not flattened through the
behavioural DRAM array: that array is a verification model, not a DRAM macro.

Synthesis found two additional parameterization defects: a narrow test vector
could index beyond the SRF, and the 64-KiB weight-buffer address was fixed at the
256-bit width. SRF selection now wraps within the implemented lane count and
the address width is derived from bytes divided by vector bytes. Regressions
were rerun after both fixes. Remaining Yosys memory-to-register messages are
inference notices, not structural errors.

## 4.3 Reproduction

Run `bash rtl/run_full_pim_tests.sh` for functional tests and
`bash rtl/run_full_pim_synthesis.sh` for structural/synthesis checks. Logs and
the summary CSV are written to `experiment/results/full_pim_rtl/`.

## 5. External literature

No external paper is used for the initial functional contract. The command and
compute behaviour above is derived from the simulator sources bundled with this
repository. If physical DRAM protocols or published PIM microarchitectures are
used in later implementation decisions, their bibliographic details and the
specific adopted rule will be added here.
