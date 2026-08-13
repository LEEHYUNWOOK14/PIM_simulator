#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_exe="${STOB_GDS_MERGE_PYTHON:-$(command -v python3)}"
force=0

usage() {
  echo "usage: $0 [--force] RECIPE.json" >&2
  exit 2
}

while (($#)); do
  case "$1" in
    --force) force=1 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
  shift
done
test "$#" -eq 1 || usage
recipe="$1"

PYTHONPATH="$root/tools${PYTHONPATH:+:$PYTHONPATH}" \
  "$python_exe" -c 'import jsonschema; from klayout_python import kdb' \
  || { echo "Python lacks jsonschema/klayout_python: $python_exe" >&2; exit 3; }

arguments=("$root/tools/merge_final_rtl_gds.py" --recipe "$recipe")
if test "$force" -eq 1; then
  arguments+=(--force)
fi
(cd "$root" && "$python_exe" "${arguments[@]}")

# Reopen the emitted compact report in a separate Python process and bind its
# PASS claim to the exact bytes produced by the recipe.  The merger itself has
# already reopened the GDS through KLayout; this checks the persisted evidence
# contract that downstream clean-regeneration audits consume.
(cd "$root" && "$python_exe" - "$recipe" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

root = Path.cwd()


def absolute(value: str) -> Path:
    path = Path(os.path.expandvars(value))
    return path.resolve() if path.is_absolute() else (root / path).resolve()


recipe_path = absolute(sys.argv[1])
recipe = json.loads(recipe_path.read_text(encoding="utf-8-sig"))
gds = absolute(recipe["output"]["gds"])
report_path = absolute(recipe["output"]["report"])
if not gds.is_file() or not report_path.is_file():
    raise SystemExit("final merge output/report missing")
report = json.loads(report_path.read_text(encoding="utf-8-sig"))
actual_sha = hashlib.sha256(gds.read_bytes()).hexdigest()
shapes = report.get("geometry", {}).get("post_readback_shapes", {})
checks = {
    "status_pass": report.get("status") == "PASS",
    "not_signoff": report.get("signoff") is False,
    "gds_hash_match": report.get("output", {}).get("gds_sha256") == actual_sha,
    "rtl_shapes_preserved": shapes.get("rtl", 0) > 0 and shapes.get("rtl") == shapes.get("rtl_expected"),
    "overlay_shapes_preserved": shapes.get("overlay", 0) > 0 and shapes.get("overlay") == shapes.get("overlay_expected"),
    "two_top_instances": report.get("cell_namespace", {}).get("output_top_instance_count") == 2,
    "research_boundary": "RESEARCH ARTIFACT — NOT FOR FABRICATION" in report.get("claim_boundary", ""),
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("final merge persisted-evidence checks failed: " + ", ".join(failed))
print(f"FINAL_RTL_GDS_MERGE_LINUX PASS gds={gds} sha256={actual_sha}")
PY
)
