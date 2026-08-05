#!/usr/bin/env python3
import csv
from collections import deque
from pathlib import Path

CHANNELS = 64
SOURCES_PER_CHANNEL = 8
LINK_LANES = 2
TRACE = Path("experiment/results/depthwise_actual_payload_trace.csv.payload.csv")
OUTPUT = Path("experiment/results/shared_pipeline_64ch_trace_replay.csv")


def load_events():
    with TRACE.open(newline="") as trace_file:
        events = []
        for row in csv.DictReader(trace_file):
            events.append(
                {
                    "cycle": int(row["cycle"]),
                    "channel": int(row["channel"]),
                    "source": int(row["pim_block"]),
                    "key": int(row["key"]),
                    "tap": int(row["tap_index"]),
                }
            )
    events.sort(key=lambda event: (event["cycle"], event["channel"], event["source"]))
    return events


def choose_round_robin(valid, start, limit):
    chosen = []
    for offset in range(len(valid)):
        index = (start + offset) % len(valid)
        if valid[index]:
            chosen.append(index)
            if len(chosen) == limit:
                break
    return chosen


def replay(events, pipelines):
    queues = [[deque() for _ in range(SOURCES_PER_CHANNEL)] for _ in range(CHANNELS)]
    final_slots = [[None] * SOURCES_PER_CHANNEL for _ in range(CHANNELS)]
    scheduler_rr = [0] * CHANNELS
    local_link_rr = [0] * CHANNELS
    global_link_rr = 0
    tap_counts = {}
    source_peak = [[0] * SOURCES_PER_CHANNEL for _ in range(CHANNELS)]
    channel_peak = [0] * CHANNELS
    event_index = 0
    first_cycle = events[0]["cycle"]
    cycle = first_cycle
    grants = finals = full_link_cycles = partial_link_cycles = idle_link_cycles = 0
    queued_request_cycles = scheduler_stall_source_cycles = final_backpressure_cycles = 0

    while True:
        while event_index < len(events) and events[event_index]["cycle"] <= cycle:
            event = events[event_index]
            queue = queues[event["channel"]][event["source"]]
            queue.append(event)
            source_peak[event["channel"]][event["source"]] = max(
                source_peak[event["channel"]][event["source"]], len(queue)
            )
            event_index += 1

        for channel in range(CHANNELS):
            channel_depth = sum(len(queue) for queue in queues[channel])
            channel_peak[channel] = max(channel_peak[channel], channel_depth)
            queued_request_cycles += channel_depth

        local_selected = [None] * CHANNELS
        channel_valid = [False] * CHANNELS
        for channel in range(CHANNELS):
            valid = [slot is not None for slot in final_slots[channel]]
            selected = choose_round_robin(valid, local_link_rr[channel], 1)
            if selected:
                local_selected[channel] = selected[0]
                channel_valid[channel] = True

        drained_channels = choose_round_robin(channel_valid, global_link_rr, LINK_LANES)
        if len(drained_channels) == LINK_LANES:
            full_link_cycles += 1
        elif drained_channels:
            partial_link_cycles += 1
        else:
            idle_link_cycles += 1
        for channel in drained_channels:
            source = local_selected[channel]
            final_slots[channel][source] = None
            local_link_rr[channel] = (source + 1) % SOURCES_PER_CHANNEL
            finals += 1
        if drained_channels:
            global_link_rr = (drained_channels[-1] + 1) % CHANNELS

        for channel in range(CHANNELS):
            eligible = []
            for source in range(SOURCES_PER_CHANNEL):
                if not queues[channel][source]:
                    eligible.append(False)
                    continue
                event = queues[channel][source][0]
                blocked_final = event["tap"] == 3 and final_slots[channel][source] is not None
                if blocked_final:
                    final_backpressure_cycles += 1
                eligible.append(not blocked_final)
            ready_sources = sum(eligible)
            scheduler_stall_source_cycles += max(0, ready_sources - pipelines)
            selected = choose_round_robin(eligible, scheduler_rr[channel], pipelines)
            for source in selected:
                event = queues[channel][source].popleft()
                count = tap_counts.get(event["key"], 0) + 1
                tap_counts[event["key"]] = count
                if count != event["tap"]:
                    raise RuntimeError(f"tap order mismatch for key {event['key']}")
                if event["tap"] == 3:
                    final_slots[channel][source] = event["key"]
                grants += 1
            if selected:
                scheduler_rr[channel] = (selected[-1] + 1) % SOURCES_PER_CHANNEL

        done = (
            event_index == len(events)
            and grants == len(events)
            and finals == len(events) // 3
            and all(slot is None for channel in final_slots for slot in channel)
        )
        if done:
            break
        cycle += 1
        if cycle - first_cycle > 100000:
            raise RuntimeError("shared pipeline replay did not converge")

    return {
        "pipelines_per_channel": pipelines,
        "partial_grants": grants,
        "final_bursts": finals,
        "replay_cycles": cycle - first_cycle + 1,
        "full_link_cycles": full_link_cycles,
        "partial_link_cycles": partial_link_cycles,
        "idle_link_cycles": idle_link_cycles,
        "peak_source_fifo": max(max(row) for row in source_peak),
        "peak_channel_fifo": max(channel_peak),
        "queued_request_cycles": queued_request_cycles,
        "scheduler_stall_source_cycles": scheduler_stall_source_cycles,
        "final_backpressure_cycles": final_backpressure_cycles,
    }


def main():
    events = load_events()
    rows = [replay(events, pipelines) for pipelines in (1, 2, 4)]
    with OUTPUT.open("w", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print("SHARED_PIPELINE_64CH_TRACE_REPLAY PASS")
    for row in rows:
        print(" ".join(f"{key}[{value}]" for key, value in row.items()))


if __name__ == "__main__":
    main()
