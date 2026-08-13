#!/usr/bin/env python3
"""Check that GR00T placement docs stay aligned with the generated summary."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GR00T = ROOT / "experiment" / "gr00t_placement"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def expect(text: str, pattern: str, label: str) -> None:
    if not re.search(pattern, text, re.M):
        raise SystemExit(f"missing {label}: {pattern}")


def main() -> int:
    summary = json.loads((GR00T / "results" / "summary.json").read_text(encoding="utf-8"))
    readme = read_text(GR00T / "README.md")
    memo = read_text(GR00T / "decision_memo.md")
    claim_map = read_text(GR00T / "claim_map.md")
    recommendation = json.loads((GR00T / "recommendation.json").read_text(encoding="utf-8"))

    candidate_count = summary["candidate_count"]
    pareto_count = summary["pareto_count"]
    baseline = summary["baseline"]
    mode = summary["provisional_monte_carlo_mode"]
    status = summary["final_recommendation_status"]
    mode_win_rate = mode["monte_carlo_mode_win_rate"]
    mode_win_percent = f"{mode_win_rate * 100:.1f}%"

    expect(readme, rf"{candidate_count} candidate placements evaluated", "README candidate count")
    expect(readme, rf"{pareto_count} Pareto candidates", "README pareto count")
    expect(
        readme,
        rf"Provisional (?:center )?Monte Carlo mode win rate:\s*`{re.escape(mode_win_percent)}`",
        "README Monte Carlo rate",
    )

    expect(memo, rf"Candidate placements evaluated:\s*{candidate_count}", "memo candidate count")
    expect(memo, rf"Pareto points found:\s*{pareto_count}", "memo pareto count")
    expect(memo, rf"Baseline balanced score:\s*`{baseline['balanced_score']}`", "memo baseline score")
    expect(memo, rf"Win rate:\s*`{re.escape(mode_win_percent)}`", "memo Monte Carlo rate")
    expect(memo, rf"Status:\s*`{status}`", "memo status")

    expect(claim_map, rf"Candidate placements evaluated:\s*`{candidate_count}`", "claim map candidate count")
    expect(claim_map, rf"Pareto candidates:\s*`{pareto_count}`", "claim map pareto count")
    expect(claim_map, rf"Baseline balanced score:\s*`{baseline['balanced_score']}`", "claim map baseline score")
    expect(
        claim_map,
        rf"Provisional Monte Carlo mode win rate:\s*`{re.escape(str(mode_win_rate))}`",
        "claim map Monte Carlo rate",
    )
    expect(claim_map, rf"Robustness gate:\s*`failed`", "claim map robustness gate")

    if recommendation["status"] != status:
        raise SystemExit("recommendation status does not match summary status")
    if "summary" in recommendation:
        recommendation_summary = recommendation["summary"]
        if recommendation_summary["candidate_count"] != candidate_count:
            raise SystemExit("recommendation candidate count does not match summary")
        if recommendation_summary["pareto_count"] != pareto_count:
            raise SystemExit("recommendation pareto count does not match summary")
        if recommendation_summary["baseline"]["balanced_score"] != baseline["balanced_score"]:
            raise SystemExit("recommendation baseline score does not match summary")
        recommendation_mode = recommendation_summary["provisional_monte_carlo_mode"]
    else:
        if recommendation.get("authoritative_summary") != "results/summary.json":
            raise SystemExit("recommendation does not identify the authoritative summary")
        recommendation_mode = recommendation["provisional_coordinate_only"]

    if recommendation_mode["balanced_score"] != mode["balanced_score"]:
        raise SystemExit("recommendation Monte Carlo score does not match summary")
    if recommendation_mode["monte_carlo_mode_win_rate"] != mode_win_rate:
        raise SystemExit("recommendation Monte Carlo win rate does not match summary")

    print("GR00T placement docs are aligned with the current summary outputs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
