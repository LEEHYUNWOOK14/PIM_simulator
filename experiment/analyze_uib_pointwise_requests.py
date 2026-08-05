#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def percentile(sorted_values, fraction):
    return sorted_values[int(fraction * (len(sorted_values) - 1))]


def main():
    trace = Path(sys.argv[1] if len(sys.argv) > 1 else
                 "experiment/results/uib_integration_trace.csv.requests.csv")
    output = Path(sys.argv[2] if len(sys.argv) > 2 else
                  "experiment/results/uib_pointwise_request_summary.csv")
    with trace.open(newline="") as trace_file:
        events = list(csv.DictReader(trace_file))

    rows = []
    for stage in ("expand_pointwise", "project_pointwise"):
        selected = [event for event in events if event["stage"] == stage]
        if not selected:
            raise SystemExit(f"No reservation events for {stage}")
        queues = sorted(int(event["queue_cycles"]) for event in selected)
        coalesced = sum(int(event["coalesced"]) for event in selected)
        rows.append({
            "stage": stage,
            "requests": len(selected),
            "streams": len({event["stream_id"] for event in selected}),
            "dispatches": len(selected) - coalesced,
            "coalesced_requests": coalesced,
            "coalescing_percent": f"{100.0 * coalesced / len(selected):.4f}",
            "average_queue_cycles": f"{sum(queues) / len(queues):.4f}",
            "p95_queue_cycles": percentile(queues, 0.95),
            "max_queue_cycles": queues[-1],
            "first_arrival_cycle": min(int(event["arrival_cycle"]) for event in selected),
            "last_completion_cycle": max(int(event["completion_cycle"]) for event in selected),
            "modeled_transfer_bytes": sum(int(event["transfer_bytes"]) for event in selected),
        })

    with output.open("w", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print("UIB_POINTWISE_REQUEST_ANALYSIS PASS")
    for row in rows:
        print(" ".join(f"{key}[{value}]" for key, value in row.items()))


if __name__ == "__main__":
    main()
