#!/usr/bin/env python3
"""Collect the current wbq Sky130 mapping gate and render its HTML report."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "reports/groot_normalization/physical_feasibility"
OUT = ROOT / "reports/final_integrated_gds_execution"
LOG = RAW / "logic_die_normalization_hbm_top_wbq_sky130_yosys.log"
DRIVER = RAW / "logic_die_normalization_hbm_top_wbq_mapping_driver.log"
NETLIST = RAW / "logic_die_normalization_hbm_top_wbq_sky130.v"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def last_int(pattern: str, text: str) -> int | None:
    matches = re.findall(pattern, text, flags=re.MULTILINE)
    return int(matches[-1]) if matches else None


def main() -> int:
    log = LOG.read_text(encoding="utf-8", errors="replace")
    driver = DRIVER.read_text(encoding="utf-8", errors="replace")
    netlist = NETLIST.read_text(encoding="utf-8", errors="replace")
    area_matches = re.findall(r"Chip area for top module .*?: ([0-9.]+)", log)
    sequential_matches = re.findall(r"used for sequential elements: ([0-9.]+) \(([0-9.]+)%\)", log)
    internal_cells = sorted(set(re.findall(r"\\?\$_[A-Za-z0-9_]+", netlist)))
    check_zero = log.count("Found and reported 0 problems.") >= 1
    pass_marker = "NORMALIZATION_HBM_TOP_SKY130_MAPPING PASS" in driver
    exit_zero = "Exit status: 0" in driver
    cell_matches = re.findall(r"^\s*(\d+)\s+\S+\s+cells$", log, flags=re.MULTILINE)
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "synthesized",
        "git_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
        "top": "logic_die_normalization_hbm_top",
        "variant": "wbq",
        "yosys_version": re.findall(r"Yosys 0\.68\+[^\n]+", log)[-1],
        "check_zero": check_zero,
        "unmapped_internal_primitive_count": len(internal_cells),
        "unmapped_internal_primitives": internal_cells,
        "latch_count": len(re.findall(r"\\?\$_DLATCH", netlist)),
        "mapped_cell_count_including_submodules": int(cell_matches[-1]) if cell_matches else None,
        "mapped_area_um2": float(area_matches[-1]),
        "sequential_area_um2": float(sequential_matches[-1][0]),
        "sequential_area_percent": float(sequential_matches[-1][1]),
        "elapsed_wall": re.findall(r"Elapsed \(wall clock\) time .*?: (.+)", driver)[-1],
        "maximum_rss_kbytes": last_int(r"Maximum resident set size \(kbytes\): (\d+)", driver),
        "warning_unique_count": int(re.findall(r"Warnings: (\d+) unique", log)[-1]),
        "warning_total_count": int(re.findall(r"Warnings: \d+ unique messages, (\d+) total", log)[-1]),
        "artifacts": {
            str(LOG.relative_to(ROOT)): sha(LOG),
            str(DRIVER.relative_to(ROOT)): sha(DRIVER),
            str(NETLIST.relative_to(ROOT)): sha(NETLIST),
        },
    }
    payload["gate_pass"] = bool(
        check_zero and not internal_cells and payload["latch_count"] == 0 and pass_marker and exit_zero
    )
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "wbq_synthesis_manifest.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    verdict = "PASS" if payload["gate_pass"] else "FAIL"
    html = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ Sky130 합성 보고서</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1050px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.pass{{padding:16px;background:#e7f6ed;border-left:6px solid #168154}}code{{word-break:break-all}}</style></head><body>
<h1>Phase 2 — wbq Sky130HD Technology Mapping</h1><div class=\"pass\"><strong>{verdict}</strong><br>Git <code>{payload['git_sha']}</code></div>
<h2>필수 게이트</h2><table>
<tr><th>Top</th><td>{payload['top']}</td></tr><tr><th>Variant</th><td>{payload['variant']}</td></tr>
<tr><th>Yosys check</th><td>{'0 problems' if check_zero else 'FAIL'}</td></tr>
<tr><th>Unmapped internal primitive</th><td>{len(internal_cells)}</td></tr><tr><th>의도하지 않은 latch</th><td>{payload['latch_count']}</td></tr></table>
<h2>정량 결과</h2><table><tr><th>Mapped cells</th><td>{payload['mapped_cell_count_including_submodules']:,}</td></tr>
<tr><th>Mapped area</th><td>{payload['mapped_area_um2']:,.4f} µm²</td></tr><tr><th>Sequential area</th><td>{payload['sequential_area_um2']:,.4f} µm² ({payload['sequential_area_percent']}%)</td></tr>
<tr><th>Wall time</th><td>{payload['elapsed_wall']}</td></tr><tr><th>Peak RSS</th><td>{payload['maximum_rss_kbytes'] / 1024:.1f} MiB</td></tr>
<tr><th>Warnings</th><td>{payload['warning_unique_count']} unique / {payload['warning_total_count']} total; 상세 분류는 raw log 참조</td></tr></table>
<h2>재현 명령</h2><pre>MAPPING_VARIANT=wbq bash verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh
python3 tools/collect_wbq_synthesis_evidence.py</pre>
<p><strong>Claim boundary:</strong> 공개 Sky130HD library의 technology-mapped 연구 결과다. Placement, routing, timing closure 또는 제조 공정 signoff를 증명하지 않는다. RESEARCH ARTIFACT — NOT FOR FABRICATION.</p>
</body></html>"""
    (OUT / "02_wbq_synthesis_report.html").write_text(html, encoding="utf-8")
    print(f"WBQ_SYNTHESIS_EVIDENCE {verdict} cells={payload['mapped_cell_count_including_submodules']} area={payload['mapped_area_um2']}")
    return 0 if payload["gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

