#!/usr/bin/env python3
"""Collect Phase-6 wbq CTS evidence and render the clock-stage HTML report."""

from __future__ import annotations

import hashlib
import html
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORFS = Path(os.environ.get("ORFS_ROOT", ROOT.parent / "OpenROAD-flow-scripts"))
RESULTS = ORFS / "flow/results/sky130hd/normalization_hbm_wbq/base"
RAW = ROOT / "reports/groot_normalization/physical_feasibility"
OUT = ROOT / "reports/final_integrated_gds_execution"
PLACEMENT = OUT / "wbq_placement_manifest.json"
DECISION = OUT / "wbq_post_route_decision.json"
GATE = OUT / "wbq_phase6_input_gate.json"
RUN_LOG = RAW / "logic_die_normalization_hbm_top_wbq_phase6_cts.log"
AUDIT_LOG = RAW / "logic_die_normalization_hbm_top_wbq_phase6_cts_audit.log"
ODB = RESULTS / "4_cts.odb"
SDC = RESULTS / "4_cts.sdc"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def one(pattern: str, text: str, cast=str):
    values = re.findall(pattern, text, flags=re.MULTILINE)
    return cast(values[-1]) if values else None


def kv(text: str, key: str) -> str | None:
    return one(rf"^{re.escape(key)}=(.*)$", text)


