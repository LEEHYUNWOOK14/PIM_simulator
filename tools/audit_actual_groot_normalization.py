#!/usr/bin/env python3
"""Build an evidence-labelled GR00T N1.7 normalization workload manifest.

The tool uses only Python's standard library.  It reads the pinned public
checkpoint config/index and safetensors headers without downloading tensor
payloads.  Runtime-dependent row counts remain explicitly unverified.
"""

from __future__ import annotations

import csv
import hashlib
import json
import struct
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "reports" / "groot_normalization" / "results"
OUT = RESULTS / "actual_groot"
OUT.mkdir(parents=True, exist_ok=True)

MODEL = "nvidia/GR00T-N1.7-3B"
MODEL_REVISION = "2fc962b973bccdd5d8ce4f67cc63b264d6886495"
ISAAC_GROOT_REVISION = "b9955401d50c92a29258732e3ad6ccd579f1bdc0"
BASE = f"https://huggingface.co/{MODEL}/resolve/{MODEL_REVISION}"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "STOB-PIM-workload-audit/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def fetch_json(name: str) -> dict:
    return json.loads(fetch(f"{BASE}/{name}"))


def fetch_safetensors_header(shard: str) -> dict:
    url = f"{BASE}/{shard}"
    first = urllib.request.Request(
        url, headers={"Range": "bytes=0-7", "User-Agent": "STOB-PIM-workload-audit/1"}
    )
    with urllib.request.urlopen(first, timeout=60) as response:
        prefix = response.read(8)
    if len(prefix) != 8:
        raise RuntimeError(f"short safetensors prefix for {shard}")
    header_len = struct.unpack("<Q", prefix)[0]
    if header_len <= 0 or header_len > 16 * 1024 * 1024:
        raise RuntimeError(f"invalid safetensors header length {header_len} for {shard}")
    header_request = urllib.request.Request(
        url,
        headers={
            "Range": f"bytes=8-{7 + header_len}",
            "User-Agent": "STOB-PIM-workload-audit/1",
        },
    )
    with urllib.request.urlopen(header_request, timeout=60) as response:
        raw = response.read(header_len)
    if len(raw) != header_len:
        raise RuntimeError(f"short safetensors header for {shard}: {len(raw)} != {header_len}")
    return json.loads(raw)


def weight_shape(headers: dict[str, dict], index: dict, name: str) -> list[int]:
    shard = index["weight_map"][name]
    return headers[shard][name]["shape"]


def add_row(manifest: list[dict], **values) -> None:
    defaults = {
        "model": MODEL,
        "model_revision": MODEL_REVISION,
        "isaac_groot_revision": ISAAC_GROOT_REVISION,
        "batch": 1,
        "rows": "dynamic",
        "rows_expression": "B*S",
        "representative_rows": "",
        "hidden_size": "",
        "epsilon": "",
        "elementwise_affine": "",
        "dynamic_modulation": False,
        "invocations_per_policy_call": "",
        "invocation_expression": "",
        "dtype": "BF16",
        "read_bytes_per_invocation": "dynamic",
        "write_bytes_per_invocation": "dynamic",
        "affine_bytes": "",
        "shape_status": "RUNTIME_TRACE_REQUIRED",
        "invocation_status": "CODE_AND_CHECKPOINT_DERIVED",
        "activation_status": "NOT_CAPTURED",
        "evidence": "pinned official source + checkpoint metadata",
    }
    defaults.update(values)
    hidden = defaults["hidden_size"]
    representative = defaults["representative_rows"]
    if hidden and representative != "":
        defaults["read_bytes_per_invocation"] = int(hidden) * int(representative) * 2
        defaults["write_bytes_per_invocation"] = int(hidden) * int(representative) * 2
    manifest.append(defaults)


