#!/usr/bin/env python3
"""Classify paper results and enforce claim boundaries from physical gates."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "hardware_cost/regression/paper_claims.json"
DEFAULT_JSON = ROOT / "reports/paper_evidence_matrix/evidence_matrix.json"
DEFAULT_REPORT = ROOT / "reports/paper_evidence_matrix/evidence_matrix.md"

CLASS_BY_BASIS = {
    "rtl_simulation": "rtl_simulated",
    "technology_mapping": "synthesized",
    "legal_placement": "placed",
    "global_routing": "placed",  # six-class taxonomy has no routed class
    "computational_model": "modeled",
    "engineering_estimate": "estimated",
    "illustration": "illustrative",
}
CLASSES = set(CLASS_BY_BASIS.values())
GATES = {f"PF-{index}" for index in range(5)}
ROUTING_ASSERTION = re.compile(
    r"\brouting feasible\b|\broutab(?:le|ility)\b|\b(?:global[- ]?)?routing feasibility\b|"
    r"\bsuccessfully (?:globally )?routed\b|\bglobally routed\b",
    re.IGNORECASE,
)
SAFE_ROUTING_QUALIFIER = re.compile(
    r"\b(?:remains? unestablished|is not established|has not been established|PF-4[^.;]*pending|"
    r"must remain unclaimed|no affirmative|cannot (?:be )?(?:claimed|established)|"
    r"does not establish|not routable|routing (?:is )?unavailable|severe congestion remains|PF-4 failed)\b",
    re.IGNORECASE,
)


class ClaimBoundaryError(ValueError):
    pass


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def evidence_record(relative: str) -> dict:
    path = ROOT / relative
    if not path.is_file():
        return {"path": relative, "bytes": None, "sha256": None}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest.hexdigest()}


def classify_result(item: dict, physical: dict) -> dict:
    basis = item.get("basis")
    if basis not in CLASS_BY_BASIS:
        raise ClaimBoundaryError(f"{item.get('id', '<unknown>')}: unknown basis {basis!r}")
    required_gate = item.get("required_gate")
    if required_gate is not None and required_gate not in GATES:
        raise ClaimBoundaryError(f"{item['id']}: unknown required_gate {required_gate!r}")
    gate_status = physical["gates"][required_gate]["status"] if required_gate else "NOT_APPLICABLE"
    evidence = item.get("evidence", [])
    records = [evidence_record(path) for path in evidence]
    missing = [record["path"] for record in records if record["sha256"] is None]
    supported = not missing and gate_status in {"PASS", "NOT_APPLICABLE"}
    return {
        **item,
        "classification": CLASS_BY_BASIS[basis],
        "gate_status": gate_status,
        "claim_status": "SUPPORTED" if supported else "BLOCKED",
        "evidence_records": records,
        "missing_evidence": missing,
    }


def routing_overclaims(text: str, source: str, pf4_status: str) -> list[str]:
    if pf4_status == "PASS":
        return []
    violations = []
    for number, line in enumerate(text.splitlines(), 1):
        if ROUTING_ASSERTION.search(line) and not SAFE_ROUTING_QUALIFIER.search(line):
            violations.append(f"{source}:{number}: PF-4={pf4_status} forbids affirmative routing claim: {line.strip()}")
    return violations


def build(manifest_path: Path = DEFAULT_MANIFEST) -> tuple[dict, list[str]]:
    manifest = load_json(manifest_path)
    physical_path = ROOT / manifest["physical_feasibility"]
    physical = load_json(physical_path)
    rows = [classify_result(item, physical) for item in manifest["results"]]
    errors = []
    ids = [row["id"] for row in rows]
    if len(ids) != len(set(ids)):
        errors.append("result ids must be unique")
    if {row["classification"] for row in rows} - CLASSES:
        errors.append("matrix contains an unsupported classification")
    for row in rows:
        if row["missing_evidence"]:
            errors.append(f"{row['id']}: missing evidence: {', '.join(row['missing_evidence'])}")
        if row["basis"] == "global_routing" and row["gate_status"] != "PASS" and row["claim_status"] != "BLOCKED":
            errors.append(f"{row['id']}: global-routing claim must be blocked until PF-4 passes")
        if physical["gates"]["PF-4"]["status"] != "PASS":
            for field in ("allowed_claim", "boundary"):
                errors.extend(routing_overclaims(row.get(field, ""), f"{row['id']}.{field}", physical["gates"]["PF-4"]["status"]))
    for relative in manifest.get("scan_paths", []):
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"scan path does not exist: {relative}")
            continue
        errors.extend(routing_overclaims(path.read_text(encoding="utf-8", errors="replace"), relative, physical["gates"]["PF-4"]["status"]))
    matrix = {
        "schema_version": 1,
        "physical_feasibility_source": manifest["physical_feasibility"],
        "physical_status": physical["status"],
        "gate_status": {name: physical["gates"][name]["status"] for name in sorted(GATES)},
        "routing_claim_allowed": physical["gates"]["PF-4"]["status"] == "PASS",
        "results": rows,
    }
    return matrix, errors


def markdown(matrix: dict) -> str:
    pf4_status = matrix["gate_status"]["PF-4"]
    guardrail = (
        "PF-4 failed after a completed full-net global-route run because severe congestion remained. "
        "The paper may report the completed attempt and its measured congestion, but must not assert "
        "routability, routing feasibility, or congestion closure."
        if pf4_status == "FAIL"
        else "PF-4 is not PASS. The paper may report that legal coarse placement passed, but it must not "
             "assert routability, routing feasibility, congestion closure, or completed global routing."
    )
    lines = [
        "# Paper Claim Boundary and Evidence Matrix",
        "",
        f"Physical status: **{matrix['physical_status']}**  ",
        f"Routing claim allowed: **{str(matrix['routing_claim_allowed']).lower()}**",
        "",
        "The classification describes the evidence actually supporting each result. It is not a maturity ladder: modeled and estimated results remain distinct from RTL and implementation evidence.",
        "",
        "| ID | Result | Class | Gate | Claim status |",
        "|---|---|---|---|---|",
    ]
    for row in matrix["results"]:
        gate = f"{row['required_gate']} {row['gate_status']}" if row["required_gate"] else "n/a"
        lines.append(f"| {row['id']} | {row['result']} | `{row['classification']}` | {gate} | **{row['claim_status']}** |")
    lines.extend(["", "## Allowed wording and boundary", ""])
    for row in matrix["results"]:
        lines.extend([
            f"### {row['id']} — `{row['classification']}` / {row['claim_status']}",
            "",
            f"Allowed: {row['allowed_claim']}",
            "",
            f"Boundary: {row['boundary']}",
            "",
            "Evidence: " + ", ".join(f"`{path}`" for path in row["evidence"]),
            "",
        ])
    lines.extend([
        "## PF-4 guardrail",
        "",
        guardrail + " Re-run this generator after routing evidence changes; the guard is derived from the physical-feasibility JSON rather than manually selected.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--check", action="store_true", help="validate without writing outputs")
    args = parser.parse_args()
    matrix, errors = build(args.manifest)
    if errors:
        raise ClaimBoundaryError("claim-boundary validation failed:\n- " + "\n- ".join(errors))
    if not args.check:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(matrix, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        args.report.write_text(markdown(matrix), encoding="utf-8")
    print(f"PASS: {len(matrix['results'])} results classified; routing_claim_allowed={matrix['routing_claim_allowed']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