def main() -> int:
    required = [PLACEMENT, DECISION, GATE, RUN_LOG, AUDIT_LOG, ODB, SDC]
    missing = [str(path) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("missing/non-empty Phase-6 CTS artifacts:\n" + "\n".join(missing))

    placement = json.loads(PLACEMENT.read_text(encoding="utf-8-sig"))
    decision = json.loads(DECISION.read_text(encoding="utf-8-sig"))
    gate = json.loads(GATE.read_text(encoding="utf-8-sig"))
    run = RUN_LOG.read_text(encoding="utf-8", errors="replace")
    audit = AUDIT_LOG.read_text(encoding="utf-8", errors="replace")

    actual_odb_hash = sha256(ODB)
    actual_sdc_hash = sha256(SDC)
    input_hashes_match = (
        kv(run, "WBQ_PHASE6_CTS_PLACE_ODB_SHA256")
        == placement["artifacts"]["placed_odb"]["sha256"]
        and kv(run, "WBQ_PHASE6_CTS_PLACE_SDC_SHA256")
        == placement["artifacts"]["placed_sdc"]["sha256"]
    )
    gate_hash_match = kv(run, "WBQ_PHASE6_CTS_GATE_SHA256") == sha256(GATE)
    decision_hash_match = kv(run, "WBQ_PHASE6_CTS_DECISION_SHA256") == sha256(DECISION)
    audit_hashes_match = (
        kv(audit, "WBQ_PHASE6_CTS_AUDIT_ODB_SHA256") == actual_odb_hash
        and kv(audit, "WBQ_PHASE6_CTS_AUDIT_SDC_SHA256") == actual_sdc_hash
    )

    created_buffers = one(r"\[INFO CTS-0018\]\s+Created (\d+) clock buffers", run, int)
    created_clock_nets = one(r"\[INFO CTS-0015\]\s+Created (\d+) clock nets", run, int)
    initial_sinks = one(r"\[INFO CTS-0010\]\s+Clock net .* has (\d+) sinks", run, int)
    max_tree_level = one(r"\[INFO CTS-0017\]\s+Max level of the clock tree: (\d+)", run, int)
    placement_instances = placement.get("placed_instance_count")
    cts_instances = one(r"^WBQ_PHASE6_CTS_AUDIT_INSTANCE_COUNT (\d+)$", audit, int)
    clock_count = one(r"^WBQ_PHASE6_CTS_AUDIT_CLOCK_COUNT (\d+)$", audit, int)
    sourced_clock_count = one(r"^WBQ_PHASE6_CTS_AUDIT_SOURCED_CLOCK_COUNT (\d+)$", audit, int)
    clock_net_count = one(r"^WBQ_PHASE6_CTS_AUDIT_CLOCK_NET_COUNT (\d+)$", audit, int)
    violations = one(r"^WBQ_PHASE6_CTS_AUDIT_VIOLATIONS (\d+)$", audit, int)

    clean_completion = (
        kv(run, "WBQ_PHASE6_CTS_EXIT_CODE") == "0"
        and "NORMALIZATION_HBM_WBQ_PHASE6_CTS PASS" in run
        and "WBQ_PHASE6_CTS_AUDIT_PASS" in audit
    )
    explicit_clock_tree = all(
        value is not None and value > 0
        for value in (created_buffers, created_clock_nets, initial_sinks, clock_count,
                      sourced_clock_count, clock_net_count)
    )
    instance_growth = (
        isinstance(placement_instances, int)
        and cts_instances is not None
        and cts_instances > placement_instances
    )
    policy_match = (
        kv(run, "WBQ_PHASE6_CTS_SIGNAL_LAYERS") == "met1-met5"
        and kv(run, "WBQ_PHASE6_CTS_CLOCK_LAYERS") == "met2-met5"
        and kv(run, "WBQ_PHASE6_CTS_POLICY") == "ORFS_TRITONCTS_REPAIR_CLOCK_NETS"
    )
    gate_pass = bool(
        placement.get("gate_pass") is True
        and decision.get("decision") == "PHASE6_CLOCK_AND_DETAILED_ROUTE"
        and gate.get("gate_pass") is True
        and input_hashes_match
        and gate_hash_match
        and decision_hash_match
        and audit_hashes_match
        and clean_completion
        and explicit_clock_tree
        and instance_growth
        and policy_match
        and violations == 0
    )

    elapsed = one(r"Elapsed \(wall clock\) time .*?: (.+)$", run)
    rss = one(r"Maximum resident set size \(kbytes\): (\d+)", run, int)
    artifact_paths = {
        "cts_odb": ODB,
        "cts_sdc": SDC,
        "run_log": RUN_LOG,
        "independent_audit_log": AUDIT_LOG,
        "phase6_input_gate": GATE,
    }
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "placed",
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq_phase6_cts",
        "gate_pass": gate_pass,
        "run_git_sha": kv(run, "WBQ_PHASE6_CTS_GIT_SHA"),
        "evidence_git_parent_sha": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "orfs_sha": kv(run, "WBQ_PHASE6_CTS_ORFS_SHA"),
        "openroad_version": kv(run, "WBQ_PHASE6_CTS_OPENROAD_VERSION"),
        "start_utc": kv(run, "WBQ_PHASE6_CTS_START_UTC"),
        "end_utc": kv(run, "WBQ_PHASE6_CTS_END_UTC"),
        "elapsed_wall": elapsed,
        "maximum_rss_kbytes": rss,
        "clock_policy": {
            "implementation": "ORFS TritonCTS with -repair_clock_nets",
            "signal_layers": "met1-met5",
            "clock_layers": "met2-met5",
            "policy_match": policy_match,
        },
        "metrics": {
            "initial_clock_sinks": initial_sinks,
            "created_clock_buffers": created_buffers,
            "created_clock_nets": created_clock_nets,
            "maximum_clock_tree_level": max_tree_level,
            "defined_clocks": clock_count,
            "sourced_clocks": sourced_clock_count,
            "database_clock_nets": clock_net_count,
            "placement_instances": placement_instances,
            "post_cts_instances": cts_instances,
            "instance_delta": None if cts_instances is None or not isinstance(placement_instances, int)
            else cts_instances - placement_instances,
            "legalization_violations": violations,
        },
        "checks": {
            "placement_gate_pass": placement.get("gate_pass") is True,
            "phase6_decision": decision.get("decision") == "PHASE6_CLOCK_AND_DETAILED_ROUTE",
            "phase6_input_gate_pass": gate.get("gate_pass") is True,
            "launch_input_hashes_match": input_hashes_match,
            "gate_hash_match": gate_hash_match,
            "decision_hash_match": decision_hash_match,
            "audit_output_hashes_match": audit_hashes_match,
            "clean_completion_and_independent_reopen": clean_completion,
            "explicit_clock_tree": explicit_clock_tree,
            "post_cts_instance_growth": instance_growth,
            "legalization_zero": violations == 0,
        },
        "artifacts": {
            name: {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for name, path in artifact_paths.items()
        },
        "reproduction_commands": [
            "bash verification/groot_normalization/run_normalization_hbm_wbq_phase6_cts.sh",
            "bash verification/groot_normalization/run_normalization_hbm_wbq_phase6_cts_audit.sh",
            "python3 tools/collect_wbq_phase6_cts_evidence.py",
        ],
        "claim_boundary": "CTS-completed placed research checkpoint; post-CTS global route, detailed route, timing closure, and manufacturing signoff are not yet established.",
    }
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = OUT / "wbq_phase6_cts_manifest.json"
    manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    esc = lambda value: html.escape(str(value))
    verdict = "PASS" if gate_pass else "FAIL"
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ clock 및 상세배선 보고서</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.verdict{{padding:16px;background:{'#e7f6ed' if gate_pass else '#fdecec'};border-left:6px solid {'#168154' if gate_pass else '#a12626'}}}code{{word-break:break-all}}</style></head><body>
<h1>Phase 6 — wbq clock distribution</h1><div class=\"verdict\"><strong>{verdict}</strong><br>분류: CTS-completed placed research checkpoint</div>
<h2>Clock tree</h2><table><tr><th>Initial sinks</th><td>{esc(initial_sinks)}</td></tr><tr><th>Created buffers / nets</th><td>{esc(created_buffers)} / {esc(created_clock_nets)}</td></tr><tr><th>Maximum level</th><td>{esc(max_tree_level)}</td></tr><tr><th>Clock layers</th><td>met2–met5</td></tr><tr><th>Instance delta</th><td>{esc(payload['metrics']['instance_delta'])}</td></tr><tr><th>Legalization violations</th><td>{esc(violations)}</td></tr><tr><th>Wall / peak RSS</th><td>{esc(elapsed)} / {esc(None if rss is None else f'{rss / 1024 / 1024:.2f} GiB')}</td></tr></table>
<h2>현재 경계</h2><p>독립 ODB/SDC 재개방과 명시적 clock network 및 legality를 확인한 CTS 단계다. Post-CTS global route와 detailed route는 아직 이 보고서에서 증명하지 않는다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p>
</body></html>"""
    (OUT / "06_clock_and_detailed_route_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_PHASE6_CTS_EVIDENCE {verdict} buffers={created_buffers} violations={violations}")
    return 0 if gate_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