def main() -> int:
    config = fetch_json("config.json")
    index = fetch_json("model.safetensors.index.json")
    shards = sorted(set(index["weight_map"].values()))
    headers = {shard: fetch_safetensors_header(shard) for shard in shards}

    (OUT / "checkpoint_config.json").write_text(json.dumps(config, indent=2), encoding="utf-8")
    metadata = {
        "model": MODEL,
        "model_revision": MODEL_REVISION,
        "isaac_groot_revision": ISAAC_GROOT_REVISION,
        "checkpoint_total_bytes": index["metadata"]["total_size"],
        "weight_count": len(index["weight_map"]),
        "shards": shards,
        "config_sha256": hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest(),
    }

    language_layers = sorted(
        {
            int(name.split(".layers.")[1].split(".")[0])
            for name in index["weight_map"]
            if "language_model.layers." in name
        }
    )
    vision_blocks = sorted(
        {
            int(name.split(".visual.blocks.")[1].split(".")[0])
            for name in index["weight_map"]
            if ".visual.blocks." in name
        }
    )
    dit_layers = int(config["diffusion_model_cfg"]["num_layers"])
    denoise_steps = int(config["num_inference_timesteps"])
    action_rows = 1 + int(config["action_horizon"])
    dit_hidden = int(config["diffusion_model_cfg"]["num_attention_heads"]) * int(
        config["diffusion_model_cfg"]["attention_head_dim"]
    )

    lang_norm_name = "backbone.model.model.language_model.layers.0.input_layernorm.weight"
    q_norm_name = "backbone.model.model.language_model.layers.0.self_attn.q_norm.weight"
    k_norm_name = "backbone.model.model.language_model.layers.0.self_attn.k_norm.weight"
    q_proj_name = "backbone.model.model.language_model.layers.0.self_attn.q_proj.weight"
    k_proj_name = "backbone.model.model.language_model.layers.0.self_attn.k_proj.weight"
    vision_norm_name = "backbone.model.model.visual.blocks.0.norm1.weight"
    lang_hidden = int(weight_shape(headers, index, lang_norm_name)[0])
    qk_hidden = int(weight_shape(headers, index, q_norm_name)[0])
    k_hidden = int(weight_shape(headers, index, k_norm_name)[0])
    query_heads = int(weight_shape(headers, index, q_proj_name)[0]) // qk_hidden
    key_value_heads = int(weight_shape(headers, index, k_proj_name)[0]) // k_hidden
    vision_hidden = int(weight_shape(headers, index, vision_norm_name)[0])

    rows: list[dict] = []
    add_row(
        rows,
        profile_id="backbone_language_input_rmsnorm",
        module_path="backbone.model.model.language_model.layers.*.input_layernorm",
        norm_type="RMSNorm",
        representative_rows=280,
        hidden_size=lang_hidden,
        epsilon="checkpoint subconfig unavailable; expected 1e-6",
        elementwise_affine=True,
        invocations_per_policy_call=len(language_layers),
        invocation_expression="language_layers",
        shape_status="LEGACY_280_REPRESENTATIVE_RUNTIME_UNVERIFIED",
    )
    add_row(
        rows,
        profile_id="backbone_language_post_attention_rmsnorm",
        module_path="backbone.model.model.language_model.layers.*.post_attention_layernorm",
        norm_type="RMSNorm",
        representative_rows=280,
        hidden_size=lang_hidden,
        epsilon="checkpoint subconfig unavailable; expected 1e-6",
        elementwise_affine=True,
        invocations_per_policy_call=len(language_layers),
        invocation_expression="language_layers",
        shape_status="LEGACY_280_REPRESENTATIVE_RUNTIME_UNVERIFIED",
    )
    add_row(
        rows,
        profile_id="backbone_language_q_rmsnorm",
        module_path="backbone.model.model.language_model.layers.*.self_attn.q_norm",
        norm_type="RMSNorm",
        rows_expression="B*S*query_heads",
        representative_rows=280 * query_heads,
        hidden_size=qk_hidden,
        epsilon="checkpoint subconfig unavailable; expected 1e-6",
        elementwise_affine=True,
        invocations_per_policy_call=len(language_layers),
        invocation_expression="language_layers",
        shape_status="CHECKPOINT_HEAD_COUNT_WITH_LEGACY_S280_RUNTIME_UNVERIFIED",
    )
    add_row(
        rows,
        profile_id="backbone_language_k_rmsnorm",
        module_path="backbone.model.model.language_model.layers.*.self_attn.k_norm",
        norm_type="RMSNorm",
        rows_expression="B*S*key_value_heads",
        representative_rows=280 * key_value_heads,
        hidden_size=k_hidden,
        epsilon="checkpoint subconfig unavailable; expected 1e-6",
        elementwise_affine=True,
        invocations_per_policy_call=len(language_layers),
        invocation_expression="language_layers",
        shape_status="CHECKPOINT_HEAD_COUNT_WITH_LEGACY_S280_RUNTIME_UNVERIFIED",
    )
    add_row(
        rows,
        profile_id="backbone_language_final_rmsnorm",
        module_path="backbone.model.model.language_model.norm",
        norm_type="RMSNorm",
        representative_rows=280,
        hidden_size=lang_hidden,
        epsilon="checkpoint subconfig unavailable; expected 1e-6",
        elementwise_affine=True,
        invocations_per_policy_call=1,
        invocation_expression="1",
        shape_status="LEGACY_280_REPRESENTATIVE_RUNTIME_UNVERIFIED",
    )
    for norm_name in ("norm1", "norm2"):
        add_row(
            rows,
            profile_id=f"backbone_visual_block_{norm_name}",
            module_path=f"backbone.model.model.visual.blocks.*.{norm_name}",
            norm_type="LayerNorm",
            rows_expression="B*vision_tokens",
            hidden_size=vision_hidden,
            epsilon="RUNTIME_MODULE_INTROSPECTION_REQUIRED",
            elementwise_affine=True,
            invocations_per_policy_call=len(vision_blocks),
            invocation_expression="vision_blocks",
        )
    add_row(
        rows,
        profile_id="action_vlln",
        module_path="action_head.vlln",
        norm_type="LayerNorm",
        representative_rows=280,
        hidden_size=int(config["backbone_embedding_dim"]),
        epsilon=1e-5,
        elementwise_affine=True,
        invocations_per_policy_call=1,
        invocation_expression="1",
        affine_bytes=int(config["backbone_embedding_dim"]) * 4,
        shape_status="LEGACY_280_REPRESENTATIVE_RUNTIME_UNVERIFIED",
    )
    vl_layers = int(config["vl_self_attention_cfg"]["num_layers"])
    for norm_name in ("norm1", "norm3"):
        add_row(
            rows,
            profile_id=f"action_vl_self_attention_{norm_name}",
            module_path=f"action_head.vl_self_attention.transformer_blocks.*.{norm_name}",
            norm_type="LayerNorm",
            representative_rows=280,
            hidden_size=int(config["backbone_embedding_dim"]),
            epsilon=1e-5,
            elementwise_affine=True,
            invocations_per_policy_call=vl_layers,
            invocation_expression="vl_self_attention_layers",
            affine_bytes=int(config["backbone_embedding_dim"]) * 4,
            shape_status="LEGACY_280_REPRESENTATIVE_RUNTIME_UNVERIFIED",
        )
    add_row(
        rows,
        profile_id="action_dit_adaln_norm1",
        module_path="action_head.model.transformer_blocks.*.norm1.norm",
        norm_type="AdaLayerNorm",
        rows=action_rows,
        rows_expression="B*(state_history_length+action_horizon)",
        representative_rows=action_rows,
        hidden_size=dit_hidden,
        epsilon=1e-5,
        elementwise_affine=False,
        dynamic_modulation=True,
        invocations_per_policy_call=dit_layers * denoise_steps,
        invocation_expression="dit_layers*num_inference_timesteps",
        affine_bytes=0,
        shape_status="CODE_AND_CHECKPOINT_DERIVED_FOR_BATCH1",
    )
    add_row(
        rows,
        profile_id="action_dit_norm3",
        module_path="action_head.model.transformer_blocks.*.norm3",
        norm_type="LayerNorm",
        rows=action_rows,
        rows_expression="B*(state_history_length+action_horizon)",
        representative_rows=action_rows,
        hidden_size=dit_hidden,
        epsilon=1e-5,
        elementwise_affine=True,
        invocations_per_policy_call=dit_layers * denoise_steps,
        invocation_expression="dit_layers*num_inference_timesteps",
        affine_bytes=dit_hidden * 4,
        shape_status="CODE_AND_CHECKPOINT_DERIVED_FOR_BATCH1",
    )
    add_row(
        rows,
        profile_id="action_dit_norm_out",
        module_path="action_head.model.norm_out",
        norm_type="LayerNorm",
        rows=action_rows,
        rows_expression="B*(state_history_length+action_horizon)",
        representative_rows=action_rows,
        hidden_size=dit_hidden,
        epsilon=1e-6,
        elementwise_affine=False,
        invocations_per_policy_call=denoise_steps,
        invocation_expression="num_inference_timesteps",
        affine_bytes=0,
        shape_status="CODE_AND_CHECKPOINT_DERIVED_FOR_BATCH1",
    )

    metadata.update(
        {
            "language_layers": len(language_layers),
            "vision_blocks": len(vision_blocks),
            "dit_layers": dit_layers,
            "denoise_steps": denoise_steps,
            "action_rows_batch1": action_rows,
            "language_hidden_size": lang_hidden,
            "q_norm_width": qk_hidden,
            "k_norm_width": k_hidden,
            "query_heads": query_heads,
            "key_value_heads": key_value_heads,
            "vision_hidden_size": vision_hidden,
            "manifest_profiles": len(rows),
            "static_invocations_with_known_counts": sum(
                int(row["invocations_per_policy_call"])
                for row in rows
                if row["invocations_per_policy_call"] != ""
            ),
            "runtime_status": "NO_PRETRAINED_INFERENCE_CAPTURE",
        }
    )
    fieldnames = list(rows[0].keys())
    payload = json.dumps({"metadata": metadata, "profiles": rows}, indent=2)
    for destination in (OUT, RESULTS):
        with (destination / "groot_actual_workload_manifest.csv").open(
            "w", newline="", encoding="utf-8"
        ) as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
        (destination / "groot_actual_workload_manifest.json").write_text(
            payload, encoding="utf-8"
        )
    print(
        "ACTUAL_GROOT_NORMALIZATION_AUDIT PASS "
        f"profiles={len(rows)} language_layers={len(language_layers)} "
        f"vision_blocks={len(vision_blocks)} dit_layers={dit_layers} steps={denoise_steps} "
        "runtime=NOT_CAPTURED"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
