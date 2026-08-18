#!/usr/bin/env python3
"""Audit the B hierarchy, cross-quad packet boundaries, and root reset fanout."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


DEFAULT_TOP = "logic_die_normalization_hbm_quad_local_ab_top"
EXPECTED_COUNTS = {
    # Four root leaves plus hierarchical control, per-bank reduce/apply,
    # quad-reducer, scalar-return, writeback, and HBM-payload leaves.
    "normalization_quad_reset_leaf": 62,
    "normalization_quad_bank_scheduler_leaf": 4,
    "mixed_precision_quad_bank_datapath_slice": 4,
    "mixed_precision_quad_reducer4_pipe": 4,
    "mixed_precision_quad_packet_reducer_pipe": 1,
    "normalization_quad_scalar_packet_leaf": 4,
    "normalization_hbm_quad_payload_store": 4,
}
MAX_MAPPED_RESET_LEAF_SINKS = 20_000
FORBIDDEN = (
    "normalization_bank_scheduler",
    "mixed_precision_global_reducer16_pipe",
    "hierarchical_normalization_bank_core_top",
    "logic_die_normalization_hbm_top",
)


def is_type(value: str, module: str) -> bool:
    return value == module or value == f"\\{module}" or bool(
        re.search(rf"(?:^|\\){re.escape(module)}(?:$|\\)", value)
    )


def resolve_module(modules: dict, module: str) -> str:
    matches = [name for name in modules if is_type(name, module)]
    if len(matches) != 1:
        raise RuntimeError(f"expected one module {module}, found {matches}")
    return matches[0]


def recursive_cell_counts(modules: dict, top: str) -> Counter:
    counts: Counter = Counter()

    def visit(module_name: str) -> None:
        for cell in modules[module_name].get("cells", {}).values():
            cell_type = cell["type"]
            counts[cell_type] += 1
            if cell_type in modules:
                visit(cell_type)

    visit(top)
    return counts


def total_for(counts: Counter, module: str) -> int:
    return sum(count for cell_type, count in counts.items() if is_type(cell_type, module))


def port_width(module: dict, name: str) -> int:
    try:
        return len(module["ports"][name]["bits"])
    except KeyError as error:
        raise RuntimeError(f"missing port {name}") from error


def input_sinks(module: dict, bits: set[object]) -> list[dict]:
    records = []
    for cell_name, cell in module.get("cells", {}).items():
        for port, connection in cell.get("connections", {}).items():
            if cell.get("port_directions", {}).get(port) != "input":
                continue
            overlap = [bit for bit in connection if bit in bits]
            if overlap:
                records.append(
                    {
                        "cell": cell_name,
                        "type": cell["type"],
                        "port": port,
                        "sink_pins": len(overlap),
                    }
                )
    return records


def transparent_reset_owner(modules: dict, top: str) -> tuple[str, set[object]]:
    """Descend through a single integrated wrapper before auditing rst_ni."""
    module_name = top
    bits = set(modules[module_name]["ports"]["rst_ni"]["bits"])
    for _ in range(4):
        sinks = input_sinks(modules[module_name], bits)
        if len(sinks) != 1:
            break
        sink = sinks[0]
        cell = modules[module_name]["cells"][sink["cell"]]
        child = modules.get(cell["type"])
        if child is None or sink["port"] != "rst_ni" or sink["sink_pins"] != 1:
            break
        child_port = child.get("ports", {}).get("rst_ni")
        if child_port is None or len(child_port["bits"]) != 1:
            break
        module_name = cell["type"]
        bits = set(child_port["bits"])
    return module_name, bits


def reset_leaf_fanouts(modules: dict, top: str) -> list[dict]:
    """Count effective flattened sinks of every reset-leaf output.

    The mapping netlist intentionally retains ownership hierarchy, whereas
    OpenROAD flattens it on link.  Recursing through input ports here measures
    the physical sink count without creating a multi-gigabyte flat JSON file.
    """

    memo: dict[tuple[str, object], int] = {}
    active: set[tuple[str, object]] = set()

    def sinks(module_name: str, bit: object) -> int:
        key = (module_name, bit)
        if key in memo:
            return memo[key]
        if key in active:
            raise RuntimeError(f"cycle while tracing {module_name} bit {bit}")
        active.add(key)
        total = 0
        for cell in modules[module_name].get("cells", {}).values():
            directions = cell.get("port_directions", {})
            for port, connection in cell.get("connections", {}).items():
                if directions.get(port) != "input":
                    continue
                for index, connected_bit in enumerate(connection):
                    if connected_bit != bit:
                        continue
                    cell_type = cell["type"]
                    child = modules.get(cell_type)
                    # Library primitives and Yosys internal cells are physical
                    # sinks.  Structural design modules are traversed through
                    # the corresponding input port bit.
                    if child is not None and child.get("cells"):
                        child_port = child.get("ports", {}).get(port)
                        if child_port is None or index >= len(child_port["bits"]):
                            raise RuntimeError(
                                f"cannot map {cell_type}.{port}[{index}]"
                            )
                        total += sinks(cell_type, child_port["bits"][index])
                    else:
                        total += 1
        active.remove(key)
        memo[key] = total
        return total

    records: list[dict] = []

    def visit(module_name: str, path: str) -> None:
        for cell_name, cell in modules[module_name].get("cells", {}).items():
            cell_type = cell["type"]
            cell_path = f"{path}/{cell_name}"
            if is_type(cell_type, "normalization_quad_reset_leaf"):
                bits = cell.get("connections", {}).get("quad_rst_ni_o", [])
                if len(bits) != 1:
                    raise RuntimeError(f"bad reset leaf output at {cell_path}")
                records.append(
                    {
                        "path": cell_path,
                        "owner_module": module_name,
                        "effective_sink_pins": sinks(module_name, bits[0]),
                    }
                )
            child = modules.get(cell_type)
            if child is not None and child.get("cells"):
                visit(cell_type, cell_path)

    visit(top, top)
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--stage", choices=("rtl", "mapped"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--top", default=DEFAULT_TOP)
    parser.add_argument("--require-b2-completion", action="store_true")
    args = parser.parse_args()

    design = json.loads(args.json.read_text(encoding="utf-8"))
    modules = design["modules"]
    top = resolve_module(modules, args.top)
    counts = recursive_cell_counts(modules, top)
    checks: list[dict] = []

    def check(name: str, passed: bool, evidence: object) -> None:
        checks.append(
            {"id": name, "result": "PASS" if passed else "FAIL", "evidence": evidence}
        )

    observed = {}
    for module, expected in EXPECTED_COUNTS.items():
        value = total_for(counts, module)
        observed[module] = value
        check(f"instance_count:{module}", value == expected, {"expected": expected, "actual": value})
    descriptor_count = total_for(
        counts, "normalization_registered_quad_completion_descriptor"
    )
    observed["normalization_registered_quad_completion_descriptor"] = descriptor_count
    if args.require_b2_completion:
        check(
            "registered_quad_completion_descriptor_count",
            descriptor_count == 4,
            {"expected": 4, "actual": descriptor_count},
        )
    for module in FORBIDDEN:
        value = total_for(counts, module)
        observed[module] = value
        check(f"forbidden_absent:{module}", value == 0, {"actual": value})

    # The root asynchronous reset may drive only the four tiny synchronizer
    # leaves.  Local/control resets are derived behind this boundary.
    reset_owner, rst_bits = transparent_reset_owner(modules, top)
    top_module = modules[reset_owner]
    reset_sinks = input_sinks(top_module, rst_bits)
    reset_leaf_sinks = sum(is_type(sink["type"], "normalization_quad_reset_leaf") for sink in reset_sinks)
    check(
        "root_reset_fanout",
        len(reset_sinks) == 4 and reset_leaf_sinks == 4,
        {
            "audited_owner": reset_owner,
            "sink_count": len(reset_sinks),
            "leaf_sink_count": reset_leaf_sinks,
            "sinks": reset_sinks,
        },
    )

    leaf_fanouts = reset_leaf_fanouts(modules, top)
    observed_max = max((row["effective_sink_pins"] for row in leaf_fanouts), default=0)
    fanout_limit = MAX_MAPPED_RESET_LEAF_SINKS if args.stage == "mapped" else None
    fanout_pass = len(leaf_fanouts) == EXPECTED_COUNTS["normalization_quad_reset_leaf"]
    if fanout_limit is not None:
        fanout_pass &= observed_max <= fanout_limit
    check(
        "hierarchical_reset_leaf_fanout",
        fanout_pass,
        {
            "leaf_count": len(leaf_fanouts),
            "mapped_sink_limit": fanout_limit,
            "maximum_effective_sink_pins": observed_max,
            "largest_leaves": sorted(
                leaf_fanouts, key=lambda row: row["effective_sink_pins"], reverse=True
            )[:12],
        },
    )

    slice_name = resolve_module(modules, "mixed_precision_quad_bank_datapath_slice")
    slice_module = modules[slice_name]
    partial_bits = sum(
        port_width(slice_module, port)
        for port in ("partial_valid_o", "partial_ready_i", "partial_tag_o", "partial_sum_o", "partial_sumsq_o")
    )
    scalar_bits = sum(
        port_width(slice_module, port)
        for port in (
            "scalar_packet_valid_i", "scalar_packet_ready_o", "scalar_packet_mode_i",
            "scalar_packet_tag_i", "scalar_packet_mean_i", "scalar_packet_inv_i",
        )
    )
    check(
        "registered_cross_quad_packet_widths",
        partial_bits == 82 and scalar_bits == 83,
        {
            "partial_stat_total_handshake_bits_per_quad": partial_bits,
            "scalar_return_total_handshake_bits_per_quad": scalar_bits,
            "wide_activation_affine_writeback_payload_is_quad_local": True,
        },
    )

    if args.require_b2_completion:
        pcu_name = resolve_module(modules, "logic_die_normalization_quad_local_pcu_top")
        pcu_module = modules[pcu_name]
        writeback_tag_bits = set(pcu_module["ports"]["writeback_tag_o"]["bits"])
        wide_tag_sinks = input_sinks(pcu_module, writeback_tag_bits)
        check(
            "no_central_16bank_writeback_tag_consumers",
            not wide_tag_sinks,
            {
                "writeback_tag_width": len(writeback_tag_bits),
                "internal_sink_pins": sum(row["sink_pins"] for row in wide_tag_sinks),
                "internal_sinks": wide_tag_sinks[:32],
            },
        )

        scheduler_name = resolve_module(modules, "normalization_quad_local_bank_scheduler")
        scheduler_module = modules[scheduler_name]
        completion_tag_width = port_width(scheduler_module, "quad_completion_tag_o")
        completion_valid_width = port_width(scheduler_module, "quad_completion_valid_o")
        check(
            "central_completion_is_one_aggregated_descriptor",
            completion_tag_width == 16 and completion_valid_width == 1,
            {
                "tag_bits": completion_tag_width,
                "valid_bits": completion_valid_width,
                "forbidden_bank_tag_bits": 16 * 16,
                "previous_quad_descriptor_bits": 4 * (16 + 1),
            },
        )

        descriptor_name = resolve_module(
            modules, "normalization_registered_quad_completion_descriptor"
        )
        descriptor_module = modules[descriptor_name]
        descriptor_output_bits = set(
            descriptor_module["ports"]["completion_valid_o"]["bits"]
            + descriptor_module["ports"]["completion_tag_o"]["bits"]
        )
        driven_bits: set[object] = set()
        register_drivers = []
        for cell_name, cell in descriptor_module.get("cells", {}).items():
            cell_outputs = set()
            for port, connection in cell.get("connections", {}).items():
                if cell.get("port_directions", {}).get(port) == "output":
                    cell_outputs.update(bit for bit in connection if bit in descriptor_output_bits)
            if cell_outputs:
                driven_bits.update(cell_outputs)
                register_drivers.append(
                    {"cell": cell_name, "type": cell["type"], "bits": len(cell_outputs)}
                )
        register_like = all(
            re.search(r"(?:dff|df[rst]|__df)", row["type"], re.IGNORECASE)
            for row in register_drivers
        )
        check(
            "quad_completion_descriptor_outputs_are_registered",
            driven_bits == descriptor_output_bits and bool(register_drivers) and register_like,
            {
                "output_bits": len(descriptor_output_bits),
                "registered_driver_bits": len(driven_bits),
                "drivers": register_drivers[:24],
            },
        )

    # Each scheduler leaf and datapath slice must own a disjoint four-bank
    # section of every wide bus.  Shared bits would reveal accidental cross-quad
    # payload stitching at the leaf boundary.
    disjoint_results = []
    for owner_module, child_module, ports in (
        (
            "normalization_quad_local_bank_scheduler",
            "normalization_quad_bank_scheduler_leaf",
            ("reduction_data_i", "replay_x_i", "replay_gamma_i", "replay_beta_i", "core_writeback_data_i"),
        ),
        (
            "mixed_precision_quad_local_multirow_datapath",
            "mixed_precision_quad_bank_datapath_slice",
            ("reduce_data_i", "apply_x_i", "apply_gamma_i", "apply_beta_i", "result_data_o"),
        ),
    ):
        owner_name = resolve_module(modules, owner_module)
        children = [
            cell for cell in modules[owner_name].get("cells", {}).values()
            if is_type(cell["type"], child_module)
        ]
        passed = len(children) == 4
        port_evidence = {}
        for port in ports:
            bit_sets = [set(cell["connections"][port]) for cell in children]
            overlap = sum(
                len(bit_sets[left] & bit_sets[right])
                for left in range(len(bit_sets)) for right in range(left + 1, len(bit_sets))
            )
            widths = [len(bits) for bits in bit_sets]
            port_evidence[port] = {"widths": widths, "cross_quad_overlap_bits": overlap}
            passed &= overlap == 0 and len(set(widths)) == 1
        disjoint_results.append({"owner": owner_module, "children": len(children), "ports": port_evidence})
        check(f"four_disjoint_quad_payload_slices:{owner_module}", passed, disjoint_results[-1])

    overall = all(row["result"] == "PASS" for row in checks)
    payload = {
        "schema_version": 1,
        "stage": args.stage,
        "top": args.top,
        "overall_result": "PASS" if overall else "FAIL",
        "checks": checks,
        "recursive_instance_counts": observed,
        "cross_quad_contract": {
            "reduction_order": "(b0+b1)+(b2+b3), then (q0+q1)+(q2+q3)",
            "registered_partial_stat_packet": True,
            "registered_scalar_return_packet": True,
            "registered_quad_completion_descriptor": args.require_b2_completion,
            "central_16bank_writeback_tag_consumers": 0 if args.require_b2_completion else None,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(
        "WBQ_QUAD_LOCAL_NETLIST_AUDIT "
        f"stage={args.stage} result={payload['overall_result']} "
        f"checks={len(checks)} root_reset_sinks={len(reset_sinks)}"
    )
    return 0 if overall else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"WBQ_QUAD_LOCAL_NETLIST_AUDIT FAIL: {error}", file=sys.stderr)
        raise
