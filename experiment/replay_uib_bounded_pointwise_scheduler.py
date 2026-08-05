#!/usr/bin/env python3
import csv
import heapq
import sys
from collections import deque
from pathlib import Path


PCU_COUNTS = (16, 32, 64)
QUEUE_DEPTHS = (64, 128, 256)
STREAMS = 128


def percentile(sorted_values, fraction):
    return sorted_values[int(fraction * (len(sorted_values) - 1))]


def replay(events, pcu_count, queue_depth):
    lanes_count = pcu_count // 8
    source_queues = [deque() for _ in range(STREAMS)]
    source_depths = [0] * STREAMS
    source_peak_per_stream = [0] * STREAMS
    source_total = source_peak_total = source_queued_request_cycles = 0
    central = deque()
    central_peak = central_full_cycles = 0
    free_lanes = list(range(lanes_count))
    busy_lanes = []
    rr_stream = 0
    event_index = completed = 0
    first_cycle = min(int(event["arrival_cycle"]) for event in events)
    cycle = first_cycle
    starts = []

    def dispatch_ready():
        nonlocal completed
        while free_lanes and central:
            lane = free_lanes.pop()
            event = central.popleft()
            service = int(event["service_cycles"])
            completion = cycle + service
            heapq.heappush(busy_lanes, (completion, lane))
            starts.append((event, cycle, completion))
            completed += 1

    while completed < len(events) or busy_lanes:
        while event_index < len(events) and int(events[event_index]["arrival_cycle"]) <= cycle:
            event = events[event_index]
            stream = int(event["stream_id"])
            if stream >= STREAMS:
                raise RuntimeError(f"stream {stream} exceeds configured source count")
            source_queues[stream].append(event)
            source_depths[stream] += 1
            source_total += 1
            source_peak_per_stream[stream] = max(source_peak_per_stream[stream],
                                                 source_depths[stream])
            event_index += 1
        source_peak_total = max(source_peak_total, source_total)

        while busy_lanes and busy_lanes[0][0] <= cycle:
            _, lane = heapq.heappop(busy_lanes)
            free_lanes.append(lane)

        dispatch_ready()

        admissions = 0
        scanned_without_admission = 0
        while (admissions < lanes_count and len(central) < queue_depth and
               source_total > 0 and scanned_without_admission < STREAMS):
            stream = rr_stream
            rr_stream = (rr_stream + 1) % STREAMS
            if not source_queues[stream]:
                scanned_without_admission += 1
                continue
            central.append(source_queues[stream].popleft())
            source_depths[stream] -= 1
            source_total -= 1
            admissions += 1
            scanned_without_admission = 0

        central_peak = max(central_peak, len(central))
        if len(central) == queue_depth and source_total > 0:
            central_full_cycles += 1
        dispatch_ready()
        source_queued_request_cycles += source_total

        if completed == len(events) and not busy_lanes:
            break
        if source_total == 0 and not central and not busy_lanes and event_index < len(events):
            cycle = int(events[event_index]["arrival_cycle"])
        else:
            cycle += 1
        if cycle - first_cycle > 1000000:
            raise RuntimeError("bounded scheduler replay did not converge")

    if len(starts) != len(events):
        raise RuntimeError(f"lost requests: started {len(starts)} of {len(events)}")
    if any(source_queues) or central:
        raise RuntimeError("scheduler completed with non-empty queues")

    rows = []
    for stage in ("expand_pointwise", "project_pointwise"):
        selected = [item for item in starts if item[0]["stage"] == stage]
        waits = sorted(start - int(event["arrival_cycle"]) for event, start, _ in selected)
        rows.append({
            "pcu_count": pcu_count,
            "scheduler_lanes": lanes_count,
            "queue_depth": queue_depth,
            "stage": stage,
            "requests": len(selected),
            "average_wait_cycles": f"{sum(waits) / len(waits):.4f}",
            "p95_wait_cycles": percentile(waits, 0.95),
            "max_wait_cycles": waits[-1],
            "last_completion_cycle": max(completion for _, _, completion in selected),
            "central_peak_entries": central_peak,
            "central_full_cycles": central_full_cycles,
            "source_peak_total": source_peak_total,
            "source_peak_per_stream": max(source_peak_per_stream),
            "source_queued_request_cycles": source_queued_request_cycles,
        })
    return rows


def main():
    trace = Path(sys.argv[1] if len(sys.argv) > 1 else
                 "experiment/results/uib_integration_trace.csv.requests.csv")
    output = Path(sys.argv[2] if len(sys.argv) > 2 else
                  "experiment/results/uib_bounded_pointwise_scheduler.csv")
    with trace.open(newline="") as trace_file:
        events = list(csv.DictReader(trace_file))
    events.sort(key=lambda event: int(event["sequence"]))
    if not events:
        raise SystemExit("Pointwise request trace is empty")

    rows = []
    for pcu_count in PCU_COUNTS:
        for queue_depth in QUEUE_DEPTHS:
            rows.extend(replay(events, pcu_count, queue_depth))

    with output.open("w", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print("UIB_BOUNDED_POINTWISE_SCHEDULER PASS "
          f"requests[{len(events)}] configurations[{len(PCU_COUNTS) * len(QUEUE_DEPTHS)}]")
    for row in rows:
        print(" ".join(f"{key}[{value}]" for key, value in row.items()))


if __name__ == "__main__":
    main()
