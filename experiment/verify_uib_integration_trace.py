#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def fail(message):
    raise SystemExit(f"UIB_INTEGRATION_TRACE FAIL: {message}")


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else
                "experiment/results/uib_integration_trace.csv")
    with path.open(newline="") as trace_file:
        rows = list(csv.DictReader(trace_file))

    stages = [
        "expand_pointwise",
        "depthwise_3x3",
        "project_pointwise",
        "residual_add",
        "relu_readback",
    ]
    if [row["stage"] for row in rows] != stages:
        fail("stage order does not match the MobileNetV4 UIB contract")

    for sequence, row in enumerate(rows):
        if int(row["sequence"]) != sequence:
            fail(f"sequence mismatch at row {sequence}")
        start = int(row["start_cycle"])
        end = int(row["end_cycle"])
        if end < start or int(row["cycles"]) != end - start:
            fail(f"invalid cycle range for {row['stage']}")

    boundaries = ((0, 1), (1, 2), (3, 4))
    for producer, consumer in boundaries:
        if rows[producer]["output_fp16_hash"] != rows[consumer]["input_fp16_hash"]:
            fail(f"FP16 boundary mismatch: {stages[producer]} -> {stages[consumer]}")

    project_hash = rows[2]["output_fp16_hash"]
    residual_inputs = rows[3]["input_fp16_hash"].split("+")
    if not residual_inputs or residual_inputs[0] != project_hash:
        fail("project output is not connected to residual ADD")

    expected_counts = ((18816, 37632), (37632, 37632), (37632, 18816),
                       (37632, 18816), (18816, 18816))
    for row, expected in zip(rows, expected_counts):
        actual = (int(row["input_elements"]), int(row["output_elements"]))
        if actual != expected:
            fail(f"element count mismatch for {row['stage']}: {actual} != {expected}")

    total_cycles = int(rows[-1]["end_cycle"]) - int(rows[0]["start_cycle"])
    request_path = Path(str(path) + ".requests.csv")
    with request_path.open(newline="") as request_file:
        requests = list(csv.DictReader(request_file))
    if not requests:
        fail("pointwise request trace is empty")

    stage_ranges = {
        row["stage"]: (int(row["start_cycle"]), int(row["end_cycle"])) for row in rows
    }
    request_counts = {"expand_pointwise": 0, "project_pointwise": 0}
    coalesced_counts = {"expand_pointwise": 0, "project_pointwise": 0}
    max_queue = {"expand_pointwise": 0, "project_pointwise": 0}
    for sequence, request in enumerate(requests):
        if int(request["sequence"]) != sequence:
            fail(f"request sequence mismatch at row {sequence}")
        stage = request["stage"]
        if stage not in request_counts:
            fail(f"unexpected request stage: {stage}")
        arrival = int(request["arrival_cycle"])
        start = int(request["service_start_cycle"])
        completion = int(request["completion_cycle"])
        queue = int(request["queue_cycles"])
        service = int(request["service_cycles"])
        stage_start, stage_end = stage_ranges[stage]
        if not stage_start <= arrival < stage_end:
            fail(f"request outside {stage} cycle range")
        if start != arrival + queue or completion != start + service:
            fail(f"reservation timing identity failed at request {sequence}")
        request_counts[stage] += 1
        coalesced_counts[stage] += int(request["coalesced"])
        max_queue[stage] = max(max_queue[stage], queue)

    if any(count == 0 for count in request_counts.values()):
        fail(f"missing pointwise stage requests: {request_counts}")
    print("UIB_INTEGRATION_TRACE PASS "
          f"stages[{len(rows)}] outputs[18816] total_stage_span_cycles[{total_cycles}] "
          f"final_fp16_hash[{rows[-1]['output_fp16_hash']}] "
          f"expand_requests[{request_counts['expand_pointwise']}] "
          f"project_requests[{request_counts['project_pointwise']}] "
          f"expand_coalesced[{coalesced_counts['expand_pointwise']}] "
          f"project_coalesced[{coalesced_counts['project_pointwise']}] "
          f"expand_max_queue[{max_queue['expand_pointwise']}] "
          f"project_max_queue[{max_queue['project_pointwise']}]")


if __name__ == "__main__":
    main()
