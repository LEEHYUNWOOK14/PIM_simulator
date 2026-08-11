from __future__ import annotations

import argparse
import json
import shutil
import tempfile
from pathlib import Path

import gdstk


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_PROVENANCE_FIELDS = {
    "value", "unit", "source_type", "source_repository_or_document",
    "source_file_line_or_section", "upstream_commit_hash", "confidence", "classification",
}
VALID_CLASSIFICATIONS = {
    "standard", "open_source_model", "project_config", "rtl_derived", "estimated", "illustrative",
}
VALID_LOGICAL_MAPPINGS = {
    "multiple_hbm2_stacks", "pseudo_channel_split", "simulator_only_logical_partition", "research_extension",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=ROOT / "design" / "hbm2_architecture.json")
    parser.add_argument("--output", type=Path, default=ROOT / "output" / "hbm2_arch")
    args = parser.parse_args()
    cfg = json.loads(args.config.resolve().read_text(encoding="utf-8"))
    output = args.output.resolve()
    manifest = json.loads((output / "generation_manifest.json").read_text(encoding="utf-8"))
    provenance = json.loads((output / "parameter_provenance.json").read_text(encoding="utf-8"))["parameters"]

    expected = {
        "stack_count": cfg["stack_count"],
        "dram_dies": cfg["dram_dies_per_stack"],
        "total_dram_die_instances": cfg["stack_count"] * cfg["dram_dies_per_stack"],
        "physical_channels_per_stack": cfg["physical_channels_per_stack"],
        "tsv_groups": cfg["stack_count"] * cfg["physical_channels_per_stack"] * cfg["layout"]["tsv_groups_per_channel"],
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            fail(f"manifest {key}={manifest.get(key)!r}, expected {value!r}")
    if manifest["banks_per_channel"] != 16 or manifest["pim_blocks_per_channel"] != 8:
        fail("SAIT bank/PIM counts were not reflected")
    expected_pseudo = cfg["physical_channels_per_stack"] * 2 if cfg["pseudo_channel_mode"] else 0
    if manifest["pseudo_channels_per_stack"] != expected_pseudo:
        fail("pseudo-channel mode was not reflected in the manifest")
    if not cfg.get("source_priority") or cfg["source_priority"][0] != "standard":
        fail("source priority must be explicit and standard-first for the default HBM2 profile")

    mapping = cfg["logical_channel_mapping"]
    if mapping["type"] not in VALID_LOGICAL_MAPPINGS:
        fail(f"logical mapping type must be explicit: {mapping['type']}")
    if mapping["logical_channels"] != cfg["physical_channels_per_stack"] and mapping["type"] == "multiple_hbm2_stacks":
        required_stacks = mapping["logical_channels"] / cfg["physical_channels_per_stack"]
        if required_stacks != cfg["stack_count"]:
            fail("multiple-stack logical mapping conflicts with physical stack count")
    if cfg["physical_channels_per_stack"] != 8 or cfg["channel_width_bits"] != 128:
        fail("default HBM2 profile must retain 8 x 128-bit physical channels")

    for name, record in provenance.items():
        missing = REQUIRED_PROVENANCE_FIELDS - set(record)
        if missing:
            fail(f"provenance {name} is missing {sorted(missing)}")
        if record["classification"] not in VALID_CLASSIFICATIONS:
            fail(f"invalid classification for {name}: {record['classification']}")

    gds_path = output / "hbm2_pim_architecture.gds"
    temp_gds = Path(tempfile.gettempdir()) / "stob_hbm2_validate.gds"
    shutil.copyfile(gds_path, temp_gds)
    lib = gdstk.read_gds(temp_gds)
    cell_names = {cell.name for cell in lib.cells}
    required_cells = {"HBM2_PIM_ARCHITECTURE_NOT_SIGNOFF", "HBM2_BASE_LOGIC_DIE"}
    required_cells.update(f"DRAM_DIE_{index:02d}_8PHYSICAL_CHANNELS" for index in range(cfg["dram_dies_per_stack"]))
    if not required_cells.issubset(cell_names):
        fail(f"missing GDS cells: {sorted(required_cells - cell_names)}")
    if len([name for name in cell_names if name.startswith("DRAM_DIE_")]) != cfg["dram_dies_per_stack"]:
        fail("GDS DRAM die hierarchy count differs from config")
    top = next(cell for cell in lib.cells if cell.name == "HBM2_PIM_ARCHITECTURE_NOT_SIGNOFF")
    direct_reference_names = [reference.cell_name for reference in top.references]
    expected_die_refs = cfg["stack_count"] * cfg["dram_dies_per_stack"]
    if len([name for name in direct_reference_names if name.startswith("DRAM_DIE_")]) != expected_die_refs:
        fail("GDS stack x die reference count differs from config")
    if len([polygon for polygon in top.polygons if polygon.layer == 50]) != manifest["tsv_shapes"]:
        fail("GDS TSV shape count differs from manifest")
    if len([polygon for polygon in top.polygons if polygon.layer == 40]) != manifest["microbump_shapes"]:
        fail("GDS micro-bump shape count differs from manifest")
    bank_cell = next(cell for cell in lib.cells if cell.name == "HBM2_CHANNEL_BANK_ARRAY_16BANKS")
    bank_shapes = [polygon for polygon in bank_cell.polygons if polygon.layer == 61 and polygon.datatype > 0]
    if len(bank_shapes) != manifest["banks_per_channel"]:
        fail("GDS bank-array hierarchy count differs from configuration")
    pim_shapes = [polygon for polygon in bank_cell.polygons if polygon.layer == 32]
    if len(pim_shapes) != manifest["pim_blocks_per_channel"]:
        fail("GDS bank-side PIM hierarchy count differs from configuration")
    first_die = next(cell for cell in lib.cells if cell.name == "DRAM_DIE_00_8PHYSICAL_CHANNELS")
    if len([reference for reference in first_die.references
            if reference.cell_name == "HBM2_CHANNEL_BANK_ARRAY_16BANKS"]) != cfg["physical_channels_per_stack"]:
        fail("GDS channel-to-bank-array hierarchy count differs from physical channels")

    layerstack = output / "hbm2_pim_architecture.layerstack"
    code = compile(layerstack.read_text(encoding="utf-8"), str(layerstack), "exec")
    namespace: dict[str, object] = {}
    exec(code, namespace)
    if "layerstack" not in namespace or not namespace["layerstack"]:
        fail("gds3xtrude layerstack did not define a non-empty layerstack")

    scad = (output / "hbm2_pim_architecture.scad").read_text(encoding="utf-8")
    if scad.count("{") != scad.count("}") or "not signoff layout" not in scad:
        fail("SCAD structural/disclaimer check failed")
    for required in ("model_summary.md", "cross_validation_report.md", "parameter_provenance.json",
                     "thermal_metadata.json", "hbm2_pim_architecture.lyp"):
        if not (output / required).is_file():
            fail(f"missing report: {required}")
    print("HBM2_ARCH_VALIDATION PASS")
    print(json.dumps(expected, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
