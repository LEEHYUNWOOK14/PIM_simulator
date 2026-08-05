#!/usr/bin/env python3
import csv
import heapq
import sys
from collections import deque
from pathlib import Path


PCU_COUNTS = (16, 32, 64)
SOURCE_DEPTHS = (8, 16, 32)
CENTRAL_DEPTH = 64
STREAMS = 128


def percentile(sorted_values, fraction):
    return sorted_values[int(fraction * (len(sorted_values) - 1))]


def replay(events, pcu_count, source_capacity):
    lane_count = pcu_count // 8
    upstream = [deque() for _ in range(STREAMS)]
    expected_per_stream = [0] * STREAMS
    for event in events:
        stream = int(event["stream_id"])
        upstream[stream].append(event)
        expected_per_stream[stream] += 1

    source = [deque() for _ in range(STREAMS)]
    source_delay = [0] * STREAMS
    source_peak = [0] * STREAMS
    completed_per_stream = [0] * STREAMS
    central = deque()
    free_lanes = list(range(lane_count))
    busy_lanes = []
    starts = []
    rr_stream = 0
    cycle = min(int(event["arrival_cycle"]) for event in events)
    source_full_stream_cycles = source_full_wall_cycles = 0
    central_peak = source_peak_total = max_issue_delay = 0
    issued = started = finished = 0

    def dispatch_ready():
        nonlocal started
        while free_lanes and central:
            lane = free_lanes.pop()
            event, actual_arrival = central.popleft()
            completion = cycle + int(event["service_cycles"])
            heapq.heappush(busy_lanes, (completion, lane, int(event["sequence"])))
            starts.append((event, actual_arrival, cycle, completion))
            started += 1

    def admit_sources(limit):
        nonlocal rr_stream
        admitted = scanned = 0
        while admitted < limit and len(central) < CENTRAL_DEPTH and scanned < STREAMS:
            stream = rr_stream
            rr_stream = (rr_stream + 1) % STREAMS
            if not source[stream]:
                scanned += 1
                continue
            central.append(source[stream].popleft())
            admitted += 1
            scanned = 0
        return admitted

    while finished < len(events):
        while busy_lanes and busy_lanes[0][0] <= cycle:
            _, lane, sequence = heapq.heappop(busy_lanes)
            free_lanes.append(lane)
            event = events[sequence]
            completed_per_stream[int(event["stream_id"])] += 1
            finished += 1

        dispatch_ready()
        admitted = admit_sources(lane_count)
        dispatch_ready()

        any_source_full = False
        for stream in range(STREAMS):
            if not upstream[stream]:
                continue
            event = upstream[stream][0]
            effective_arrival = int(event["arrival_cycle"]) + source_delay[stream]
            if effective_arrival > cycle:
                continue
            if len(source[stream]) >= source_capacity:
                source_delay[stream] += 1
                source_full_stream_cycles += 1
                any_source_full = True
                continue
            upstream[stream].popleft()
            source[stream].append((event, cycle))
            issued += 1
            max_issue_delay = max(max_issue_delay,
                                  cycle - int(event["arrival_cycle"]))

        if any_source_full:
            source_full_wall_cycles += 1

        if admitted < lane_count:
            admit_sources(lane_count - admitted)
            dispatch_ready()

        central_peak = max(central_peak, len(central))
        source_total = sum(len(queue) for queue in source)
        source_peak_total = max(source_peak_total, source_total)
        for stream in range(STREAMS):
            source_peak[stream] = max(source_peak[stream], len(source[stream]))

        if finished == len(events):
            break
        if not busy_lanes and not central and source_total == 0:
            next_cycles = [int(queue[0]["arrival_cycle"]) + source_delay[stream]
                           for stream, queue in enumerate(upstream) if queue]
            if next_cycles:
                cycle = max(cycle + 1, min(next_cycles))
                continue
        cycle += 1
        if cycle > 1000000:
            raise RuntimeError("finite source replay did not converge")

    if issued != len(events) or started != len(events) or finished != len(events):
        raise RuntimeError(f"request loss issued={issued} started={started} finished={finished}")
    if any(upstream) or any(source) or central or busy_lanes:
        raise RuntimeError("replay ended with pending state")
    if completed_per_stream != expected_per_stream:
        raise RuntimeError("per-stream completion mismatch")

    rows = []
    for stage in ("expand_pointwise", "project_pointwise"):
        selected = [item for item in starts if item[0]["stage"] == stage]
        issue_delays = sorted(actual - int(event["arrival_cycle"])
                              for event, actual, _, _ in selected)
        total_waits = sorted(start - int(event["arrival_cycle"])
                             for event, _, start, _ in selected)
        rows.append({
            "pcu_count": pcu_count,
            "scheduler_lanes": lane_count,
            "source_depth": source_capacity,
            "central_depth": CENTRAL_DEPTH,
            "stage": stage,
            "requests": len(selected),
            "average_issue_delay": f"{sum(issue_delays) / len(issue_delays):.4f}",
            "p95_issue_delay": percentile(issue_delays, 0.95),
            "max_issue_delay": issue_delays[-1],
            "average_total_wait": f"{sum(total_waits) / len(total_waits):.4f}",
            "p95_total_wait": percentile(total_waits, 0.95),
            "max_total_wait": total_waits[-1],
            "last_completion_cycle": max(completion for _, _, _, completion in selected),
            "source_peak_total": source_peak_total,
            "source_peak_per_stream": max(source_peak),
            "source_full_stream_cycles": source_full_stream_cycles,
            "source_full_wall_cycles": source_full_wall_cycles,
            "central_peak_entries": central_peak,
        })
    return rows


def main():
    trace = Path(sys.argv[1] if len(sys.argv) > 1 else
                 "experiment/results/uib_integration_trace.csv.requests.csv")
    output = Path(sys.argv[2] if len(sys.argv) > 2 else
                  "experiment/results/uib_finite_source_backpressure.csv")
    with trace.open(newline="") as trace_file:
        events = list(csv.DictReader(trace_file))
    events.sort(key=lambda event: int(event["sequence"]))
    for index, event in enumerate(events):
        if int(event["sequence"]) != index:
            raise SystemExit("Trace sequence must be contiguous")

    rows = []
    for pcu_count in PCU_COUNTS:
        for source_depth in SOURCE_DEPTHS:
            rows.extend(replay(events, pcu_count, source_depth))

    with output.open("w", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print("UIB_FINITE_SOURCE_BACKPRESSURE PASS "
          f"requests[{len(events)}] configurations[{len(PCU_COUNTS) * len(SOURCE_DEPTHS)}]")
    for row in rows:
        print(" ".join(f"{key}[{value}]" for key, value in row.items()))


if __name__ == "__main__":
    main()
