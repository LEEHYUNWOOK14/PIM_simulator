#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/eda_environment.sh"

manifest="${1:-${repo_root}/reports/final_integrated_gds_execution/environment_manifest.json}"
mkdir -p "$(dirname "${manifest}")"

require_file() { [[ -f "$1" ]] || { echo "missing file: $1" >&2; exit 1; }; }
require_exe() { [[ -x "$1" ]] || { echo "missing executable: $1" >&2; exit 1; }; }

require_file "${sky130hd_liberty}"
require_file "${sky130hd_platform}/lef/sky130_fd_sc_hd_merged.lef"
require_exe "${openroad_exe}"
require_exe "${yosys_exe}"
require_exe "$(command -v iverilog)"
require_exe "$(command -v verilator)"
require_exe "$(command -v klayout)"

repo_sha="$(git -C "${repo_root}" rev-parse HEAD)"
repo_branch="$(git -C "${repo_root}" branch --show-current)"
repo_dirty=false
[[ -z "$(git -C "${repo_root}" status --porcelain)" ]] || repo_dirty=true
orfs_sha="$(git -C "${orfs_root}" rev-parse HEAD)"
openroad_sha="$(git -C "${orfs_root}/tools/OpenROAD" rev-parse HEAD)"
liberty_sha="$(sha256sum "${sky130hd_liberty}" | awk '{print $1}')"
lef_sha="$(sha256sum "${sky130hd_platform}/lef/sky130_fd_sc_hd_merged.lef" | awk '{print $1}')"
export repo_sha repo_branch repo_dirty orfs_sha openroad_sha liberty_sha lef_sha

python3 - "${manifest}" <<'PY'
import json, os, platform, shutil, subprocess, sys
from datetime import datetime, timezone

def output(*cmd):
    return subprocess.run(cmd, check=False, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT).stdout.strip()

manifest = {
    "schema_version": 1,
    "captured_at_utc": datetime.now(timezone.utc).isoformat(),
    "classification": "measured",
    "host": {
        "platform": platform.platform(),
        "kernel": platform.release(),
        "cpu_count": os.cpu_count(),
        "memory": output("free", "-h"),
        "disk": output("df", "-h", os.environ["STOB_REPO_ROOT"]),
        "swap": output("swapon", "--show"),
    },
    "git": {
        "repository": os.environ["STOB_REPO_ROOT"],
        "branch": os.environ["repo_branch"],
        "sha": os.environ["repo_sha"],
        "dirty": os.environ["repo_dirty"] == "true",
        "orfs_sha": os.environ["orfs_sha"],
        "openroad_sha": os.environ["openroad_sha"],
    },
    "paths": {key: os.environ[key] for key in (
        "ORFS_ROOT", "ORFS_FLOW_ROOT", "SKY130HD_PLATFORM", "SKY130HD_LIBERTY",
        "OPENROAD_EXE", "YOSYS_EXE", "PHYSICAL_REPORT_ROOT")},
    "hashes": {
        "sky130hd_liberty_sha256": os.environ["liberty_sha"],
        "sky130hd_merged_lef_sha256": os.environ["lef_sha"],
    },
    "tools": {
        "gcc": output("gcc", "--version").splitlines()[0],
        "g++": output("g++", "--version").splitlines()[0],
        "python": output("python3", "--version"),
        "scons": output("scons", "--version").splitlines()[0],
        "iverilog": output("iverilog", "-V").splitlines()[0],
        "verilator": output("verilator", "--version"),
        "yosys": output(os.environ["YOSYS_EXE"], "-V"),
        "openroad": output(os.environ["OPENROAD_EXE"], "-version"),
        "klayout": output("klayout", "-b", "-v"),
    },
    "expected": {
        "orfs_sha": "56496f3980fb6e9e58f10c8aea4a98949c0fe5f2",
        "openroad_sha": "ab6fd26351dc449e69059684dc6aa9ae9046eb36",
        "sky130hd_liberty_sha256": "ec0e1067a35c8bf20b11e58d1e8ac53326067e4dac84a125cc1b917a3518d0d9",
    },
}
manifest["gate_pass"] = (
    manifest["git"]["orfs_sha"] == manifest["expected"]["orfs_sha"] and
    manifest["git"]["openroad_sha"] == manifest["expected"]["openroad_sha"] and
    manifest["hashes"]["sky130hd_liberty_sha256"] == manifest["expected"]["sky130hd_liberty_sha256"]
)
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, ensure_ascii=False)
    stream.write("\n")
print(f"FINAL_GDS_ENVIRONMENT_PREFLIGHT {'PASS' if manifest['gate_pass'] else 'FAIL'}")
PY

python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["gate_pass"] else 1)' "${manifest}"
