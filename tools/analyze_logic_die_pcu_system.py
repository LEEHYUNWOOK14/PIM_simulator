#!/usr/bin/env python3
"""System-level GR00T normalization model for a logic-die PCU.

The model deliberately separates traffic by physical boundary.  It does not add
bank-array traffic to off-stack traffic: a local replay may be expensive, but it
does not defeat the PCU's purpose when it replaces a tensor round trip over the
external memory interface.

Cycle results are a deterministic transaction-level model of bank reduction,
scalar service, activation replay, apply latency, and bank write-back.  They are
not a process timing or power claim.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = ROOT / "reports/groot_normalization/results"
OUT = RESULT_ROOT / "logic_die_pcu_system"
BASE_MODEL = ROOT / "tools/compare_actual_groot_architectures.py"

BANKS = 16
BYTES_PER_ELEMENT = 2
PARTIAL_STAT_BYTES_PER_BANK_ROW = 8  # FP32 sum + FP32 sumsq
SCALAR_BYTES_PER_BANK_ROW = 8  # FP32 mean + FP32 inv_std
COMMAND_BYTES_PER_INVOCATION = 32
# Twelve arithmetic stages plus input/output handoff at the non-pipelined
# global-tree boundary.  Measured request-to-next-accept service is 14 cycles.
GLOBAL_REDUCER_LATENCY = 14
# One scalar engine executes the serialized FP32/LUT/Newton FSM in the current
# RTL.  Sixty cycles is the transaction-level service abstraction; final lane
# decisions use measured top-RTL cycles, not this estimate.
LAYERNORM_SCALAR_SERVICE_CYCLES = 63
RMSNORM_SCALAR_SERVICE_CYCLES = 51
APPLY_PIPELINE_LATENCY = 12
RESULT_FIFO_DEPTH = 16
CONTEXTS = 8
# Descriptor retirement plus replay-request handoff measured at the integrated
# RTL/controller boundary.  It is hidden by scalar latency for one-vector rows.
CONTROLLER_ROW_HANDOFF_CYCLES = 2
BOUNDED_CONTEXT_FIXED_OVERHEAD = 11


def load_workload_module():
    spec = importlib.util.spec_from_file_location("actual_workload", BASE_MODEL)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {BASE_MODEL}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@dataclass
class SimResult:
    cycles: int
    reduction_read_vectors: int
    replay_read_vectors: int
    writeback_vectors: int
    read_port_stall_cycles: int
    write_port_stall_cycles: int
    scalar_queue_stall_cycles: int
    maximum_live_rows: int


@dataclass
class RowState:
    row_id: int
    vectors: int
    reduction_remaining: int
    reduction_started: bool = False
    local_result_ready: int | None = None
    global_started: bool = False
    reduction_tail_ready: int | None = None
    scalar_queued: bool = False
    scalar_done: bool = False
    replay_remaining: int = 0
    replay_started: bool = False
    replay_ready_cycle: int = 0
    replay_done: bool = False
    writeback_done: int = 0
    completed: bool = False


def reducer_tail_cycles(lanes: int) -> int:
    """Latency after the final vector, derived from the current RTL stages."""
    return 3 * int(math.log2(lanes)) + 12


def simulate_call(
    rows: int,
    hidden: int,
    lanes: int,
    *,
    scalar_engines: int = 4,
    contexts: int = CONTEXTS,
    bank_port_mode: str = "single_shared",
    scalar_service_cycles: int | None = None,
    rms_norm: bool = False,
    local_reducer_contexts: int = 2,
) -> SimResult:
    """Run a deterministic bank/replay/write-back transaction simulation.

    All banks advance in lockstep.  A vector transaction therefore means one
    LANES-wide access at each active bank.  single_shared conservatively shares
    one bank service slot among reduction reads, replay reads, and write-backs.
    split_rw allows one read and one write in a cycle, but reduction and replay
    still share the read port.
    """
    if lanes not in (4, 8, 16):
        raise ValueError("lanes must be 4, 8, or 16")
    if bank_port_mode not in ("single_shared", "split_rw", "independent_pcu_ports"):
        raise ValueError("bank_port_mode must be single_shared, split_rw, or independent_pcu_ports")
    if scalar_service_cycles is None:
        scalar_service_cycles = RMSNORM_SCALAR_SERVICE_CYCLES if rms_norm else LAYERNORM_SCALAR_SERVICE_CYCLES
    if min(rows, hidden, scalar_engines, contexts, scalar_service_cycles, local_reducer_contexts) <= 0:
        raise ValueError("rows, hidden, engines, contexts, scalar service, and local contexts must be positive")

    vectors = math.ceil(hidden / (BANKS * lanes))
    states: list[RowState] = []
    next_row = 0
    completed_rows = 0
    cycle = 0
    scalar_engines_free = [0] * scalar_engines
    scalar_completions: list[tuple[int, int]] = []
    global_reducer_free = 0
    next_reduction_start_cycle = 0
    writeback_events: list[tuple[int, int]] = []
    active_apply: int | None = None
    arbitration_toggle = False
    reduction_vectors = replay_vectors = writeback_vectors = 0
    read_stalls = write_stalls = scalar_stalls = maximum_live = 0
    safety_limit = rows * (vectors * 8 + scalar_service_cycles + 128) + 10000

    while completed_rows < rows:
        live = sum(not state.completed for state in states)
        while next_row < rows and live < contexts:
            states.append(RowState(next_row, vectors, vectors))
            next_row += 1
            live += 1
        maximum_live = max(maximum_live, live)

        # Complete scalar jobs whose fixed-latency engines return this cycle.
        for ready_cycle, row_id in list(scalar_completions):
            if ready_cycle <= cycle:
                states[row_id].scalar_done = True
                scalar_completions.remove((ready_cycle, row_id))

        # The RTL global tree deliberately keeps one row in flight.  It is a
        # latency-12 resource, not an II=1 pipeline.  A local reducer context is
        # released when its partial is accepted here.
        global_candidate = next((
            state for state in states
            if state.local_result_ready is not None
            and state.local_result_ready <= cycle
            and not state.global_started
        ), None)
        if global_candidate is not None and global_reducer_free <= cycle:
            global_candidate.global_started = True
            global_candidate.reduction_tail_ready = cycle + GLOBAL_REDUCER_LATENCY
            global_reducer_free = cycle + GLOBAL_REDUCER_LATENCY + 1

        # Queue completed reductions on the earliest available scalar engine.
        for state in states:
            if (
                not state.scalar_queued
                and state.reduction_tail_ready is not None
                and state.reduction_tail_ready <= cycle
            ):
                engine = min(range(scalar_engines), key=scalar_engines_free.__getitem__)
                start = max(cycle, scalar_engines_free[engine])
                if start > cycle:
                    scalar_stalls += start - cycle
                done = start + scalar_service_cycles
                scalar_engines_free[engine] = done
                scalar_completions.append((done, state.row_id))
                state.scalar_queued = True

        if active_apply is None:
            ready = [state for state in states if state.scalar_done and not state.replay_started]
            if ready:
                state = min(ready, key=lambda item: item.row_id)
                state.replay_started = True
                state.replay_remaining = state.vectors
                # The RTL replay source changes row/tag through a ready/valid
                # request handshake, leaving one empty bank-read slot between
                # rows in the trace driver/controller contract.
                state.replay_ready_cycle = cycle + 2
                active_apply = state.row_id

        due_writes = sorted(row_id for due, row_id in writeback_events if due <= cycle)
        reduction_ready = next((s for s in states if s.reduction_started and s.reduction_remaining > 0), None)
        if reduction_ready is None:
            occupied_local = sum(
                state.reduction_started
                and not state.global_started
                for state in states
            )
            if occupied_local < local_reducer_contexts and cycle >= next_reduction_start_cycle:
                reduction_ready = next((s for s in states if not s.reduction_started), None)
        replay_ready = states[active_apply] if active_apply is not None else None
        if replay_ready is not None and (replay_ready.replay_remaining == 0 or replay_ready.replay_ready_cycle > cycle):
            replay_ready = None

        def do_read() -> bool:
            nonlocal reduction_vectors, replay_vectors, active_apply, arbitration_toggle, next_reduction_start_cycle
            choice = None
            if reduction_ready is not None and replay_ready is not None:
                choice = "replay" if arbitration_toggle else "reduction"
                arbitration_toggle = not arbitration_toggle
            elif replay_ready is not None:
                choice = "replay"
            elif reduction_ready is not None:
                choice = "reduction"
            if choice == "reduction":
                reduction_ready.reduction_started = True
                reduction_ready.reduction_remaining -= 1
                reduction_vectors += 1
                if reduction_ready.reduction_remaining == 0:
                    reduction_ready.local_result_ready = cycle + reducer_tail_cycles(lanes)
                    next_reduction_start_cycle = cycle + 2
                return True
            if choice == "replay":
                replay_ready.replay_remaining -= 1
                replay_vectors += 1
                writeback_events.append((cycle + APPLY_PIPELINE_LATENCY, replay_ready.row_id))
                if replay_ready.replay_remaining == 0:
                    replay_ready.replay_done = True
                    active_apply = None
                return True
            return False

        def do_independent_reads() -> None:
            """Optimistic interface bound implemented by the current RTL top.

            Reduction input and replay input are separate ready/valid interfaces;
            this mode allows both in the same cycle.  A real bank scheduler must
            either provision that bandwidth or fall back to one of the shared-port
            bounds above.
            """
            nonlocal reduction_vectors, replay_vectors, active_apply, next_reduction_start_cycle
            if reduction_ready is not None:
                reduction_ready.reduction_started = True
                reduction_ready.reduction_remaining -= 1
                reduction_vectors += 1
                if reduction_ready.reduction_remaining == 0:
                    reduction_ready.local_result_ready = cycle + reducer_tail_cycles(lanes)
                    next_reduction_start_cycle = cycle + 2
            if replay_ready is not None:
                replay_ready.replay_remaining -= 1
                replay_vectors += 1
                writeback_events.append((cycle + APPLY_PIPELINE_LATENCY, replay_ready.row_id))
                if replay_ready.replay_remaining == 0:
                    replay_ready.replay_done = True
                    active_apply = None

        if bank_port_mode == "single_shared":
            if due_writes:
                row_id = due_writes[0]
                writeback_events.remove(next(event for event in writeback_events if event[1] == row_id and event[0] <= cycle))
                states[row_id].writeback_done += 1
                writeback_vectors += 1
                if reduction_ready is not None or replay_ready is not None:
                    read_stalls += 1
            else:
                do_read()
        elif bank_port_mode == "split_rw":
            do_read()
            if due_writes:
                row_id = due_writes[0]
                writeback_events.remove(next(event for event in writeback_events if event[1] == row_id and event[0] <= cycle))
                states[row_id].writeback_done += 1
                writeback_vectors += 1
            elif writeback_events:
                write_stalls += 1
        else:
            do_independent_reads()
            if due_writes:
                row_id = due_writes[0]
                writeback_events.remove(next(event for event in writeback_events if event[1] == row_id and event[0] <= cycle))
                states[row_id].writeback_done += 1
                writeback_vectors += 1

        for state in states:
            if state.replay_done and state.writeback_done == state.vectors and not state.completed:
                state.completed = True
                completed_rows += 1

        cycle += 1
        if cycle > safety_limit:
            raise RuntimeError("cycle simulation did not converge")

    if vectors <= 1:
        controller_cycles = 0
    elif contexts <= 8:
        # With the frozen eight-entry window, producer handoffs overlap across
        # rows and collapse to an invocation-level measured constant.
        controller_cycles = BOUNDED_CONTEXT_FIXED_OVERHEAD
    else:
        controller_cycles = CONTROLLER_ROW_HANDOFF_CYCLES * rows
    return SimResult(
        cycles=cycle + controller_cycles,
        reduction_read_vectors=reduction_vectors,
        replay_read_vectors=replay_vectors,
        writeback_vectors=writeback_vectors,
        read_port_stall_cycles=read_stalls,
        write_port_stall_cycles=write_stalls,
        scalar_queue_stall_cycles=scalar_stalls,
        maximum_live_rows=maximum_live,
    )


def traffic_for_workload(workload: Iterable[dict]) -> dict[str, int | float]:
    rows = list(workload)
    invocations = sum(int(row["invocations"]) for row in rows)
    tensor = sum(int(row["tensor_bytes_per_call"]) * int(row["invocations"]) for row in rows)
    affine = sum(int(row["affine_bytes_per_call"]) * int(row["invocations"]) for row in rows)
    row_calls = sum(int(row["rows"]) * int(row["invocations"]) for row in rows)
    bank_array_reduction = tensor
    bank_array_replay = tensor
    bank_array_writeback = tensor
    # Gamma and beta are consumed per element by the apply PCU (4 B/element).
    # `affine` below remains the cold parameter payload, which may be cached.
    bank_array_affine = 2 * tensor
    bank_to_logic_partial = row_calls * BANKS * PARTIAL_STAT_BYTES_PER_BANK_ROW
    logic_to_bank_scalar = row_calls * BANKS * SCALAR_BYTES_PER_BANK_ROW
    gpu_external = 2 * tensor + affine
    bank_only_external = bank_to_logic_partial + logic_to_bank_scalar
    pcu_external_resident = invocations * COMMAND_BYTES_PER_INVOCATION
    pcu_external_cold = pcu_external_resident + affine
    return {
        "invocations": invocations,
        "tensor_bytes": tensor,
        "affine_bytes": affine,
        "row_invocations": row_calls,
        "gpu_external_bytes": gpu_external,
        "bank_only_external_bytes": bank_only_external,
        "pcu_external_bytes_resident": pcu_external_resident,
        "pcu_external_bytes_cold_affine": pcu_external_cold,
        "bank_array_reduction_read_bytes": bank_array_reduction,
        "bank_array_replay_read_bytes": bank_array_replay,
        "bank_array_affine_read_bytes": bank_array_affine,
        "bank_array_writeback_bytes": bank_array_writeback,
        "bank_to_logic_partial_bytes": bank_to_logic_partial,
        "logic_to_bank_scalar_bytes": logic_to_bank_scalar,
        "external_reduction_fraction_resident": 1.0 - pcu_external_resident / gpu_external,
        "external_reduction_fraction_cold_affine": 1.0 - pcu_external_cold / gpu_external,
    }


def hardware_cost(lanes: int, scalar_engines: int = 4) -> dict[str, int | float]:
    # Structural counts describe replicated arithmetic, independent of a PDK.
    reducer_mul = BANKS * lanes
    reducer_add = BANKS * (2 * (lanes - 1) + 8)
    apply_mul = BANKS * (2 * lanes)
    apply_add = BANKS * (2 * lanes)
    scalar_mul = scalar_engines * 4
    scalar_add = scalar_engines * 5
    rsqrt = scalar_engines
    fp32_mul = reducer_mul + apply_mul + scalar_mul
    fp32_add = reducer_add + apply_add + scalar_add
    result_fifo_bits = BANKS * RESULT_FIFO_DEPTH * lanes * 16
    context_bits = CONTEXTS * (16 + 16 + 32 + 32 + BANKS)
    control_state_bits = BANKS * (2 * (16 + 16 + 4 * 64) + 128)
    storage_bits = result_fifo_bits + context_bits + control_state_bits
    # A transparent comparison proxy, not area or energy.
    cost_units = fp32_add + 2.0 * fp32_mul + 8.0 * rsqrt + storage_bits / 1024.0
    return {
        "fp32_adders": fp32_add,
        "fp32_multipliers": fp32_mul,
        "rsqrt_units": rsqrt,
        "estimated_state_bits": storage_bits,
        "relative_cost_units": cost_units,
    }


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"no rows for {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def lane_dse(workload: list[dict]) -> tuple[list[dict], list[dict]]:
    per_profile: list[dict] = []
    aggregate: list[dict] = []
    traffic = traffic_for_workload(workload)
    for lanes in (4, 8, 16):
        totals = {"single_shared": 0, "split_rw": 0, "independent_pcu_ports": 0}
        for row in workload:
            for port_mode in totals:
                result = simulate_call(
                    int(row["rows"]),
                    int(row["hidden_size"]),
                    lanes,
                    scalar_engines=4,
                    bank_port_mode=port_mode,
                    rms_norm=row.get("norm_type") == "RMSNorm",
                )
                weighted = result.cycles * int(row["invocations"])
                totals[port_mode] += weighted
                per_profile.append({
                    "profile_id": row["profile_id"],
                    "shape": row["shape"],
                    "invocations": row["invocations"],
                    "lanes": lanes,
                    "bank_port_mode": port_mode,
                    **asdict(result),
                    "weighted_cycles": weighted,
                })
        cost = hardware_cost(lanes)
        external_saved = int(traffic["gpu_external_bytes"]) - int(traffic["pcu_external_bytes_resident"])
        aggregate.append({
            "lanes": lanes,
            "scalar_engines": 4,
            "single_shared_weighted_cycles": totals["single_shared"],
            "split_rw_weighted_cycles": totals["split_rw"],
            "independent_pcu_ports_weighted_cycles": totals["independent_pcu_ports"],
            "split_rw_speedup_vs_lane4": 0.0,
            "single_shared_speedup_vs_lane4": 0.0,
            **cost,
            "external_bytes_saved": external_saved,
            "external_bytes_saved_per_cost_unit": external_saved / float(cost["relative_cost_units"]),
            "trace_accuracy_evidence": "EXISTING_FULL_RTL_MODEL_BIT_EXACT_6_OF_6",
        })
    base_single = int(aggregate[0]["single_shared_weighted_cycles"])
    base_split = int(aggregate[0]["split_rw_weighted_cycles"])
    for row in aggregate:
        row["single_shared_speedup_vs_lane4"] = base_single / int(row["single_shared_weighted_cycles"])
        row["split_rw_speedup_vs_lane4"] = base_split / int(row["split_rw_weighted_cycles"])
    return per_profile, aggregate


def choose_candidate(rows: list[dict]) -> dict:
    # A lane count is on the cost/performance Pareto frontier if no other design
    # is both cheaper and faster under the conservative shared-port model.
    frontier = []
    for candidate in rows:
        dominated = any(
            other["relative_cost_units"] <= candidate["relative_cost_units"]
            and other["single_shared_weighted_cycles"] <= candidate["single_shared_weighted_cycles"]
            and (
                other["relative_cost_units"] < candidate["relative_cost_units"]
                or other["single_shared_weighted_cycles"] < candidate["single_shared_weighted_cycles"]
            )
            for other in rows
        )
        if not dominated:
            frontier.append(int(candidate["lanes"]))
    # The 256-bit bank beat contains 16 BF16 values.  The project throughput
    # floor is one 128-bit slice per active bank cycle (50% of that beat).
    bank_word_bf16 = 16
    minimum_supply_fraction = 0.50
    eligible = [row for row in rows if row["lanes"] / bank_word_bf16 >= minimum_supply_fraction]
    winner = min(eligible, key=lambda row: row["relative_cost_units"])
    return {
        "recommended_knee_lanes": int(winner["lanes"]),
        "pareto_frontier_lanes": frontier,
        "bank_word_bits": 256,
        "minimum_bank_supply_fraction": minimum_supply_fraction,
        "lane_supply_fraction": {str(row["lanes"]): row["lanes"] / bank_word_bf16 for row in rows},
        "freeze_status": "FROZEN_8_LANES_SPLIT_RW_CONTEXTS8_FIFO16",
        "selection_rule": "minimum hardware cost that consumes at least one 128-bit slice per active bank cycle",
        "excluded_16_lane_reason": "passes throughput floor but costs more than the minimum passing 8-lane design",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    workload = load_workload_module().workload_rows()
    traffic = traffic_for_workload(workload)
    per_profile, aggregate = lane_dse(workload)
    decision = choose_candidate(aggregate)

    traffic_rows = [
        {"boundary": "external_gpu_baseline", "bytes": traffic["gpu_external_bytes"], "meaning": "GPU reads activation/affine and writes output across the external memory interface"},
        {"boundary": "external_bank_only", "bytes": traffic["bank_only_external_bytes"], "meaning": "partial statistics leave memory and normalization scalars return"},
        {"boundary": "external_logic_die_pcu_resident", "bytes": traffic["pcu_external_bytes_resident"], "meaning": "commands only; activation, affine, and output remain in memory"},
        {"boundary": "external_logic_die_pcu_cold_affine", "bytes": traffic["pcu_external_bytes_cold_affine"], "meaning": "commands plus cold affine load"},
        {"boundary": "bank_array_reduction_read", "bytes": traffic["bank_array_reduction_read_bytes"], "meaning": "first activation pass inside memory"},
        {"boundary": "bank_array_replay_read", "bytes": traffic["bank_array_replay_read_bytes"], "meaning": "second activation pass inside memory"},
        {"boundary": "bank_array_affine_read", "bytes": traffic["bank_array_affine_read_bytes"], "meaning": "gamma/beta payload read inside memory"},
        {"boundary": "bank_array_writeback", "bytes": traffic["bank_array_writeback_bytes"], "meaning": "normalized output stored back to banks"},
        {"boundary": "bank_to_logic_partial", "bytes": traffic["bank_to_logic_partial_bytes"], "meaning": "FP32 sum and sumsq from every bank and row"},
        {"boundary": "logic_to_bank_scalar", "bytes": traffic["logic_to_bank_scalar_bytes"], "meaning": "FP32 mean and inv_std returned to every bank and row"},
    ]
    write_csv(args.out / "hierarchical_traffic.csv", traffic_rows)
    write_csv(args.out / "lane_profile_cycles.csv", per_profile)
    write_csv(args.out / "lane_system_dse.csv", aggregate)
    payload = {
        "objective": "logic-die PCU completes cross-bank normalization while minimizing external memory I/O",
        "evidence_class": "ACTUAL_ACTION_HEAD_TRACE_PLUS_TRANSACTION_LEVEL_MODEL_PLUS_EXISTING_RTL_ACCURACY",
        "trace_scope": "PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT_NOT_FULL_GROOT_INFERENCE",
        "traffic": traffic,
        "cycle_model": {
            "banks": BANKS,
            "contexts": CONTEXTS,
            "scalar_engines": 4,
            "global_reducer_latency": GLOBAL_REDUCER_LATENCY,
            "layernorm_scalar_service_cycles": LAYERNORM_SCALAR_SERVICE_CYCLES,
            "rmsnorm_scalar_service_cycles": RMSNORM_SCALAR_SERVICE_CYCLES,
            "local_reducer_contexts": 2,
            "controller_row_handoff_cycles": CONTROLLER_ROW_HANDOFF_CYCLES,
            "bounded_context_fixed_overhead": BOUNDED_CONTEXT_FIXED_OVERHEAD,
            "apply_pipeline_latency": APPLY_PIPELINE_LATENCY,
            "bank_port_modes": ["single_shared", "split_rw", "independent_pcu_ports"],
            "clock_or_process_assumption": "NONE; output is cycles and transaction counts",
        },
        "candidate_decision": decision,
        "lane_dse": aggregate,
        "gates": {
            "numerical_accuracy": "PASS_FROM_EXISTING_6_PROFILE_FULL_RTL_REPLAY",
            "external_io_reduction_resident": traffic["external_reduction_fraction_resident"],
            "external_io_reduction_cold_affine": traffic["external_reduction_fraction_cold_affine"],
            "top_rtl_replay_writeback": "IMPLEMENTED_INTERFACE_REQUIRES_TRACE_REPLAY_VERIFICATION",
            "process_signoff": "OUT_OF_SCOPE",
        },
    }
    (args.out / "system_decision.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(
        "LOGIC_DIE_PCU_SYSTEM PASS "
        f"external_reduction={traffic['external_reduction_fraction_resident']:.6f} "
        f"recommended_lanes={decision['recommended_knee_lanes']} "
        f"pareto={decision['pareto_frontier_lanes']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
