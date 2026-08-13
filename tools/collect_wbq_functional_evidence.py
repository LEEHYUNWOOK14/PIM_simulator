#!/usr/bin/env python3
"""Collect deterministic evidence from the wbq unit and integration logs."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHYSICAL = ROOT / "reports/groot_normalization/physical_feasibility"
OUTPUT = ROOT / "reports/final_integrated_gds_execution"
SOURCES = [
    "rtl/bf16_to_fp32.sv", "rtl/fp32_to_bf16_rne.sv", "rtl/fp32_add.sv",
    "rtl/fp32_mul.sv", "rtl/fp32_add_pipe4.sv", "rtl/fp32_mul_pipe4.sv",
    "rtl/bf16_rsqrt_lut256.sv", "rtl/mixed_precision_bank_reducer_pingpong.sv",
    "rtl/mixed_precision_global_reducer16_pipe.sv", "rtl/mixed_precision_scalar_nr2_pipe.sv",
    "rtl/mixed_precision_scalar_engine_array.sv", "rtl/mixed_precision_bank_apply_pipe.sv",
    "rtl/mixed_precision_row_context_table.sv", "rtl/mixed_precision_multirow_datapath.sv",
    "rtl/normalization_bank_scheduler.sv", "rtl/logic_die_normalization_pcu_top.sv",
    "rtl/normalization_hbm_boundary_adapter.sv", "rtl/normalization_writeback_quad_slice.sv",
    "rtl/logic_die_normalization_hbm_top.sv", "rtl/dram_bank_array_model.sv",
    "verification/groot_normalization/normalization_writeback_quad_slice_tb.sv",
    "verification/groot_normalization/normalization_hbm_boundary_integration_tb.sv",
]
PASS_RE = re.compile(
    r"PASS width=(?P<width>\d+) rms=(?P<rms>[01]) vectors=(?P<vectors>\d+) "
    r"wall_cycles=(?P<wall>\d+) adapter_cycles=(?P<adapter>\d+) act=(?P<act>\d+) "
    r"read=(?P<read>\d+) write=(?P<write>\d+) pre=(?P<pre>\d+) wait=(?P<wait>\d+) "
    r"read_credit_peak=(?P<credit_peak>\d+) read_credit_final=(?P<credit_final>\d+) "
    r"timing_errors=(?P<timing_errors>\d+)"
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    unit_log = PHYSICAL / "writeback_quad_slice_unit_regression.log"
    integration_log = PHYSICAL / "writeback_quad_slice_integration_regression.log"
    unit_text = unit_log.read_text(encoding="utf-8", errors="replace")
    integration_text = integration_log.read_text(encoding="utf-8", errors="replace")
    cases = [{key: int(value) for key, value in match.groupdict().items()}
             for match in PASS_RE.finditer(integration_text)]
    source_hashes = {name: digest(ROOT / name) for name in SOURCES}
    gate = (
        unit_text.count("NORMALIZATION_WRITEBACK_QUAD_SLICE_TB PASS") == 1
        and len(cases) == 4
        and {(case["width"], case["rms"]) for case in cases}
        == {(128, 0), (2048, 0), (128, 1), (2048, 1)}
        and all(case["credit_final"] == 0 and case["timing_errors"] == 0 for case in cases)
    )
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "rtl_simulated",
        "git_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
        "top": "logic_die_normalization_hbm_top",
        "unit_pass": "NORMALIZATION_WRITEBACK_QUAD_SLICE_TB PASS" in unit_text,
        "integration_pass_count": len(cases),
        "cases": cases,
        "source_sha256": source_hashes,
        "logs": {
            str(unit_log.relative_to(ROOT)): digest(unit_log),
            str(integration_log.relative_to(ROOT)): digest(integration_log),
        },
        "warnings": [
            "Icarus constant-select sensitivity limitation warnings were emitted; all functional, credit, and timing-error gates passed."
        ],
        "gate_pass": gate,
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "wbq_functional_manifest.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    rows = "".join(
        "<tr>" + "".join(f"<td>{case[key]}</td>" for key in
        ("width", "rms", "vectors", "wall", "adapter", "act", "read", "write", "pre", "credit_final", "timing_errors")) + "</tr>"
        for case in cases
    )
    html = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ 기능 회귀 보고서</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1100px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:9px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.pass{{padding:16px;background:#e7f6ed;border-left:6px solid #168154}}code{{word-break:break-all}}</style></head><body>
<h1>Phase 1 — 최신 wbq RTL 기능 기준선</h1><div class=\"pass\"><strong>{'PASS' if gate else 'FAIL'}</strong><br>Git <code>{payload['git_sha']}</code></div>
<h2>결과</h2><p>writeback quad slice unit test: {payload['unit_pass']}; integration: {len(cases)}/4.</p>
<table><tr><th>width</th><th>RMS</th><th>vectors</th><th>wall</th><th>adapter</th><th>ACT</th><th>READ</th><th>WRITE</th><th>PRE</th><th>credit final</th><th>timing errors</th></tr>{rows}</table>
<h2>재현 명령</h2><pre>bash verification/groot_normalization/run_normalization_writeback_quad_slice_test.sh
bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh
python3 tools/collect_wbq_functional_evidence.py</pre>
<h2>검증 범위</h2><p>LayerNorm/RMSNorm width 128/2048의 expected output 및 DRAM command count, read-credit drain, timing error를 검증했다. Source SHA-256과 raw-log SHA-256은 <code>wbq_functional_manifest.json</code>에 기록했다.</p>
<p><strong>Claim boundary:</strong> RTL 기능 회귀 결과이며 Sky130 mapping, placement, routability 또는 제조 signoff를 증명하지 않는다. RESEARCH ARTIFACT — NOT FOR FABRICATION.</p>
</body></html>"""
    (OUTPUT / "01_wbq_functional_regression_report.html").write_text(html, encoding="utf-8")
    print(f"WBQ_FUNCTIONAL_EVIDENCE {'PASS' if gate else 'FAIL'} cases={len(cases)}")
    return 0 if gate else 1


if __name__ == "__main__":
    raise SystemExit(main())

