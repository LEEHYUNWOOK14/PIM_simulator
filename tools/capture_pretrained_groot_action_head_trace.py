#!/usr/bin/env python3
"""Capture BF16 normalization traces from the pretrained GR00T N1.7 action head.

This is a constrained fallback when the full gated backbone cannot be executed.
The boundary backbone/state tensors are deterministic synthetic BF16 values;
all captured internal tensors are produced by the published pretrained action
head weights.  Outputs are never labelled as full pretrained inference traces.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys
import types

import torch
from safetensors import safe_open
from transformers.feature_extraction_utils import BatchFeature


MODEL_REVISION = "2fc962b973bccdd5d8ce4f67cc63b264d6886495"
SEED = 1701


def classify(name: str) -> str | None:
    if name == "vlln":
        return "action_vlln"
    if name.startswith("vl_self_attention.transformer_blocks.") and name.endswith(".norm1"):
        return "action_vl_self_attention_norm1"
    if name.startswith("vl_self_attention.transformer_blocks.") and name.endswith(".norm3"):
        return "action_vl_self_attention_norm3"
    if name.startswith("model.transformer_blocks.") and name.endswith(".norm1.norm"):
        return "action_dit_adaln_norm1"
    if name.startswith("model.transformer_blocks.") and name.endswith(".norm3"):
        return "action_dit_norm3"
    if name == "model.norm_out":
        return "action_dit_norm_out"
    return None


def tensor_bytes(tensor: torch.Tensor) -> bytes:
    return tensor.detach().contiguous().cpu().view(torch.uint16).numpy().tobytes()


def stats(tensor: torch.Tensor) -> dict:
    value = tensor.detach().float().cpu()
    finite = torch.isfinite(value)
    finite_value = value[finite]
    return {
        "min": float(finite_value.min()) if finite_value.numel() else None,
        "max": float(finite_value.max()) if finite_value.numel() else None,
        "mean": float(finite_value.mean()) if finite_value.numel() else None,
        "std": float(finite_value.std(unbiased=False)) if finite_value.numel() else None,
        "nan_count": int(torch.isnan(value).sum()),
        "inf_count": int(torch.isinf(value).sum()),
        "zero_count": int((value == 0).sum()),
    }


def write_hex(path: Path, tensor: torch.Tensor) -> None:
    values = tensor.detach().contiguous().cpu().view(torch.uint16).reshape(-1).tolist()
    path.write_text("\n".join(f"{value:04x}" for value in values) + "\n", encoding="ascii")


def load_action_head(source: Path, checkpoint: Path, device: torch.device):
    sys.path.insert(0, str(source))
    from gr00t.configs.model.gr00t_n1d7 import Gr00tN1d7Config

    # Avoid gr00t.model.__init__, which imports the full training/data pipeline.
    model_package = types.ModuleType("gr00t.model")
    model_package.__path__ = [str(source / "gr00t" / "model")]
    sys.modules["gr00t.model"] = model_package
    from gr00t.model.gr00t_n1d7.gr00t_n1d7 import Gr00tN1d7ActionHead

    config_data = json.loads((checkpoint / "config.json").read_text(encoding="utf-8"))
    config = Gr00tN1d7Config(**config_data)
    with torch.device("meta"):
        action_head = Gr00tN1d7ActionHead(config)

    state = {}
    for shard in sorted(checkpoint.glob("model-*.safetensors")):
        with safe_open(shard, framework="pt", device="cpu") as handle:
            for name in handle.keys():
                if name.startswith("action_head."):
                    state[name.removeprefix("action_head.")] = handle.get_tensor(name)
    incompat = action_head.load_state_dict(state, strict=True, assign=True)
    if incompat.missing_keys or incompat.unexpected_keys:
        raise RuntimeError(f"state mismatch: {incompat}")
    del state
    return action_head.eval().to(device), config


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--sequence-length", type=int, default=280)
    parser.add_argument("--image-tokens", type=int, default=256)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    if args.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA requested but unavailable")
    device = torch.device(args.device)
    torch.manual_seed(SEED)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(SEED)

    action_head, config = load_action_head(args.source, args.checkpoint, device)
    if next(action_head.parameters()).dtype != torch.bfloat16:
        raise RuntimeError("checkpoint action head is not BF16")

    invocation_rows: list[dict] = []
    samples: dict[str, dict] = {}
    profile_counts: dict[str, int] = {}
    hooks = []

    def make_hook(module_name: str, profile: str):
        def hook(module, inputs, output):
            source = inputs[0].detach()
            result = output.detach()
            index = profile_counts.get(profile, 0)
            profile_counts[profile] = index + 1
            source_raw = tensor_bytes(source)
            result_raw = tensor_bytes(result)
            row = {
                "profile_id": profile,
                "module_path": f"action_head.{module_name}",
                "invocation_index": index,
                "shape": list(source.shape),
                "dtype": str(source.dtype).removeprefix("torch."),
                "epsilon": float(module.eps),
                "elementwise_affine": bool(module.elementwise_affine),
                "input_sha256": hashlib.sha256(source_raw).hexdigest(),
                "output_sha256": hashlib.sha256(result_raw).hexdigest(),
                "input_stats": stats(source),
                "output_stats": stats(result),
            }
            invocation_rows.append(row)
            if profile not in samples:
                sample_file = f"{profile}.pt"
                input_hex = f"{profile}_input_bf16.hex"
                output_hex = f"{profile}_output_bf16.hex"
                gamma_hex = f"{profile}_gamma_bf16.hex"
                beta_hex = f"{profile}_beta_bf16.hex"
                gamma = (
                    module.weight.detach()
                    if module.weight is not None
                    else torch.ones(source.shape[-1], device=source.device, dtype=source.dtype)
                )
                beta = (
                    module.bias.detach()
                    if module.bias is not None
                    else torch.zeros(source.shape[-1], device=source.device, dtype=source.dtype)
                )
                torch.save(
                    {
                        "classification": "PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT",
                        "profile_id": profile,
                        "module_path": row["module_path"],
                        "input": source.cpu(),
                        "output": result.cpu(),
                        "weight": gamma.cpu(),
                        "bias": beta.cpu(),
                        "epsilon": float(module.eps),
                    },
                    args.output / sample_file,
                )
                write_hex(args.output / input_hex, source)
                write_hex(args.output / output_hex, result)
                write_hex(args.output / gamma_hex, gamma)
                write_hex(args.output / beta_hex, beta)
                samples[profile] = {
                    "sample_file": sample_file,
                    "input_hex": input_hex,
                    "output_hex": output_hex,
                    "gamma_hex": gamma_hex,
                    "beta_hex": beta_hex,
                    "shape": list(source.shape),
                    "input_sha256": row["input_sha256"],
                    "output_sha256": row["output_sha256"],
                }

        return hook

    for name, module in action_head.named_modules():
        if isinstance(module, torch.nn.LayerNorm):
            profile = classify(name)
            if profile:
                hooks.append(module.register_forward_hook(make_hook(name, profile)))

    dtype = torch.bfloat16
    batch = 1
    seq = args.sequence_length
    hidden = int(config.backbone_embedding_dim)
    state_hidden = int(config.input_embedding_dim)
    generator = torch.Generator(device=device).manual_seed(SEED)
    backbone_features = torch.randn((batch, seq, hidden), device=device, dtype=dtype, generator=generator)
    state_features = torch.randn((batch, 1, state_hidden), device=device, dtype=dtype, generator=generator)
    image_mask = torch.zeros((batch, seq), device=device, dtype=torch.bool)
    image_mask[:, : min(args.image_tokens, seq)] = True
    attention_mask = torch.ones((batch, seq), device=device, dtype=torch.bool)
    embodiment_id = torch.zeros((batch,), device=device, dtype=torch.long)
    backbone_output = BatchFeature(
        data={"image_mask": image_mask, "backbone_attention_mask": attention_mask}
    )
    action_input = BatchFeature(data={})

    with torch.no_grad():
        processed_backbone = action_head.vlln(backbone_features)
        processed_backbone = action_head.vl_self_attention(processed_backbone)
        output = action_head.get_action_with_features(
            backbone_features=processed_backbone,
            state_features=state_features,
            embodiment_id=embodiment_id,
            backbone_output=backbone_output,
            action_input=action_input,
            options=None,
        )

    for handle in hooks:
        handle.remove()
    action_pred = output.action_pred.detach().cpu()
    torch.save(action_pred, args.output / "action_pred.pt")

    csv_rows = []
    for row in invocation_rows:
        flat = dict(row)
        flat["shape"] = json.dumps(flat["shape"])
        flat["input_stats"] = json.dumps(flat["input_stats"], sort_keys=True)
        flat["output_stats"] = json.dumps(flat["output_stats"], sort_keys=True)
        csv_rows.append(flat)
    with (args.output / "invocations.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(csv_rows[0]))
        writer.writeheader()
        writer.writerows(csv_rows)

    manifest = {
        "classification": "PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT",
        "not_full_groot_inference": True,
        "model": "nvidia/GR00T-N1.7-3B",
        "model_revision": MODEL_REVISION,
        "seed": SEED,
        "device": str(device),
        "gpu": torch.cuda.get_device_name(device) if device.type == "cuda" else None,
        "dtype": "bfloat16",
        "sequence_length": seq,
        "image_tokens": int(image_mask.sum()),
        "action_horizon": int(config.action_horizon),
        "denoise_steps": int(config.num_inference_timesteps),
        "profile_counts": profile_counts,
        "total_normalization_invocations": len(invocation_rows),
        "samples": samples,
        "action_pred_shape": list(action_pred.shape),
        "action_pred_sha256": hashlib.sha256(tensor_bytes(action_pred)).hexdigest(),
    }
    (args.output / "trace_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    summary_manifest = dict(manifest)
    summary_manifest["trace_directory"] = str(args.output)
    if args.output.parent.name == "actual_groot":
        (args.output.parent.parent / "groot_bf16_trace_manifest.json").write_text(
            json.dumps(summary_manifest, indent=2), encoding="utf-8"
        )
    print(
        "PRETRAINED_GROOT_ACTION_HEAD_TRACE PASS "
        f"invocations={len(invocation_rows)} profiles={len(profile_counts)} "
        f"dtype=BF16 device={device} classification={manifest['classification']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
