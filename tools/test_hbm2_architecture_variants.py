from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = json.loads((ROOT / "design" / "hbm2_architecture.json").read_text(encoding="utf-8"))


def run_variant(name: str, dies: int, stacks: int, pseudo: bool = False, tsv_groups: int = 1) -> None:
    with tempfile.TemporaryDirectory(prefix=f"stob-hbm2-{name}-") as temp:
        temp_path = Path(temp)
        cfg = json.loads(json.dumps(BASE))
        cfg["dram_dies_per_stack"] = dies
        cfg["stack_count"] = stacks
        cfg["pseudo_channel_mode"] = pseudo
        cfg["layout"]["tsv_groups_per_channel"] = tsv_groups
        cfg["logical_channel_mapping"] = {
            "type": "multiple_hbm2_stacks",
            "logical_channels": stacks * cfg["physical_channels_per_stack"],
            "description": "Variant validation maps every logical channel to one physical channel.",
        }
        cfg_path = temp_path / "config.json"
        out_path = temp_path / "output"
        cfg_path.write_text(json.dumps(cfg), encoding="utf-8")
        subprocess.run([sys.executable, str(ROOT / "tools" / "generate_hbm2_architecture.py"),
                        "--config", str(cfg_path), "--output", str(out_path)], check=True)
        subprocess.run([sys.executable, str(ROOT / "tools" / "validate_hbm2_architecture.py"),
                        "--config", str(cfg_path), "--output", str(out_path)], check=True)


def main() -> int:
    run_variant("4hi-pseudo-tsv2", dies=4, stacks=1, pseudo=True, tsv_groups=2)
    run_variant("12hi-2stack", dies=12, stacks=2)
    with tempfile.TemporaryDirectory(prefix="stob-hbm2-invalid-map-") as temp:
        temp_path = Path(temp)
        cfg = json.loads(json.dumps(BASE))
        cfg["stack_count"] = 2
        cfg["logical_channel_mapping"] = {
            "type": "multiple_hbm2_stacks", "logical_channels": 64,
            "description": "Intentionally invalid mapping for validation.",
        }
        cfg_path, out_path = temp_path / "config.json", temp_path / "output"
        cfg_path.write_text(json.dumps(cfg), encoding="utf-8")
        subprocess.run([sys.executable, str(ROOT / "tools" / "generate_hbm2_architecture.py"),
                        "--config", str(cfg_path), "--output", str(out_path)], check=True,
                       stdout=subprocess.DEVNULL)
        invalid = subprocess.run([sys.executable, str(ROOT / "tools" / "validate_hbm2_architecture.py"),
                                  "--config", str(cfg_path), "--output", str(out_path)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if invalid.returncode == 0:
            raise AssertionError("contradictory physical/logical mapping was not rejected")
    print("HBM2_ARCH_VARIANTS PASS: 4Hi, 2x12Hi, and invalid mapping rejection")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
