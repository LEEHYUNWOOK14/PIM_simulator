#!/usr/bin/env python3
import csv
import heapq
import sys
from pathlib import Path


PCU_COUNTS = (8, 16, 32, 64)
BASELINE_PCUS = 16


def percentile(sorted_values, fraction):
    return sorted_values[int(fraction * (len(sorted_values) - 1))]


def peak_waiting(intervals):
    events = []
    for arrival, start in intervals:
        if start > arrival:
            events.append((arrival, 1))
            events.append((start, -1))
    events.sort(key=lambda event: (event[0], event[1]))
    current = peak = 0
    for _, delta in events:
        current += delta
        peak = max(peak, current)
    return peak


def replay(events, pcu_count):
    blocks_per_command = {int(event["blocks"]) for event in events}
    if blocks_per_command != {8}:
        raise SystemExit(f"Expected one 8-block command shape, got {blocks_per_command}")
    if pcu_count < 8 or pcu_count % 8:
        raise SystemExit("PCU count must be a multiple of the 8-block command width")

    lane_count = pcu_count // 8
    lanes = [(0, lane) for lane in range(lane_count)]
    heapq.heapify(lanes)
    replayed = []
    for event in events:
        available, lane = heapq.heappop(lanes)
        arrival = int(event["arrival_cycle"])
        service = int(event["service_cycles"])
        start = max(arrival, available)
        completion = start + service
        heapq.heappush(lanes, (completion, lane))
        replayed.append((event, start, completion))
    return replayed


def summarize(replayed, pcu_count, stage):
    selected = [item for item in replayed if item[0]["stage"] == stage]
    queues = sorted(start - int(event["arrival_cycle"])
                    for event, start, _ in selected)
    intervals = [(int(event["arrival_cycle"]), start)
                 for event, start, _ in selected]
    first_arrival = min(arrival for arrival, _ in intervals)
    last_completion = max(completion for _, _, completion in selected)
    return {
        "pcu_count": pcu_count,
        "scheduler_lanes": pcu_count // 8,
        "stage": stage,
        "requests": len(selected),
        "average_queue_cycles": f"{sum(queues) / len(queues):.4f}",
        "p95_queue_cycles": percentile(queues, 0.95),
        "max_queue_cycles": queues[-1],
        "peak_waiting_requests": peak_waiting(intervals),
        "first_arrival_cycle": first_arrival,
        "last_completion_cycle": last_completion,
        "arrival_to_completion_span": last_completion - first_arrival,
    }


def main():
    trace = Path(sys.argv[1] if len(sys.argv) > 1 else
                 "experiment/results/uib_integration_trace.csv.requests.csv")
    output = Path(sys.argv[2] if len(sys.argv) > 2 else
                  "experiment/results/uib_pointwise_pcu_sweep.csv")
    with trace.open(newline="") as trace_file:
        events = list(csv.DictReader(trace_file))
    if not events:
        raise SystemExit("Pointwise request trace is empty")

    baseline = replay(events, BASELINE_PCUS)
    start_mismatches = sum(start != int(event["service_start_cycle"])
                           for event, start, _ in baseline)
    completion_mismatches = sum(completion != int(event["completion_cycle"])
                                for event, _, completion in baseline)
    if start_mismatches or completion_mismatches:
        raise SystemExit("PCU_REPLAY FAIL "
                         f"start_mismatches[{start_mismatches}] "
                         f"completion_mismatches[{completion_mismatches}]")

    rows = []
    for pcu_count in PCU_COUNTS:
        replayed = baseline if pcu_count == BASELINE_PCUS else replay(events, pcu_count)
        for stage in ("expand_pointwise", "project_pointwise"):
            rows.append(summarize(replayed, pcu_count, stage))

    with output.open("w", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print("UIB_POINTWISE_PCU_SWEEP PASS baseline_start_mismatches[0] "
          "baseline_completion_mismatches[0]")
    for row in rows:
        print(" ".join(f"{key}[{value}]" for key, value in row.items()))


if __name__ == "__main__":
    main()
