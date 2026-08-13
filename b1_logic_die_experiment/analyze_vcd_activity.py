#!/usr/bin/env python3
"""Summarize top-level input activity from the B1 RTL VCD."""
from __future__ import annotations
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VCD = ROOT / "artifacts" / "b1_hierarchical.vcd"
INPUTS = {
    "bank_context_key_i", "bank_precision_i", "bank_result_to_logic_i", "clk_i",
    "crf_program_addr_i", "crf_program_data_i", "crf_program_valid_i", "crf_start_i",
    "direct_tsv_ready_i", "dram_bank_i", "dram_cmd_i", "dram_cmd_valid_i", "dram_col_i",
    "dram_read_ready_i", "dram_row_i", "dram_write_data_i", "dram_write_mask_i",
    "epoch_begin_id_i", "epoch_begin_valid_i", "epoch_execution_done_i", "epoch_expected_mask_i",
    "epoch_fill_done_channel_i", "epoch_fill_done_valid_i", "logic_accum_i",
    "logic_bank_result_ready_i", "logic_command_channel_i", "logic_command_epoch_i",
    "logic_command_expected_mask_i", "logic_command_ordinal_i", "logic_command_signature_i",
    "logic_command_valid_i", "logic_command_word_i", "logic_host_result_ready_i",
    "logic_result_ready_i", "logic_src1_i", "logic_src2_i", "normalization_begin_rms_norm_i",
    "normalization_begin_tag_i", "normalization_begin_valid_i", "normalization_broadcast_ready_i",
    "normalization_epsilon_i", "normalization_expected_bank_mask_i", "normalization_inv_hidden_i",
    "normalization_partial_bank_i", "normalization_partial_sum_i", "normalization_partial_sumsq_i",
    "normalization_partial_tag_i", "normalization_partial_valid_i", "pim_col_i", "pim_row_i",
    "register_write_bank_i", "register_write_block_i", "register_write_data_i",
    "register_write_index_i", "register_write_valid_i", "rst_ni", "srf_write_block_i",
    "srf_write_data_i", "srf_write_valid_i", "weight_context_commit_i", "weight_context_id_i",
    "weight_read_addr_i", "weight_read_valid_i", "weight_response_ready_i", "weight_write_addr_i",
    "weight_write_data_i", "weight_write_mask_i", "weight_write_valid_i",
}

def bits(value: str, width: int) -> str:
    value = value.lower().replace("x", "0").replace("z", "0")
    return value.zfill(width)[-width:]

lines = VCD.read_text(encoding="utf-8", errors="replace").splitlines()
symbols: dict[str, tuple[str, int]] = {}
for line in lines:
    m = re.match(r"\$var\s+\w+\s+(\d+)\s+(\S+)\s+(\S+)", line)
    if m and m.group(3) in INPUTS:
        symbols[m.group(2)] = (m.group(3), int(m.group(1)))

state: dict[str, str] = {}
transitions = {sym: 0 for sym in symbols}
ones_integral = {sym: 0 for sym in symbols}
last_time = 0
current_time = 0
started = False
for line in lines:
    if line.startswith("#"):
        new_time = int(line[1:])
        if started:
            dt = new_time - current_time
            for sym, val in state.items():
                if sym in symbols:
                    ones_integral[sym] += val.count("1") * dt
        current_time = new_time
        last_time = new_time
        started = True
        continue
    if not started or not line or line[0] == "$":
        continue
    if line[0] in "01xz":
        value, sym = line[0], line[1:]
    elif line[0] in "bB":
        parts = line.split()
        if len(parts) != 2:
            continue
        value, sym = parts[0][1:], parts[1]
    else:
        continue
    if sym not in symbols:
        continue
    width = symbols[sym][1]
    new = bits(value, width)
    old = state.get(sym)
    if old is not None:
        transitions[sym] += sum(a != b for a, b in zip(old, new))
    state[sym] = new

duration_ps = max(last_time, 1)
rows = []
total_trans = total_bit_cycles = weighted_ones = 0.0
cycles = duration_ps / 10_000.0
for sym, (name, width) in symbols.items():
    trans = transitions[sym]
    duty = ones_integral[sym] / (duration_ps * width)
    activity_per_cycle = trans / (width * cycles)
    rows.append({"signal": name, "width": width, "bit_transitions": trans,
                 "activity_per_bit_per_cycle": activity_per_cycle, "duty": duty})
    if name != "clk_i":
        total_trans += trans
        total_bit_cycles += width * cycles
        weighted_ones += duty * width

summary = {
    "work_id": "B1_HIERARCHICAL_41_CYCLE_TRACE",
    "duration_ps": duration_ps,
    "clock_period_ps": 10_000,
    "cycles": cycles,
    "input_bits_excluding_clock": sum(r["width"] for r in rows if r["signal"] != "clk_i"),
    "aggregate_input_activity_per_bit_per_cycle": total_trans / total_bit_cycles,
    "aggregate_input_duty": weighted_ones / sum(r["width"] for r in rows if r["signal"] != "clk_i"),
    "logic_path_active": True,
    "direct_rtl_to_mapped_annotation_pins": 0,
}
(ROOT / "metrics").mkdir(exist_ok=True)
with (ROOT / "metrics" / "b1_vcd_activity.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
(ROOT / "metrics" / "b1_vcd_activity_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
print(json.dumps(summary, indent=2))
