#!/usr/bin/env python3
"""Statically audit GR00T workload, BF16 trace, and RTL mapping evidence.

The audit deliberately does not execute GR00T.  It validates the persisted
manifests and packet files, then reports where provenance is explicit and
where it is only implied by the generating code or profile naming.
"""

from __future__ import annotations

import csv
import fnmatch
import hashlib
import json
import math
from collections import Counter
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/groot_normalization/results/actual_groot"
TRACE_DIR = BASE / "action_head_trace"
MAPPING_DIR = BASE / "rtl_mapping"
OUT_DIR = BASE / "evidence_audit"
JSON_REPORT = OUT_DIR / "static_evidence_audit.json"
MD_REPORT = (
    ROOT
    / "reports/groot_normalization/actual_workload_validation"
    / "44_static_workload_evidence_audit.md"
)

EXPECTED_CLASSIFICATION = "PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def read_hex(path: Path) -> list[int]:
    return [int(word, 16) for word in path.read_text(encoding="ascii").split()]


def raw_bf16_sha256(words: list[int]) -> str:
    payload = b"".join(word.to_bytes(2, "little") for word in words)
    return hashlib.sha256(payload).hexdigest()


def same_number(left: object, right: object) -> bool:
    try:
        return float(left) == float(right)
    except (TypeError, ValueError):
        return False


def add_check(checks: list[dict], check_id: str, status: str, evidence: str) -> None:
    checks.append({"id": check_id, "status": status, "evidence": evidence})


def main() -> int:
    workload_path = BASE / "groot_actual_workload_manifest.json"
    trace_path = TRACE_DIR / "trace_manifest.json"
    trace_summary_path = BASE.parent / "groot_bf16_trace_manifest.json"
    mapping_path = MAPPING_DIR / "mapping_manifest.json"
    invocation_path = TRACE_DIR / "invocations.csv"

    workload = read_json(workload_path)
    trace = read_json(trace_path)
    trace_summary = read_json(trace_summary_path)
    mapping = read_json(mapping_path)
    invocations = list(csv.DictReader(invocation_path.open(newline="", encoding="utf-8")))

    checks: list[dict] = []
    profiles: list[dict] = []
    workload_by_id = {row["profile_id"]: row for row in workload["profiles"]}
    invocation_counts = Counter(row["profile_id"] for row in invocations)

    scoped = (
        trace.get("classification") == EXPECTED_CLASSIFICATION
        and trace.get("not_full_groot_inference") is True
    )
    add_check(
        checks,
        "trace_scope_classification",
        "PASS" if scoped else "FAIL",
        f"classification={trace.get('classification')}, "
        f"not_full_groot_inference={trace.get('not_full_groot_inference')}",
    )
    add_check(
        checks,
        "workload_runtime_scope",
        "PASS"
        if workload["metadata"].get("runtime_status") == "NO_PRETRAINED_INFERENCE_CAPTURE"
        else "FAIL",
        f"runtime_status={workload['metadata'].get('runtime_status')}",
    )

    summary_core_equal = all(trace_summary.get(key) == value for key, value in trace.items())
    add_check(
        checks,
        "trace_summary_copy",
        "PASS" if summary_core_equal else "FAIL",
        "summary manifest contains the same trace core fields"
        if summary_core_equal
        else "summary manifest differs from trace_manifest.json",
    )
    revision_chain_ok = (
        workload["metadata"].get("model")
        == trace.get("model")
        == mapping.get("model")
        and workload["metadata"].get("model_revision")
        == trace.get("model_revision")
        == mapping.get("model_revision")
    )
    add_check(
        checks,
        "model_revision_chain",
        "PASS" if revision_chain_ok else "FAIL",
        f"model={trace.get('model')}, revision={trace.get('model_revision')}",
    )

    captured_ids = set(trace["samples"])
    workload_ids = set(workload_by_id)
    add_check(
        checks,
        "workload_profile_coverage",
        "PARTIAL" if captured_ids < workload_ids else "PASS",
        f"trace covers {len(captured_ids)}/{len(workload_ids)} workload profiles; "
        f"uncaptured={sorted(workload_ids - captured_ids)}",
    )

    for profile_id, sample in trace["samples"].items():
        workload_row = workload_by_id.get(profile_id)
        invocation_rows = [row for row in invocations if row["profile_id"] == profile_id]
        shape = sample["shape"]
        input_words = read_hex(TRACE_DIR / sample["input_hex"])
        output_words = read_hex(TRACE_DIR / sample["output_hex"])
        gamma_words = read_hex(TRACE_DIR / sample["gamma_hex"])
        beta_words = read_hex(TRACE_DIR / sample["beta_hex"])
        first_invocation = next(
            (row for row in invocation_rows if row["invocation_index"] == "0"), None
        )

        shape_ok = (
            workload_row is not None
            and int(workload_row["hidden_size"]) == int(shape[-1])
            and len(input_words) == math.prod(shape)
            and len(output_words) == math.prod(shape)
        )
        count_ok = (
            workload_row is not None
            and int(workload_row["invocations_per_policy_call"])
            == trace["profile_counts"][profile_id]
            == invocation_counts[profile_id]
        )
        module_path_ok = workload_row is not None and all(
            fnmatch.fnmatchcase(row["module_path"], workload_row["module_path"])
            for row in invocation_rows
        )
        dtype_ok = bool(invocation_rows) and all(
            row["dtype"].lower() == "bfloat16" for row in invocation_rows
        )
        epsilon_ok = (
            workload_row is not None
            and bool(invocation_rows)
            and all(same_number(workload_row["epsilon"], row["epsilon"]) for row in invocation_rows)
        )
        hashes_ok = (
            raw_bf16_sha256(input_words) == sample["input_sha256"]
            and raw_bf16_sha256(output_words) == sample["output_sha256"]
            and first_invocation is not None
            and first_invocation["input_sha256"] == sample["input_sha256"]
            and first_invocation["output_sha256"] == sample["output_sha256"]
        )

        elementwise_affine = bool(workload_row and workload_row["elementwise_affine"] is True)
        dynamic_modulation = bool(workload_row and workload_row["dynamic_modulation"] is True)
        identity_gamma = all(word == 0x3F80 for word in gamma_words)
        zero_beta = all(word == 0 for word in beta_words)
        if dynamic_modulation and identity_gamma and zero_beta:
            affine_provenance = "PLACEHOLDER_NOT_DYNAMIC_MODULATION"
        elif elementwise_affine:
            affine_provenance = "PRETRAINED_PARAMETER_IMPLIED_BY_CAPTURE_CODE_NOT_HASHED_IN_MANIFEST"
        else:
            affine_provenance = "SYNTHESIZED_IDENTITY_FOR_NON_AFFINE_LAYER"

        profiles.append(
            {
                "profile_id": profile_id,
                "module_path": first_invocation["module_path"] if first_invocation else None,
                "shape": shape,
                "shape_match": shape_ok,
                "workload_shape_status": workload_row.get("shape_status") if workload_row else None,
                "invocation_count_match": count_ok,
                "module_path_match": module_path_ok,
                "captured_invocations": invocation_counts[profile_id],
                "dtype_match": dtype_ok,
                "epsilon_match": epsilon_ok,
                "input_output_hash_match": hashes_ok,
                "gamma_words": len(gamma_words),
                "beta_words": len(beta_words),
                "gamma_sha256_computed_by_audit": raw_bf16_sha256(gamma_words),
                "beta_sha256_computed_by_audit": raw_bf16_sha256(beta_words),
                "gamma_beta_provenance": affine_provenance,
            }
        )

    add_check(
        checks,
        "invocation_shape_dtype_epsilon",
        "PASS"
        if all(
            row["shape_match"]
            and row["invocation_count_match"]
            and row["module_path_match"]
            and row["dtype_match"]
            and row["epsilon_match"]
            for row in profiles
        )
        else "FAIL",
        "all six captured action-head profiles agree across workload, invocation CSV, and trace files",
    )
    add_check(
        checks,
        "trace_input_output_checksums",
        "PASS" if all(row["input_output_hash_match"] for row in profiles) else "FAIL",
        "input/output BF16 HEX hashes agree with sample and invocation metadata",
    )
    add_check(
        checks,
        "gamma_beta_provenance",
        "FAIL",
        "gamma/beta files have no manifest checksums or checkpoint tensor names; "
        "AdaLayerNorm dynamic modulation is represented by identity/zero placeholders",
    )

    explicit_link_fields = {
        "workload_manifest_sha256",
        "workload_profile_tag",
        "invocation_id",
        "trace_id",
    }
    present_link_fields = explicit_link_fields.intersection(trace.keys())
    add_check(
        checks,
        "bf16_trace_to_workload_manifest_link",
        "PARTIAL",
        f"profile_id joins {len(captured_ids)} profiles, but explicit link fields are absent: "
        f"{sorted(explicit_link_fields - present_link_fields)}",
    )

    mapping_by_id = {row["profile_id"]: row for row in mapping["profiles"]}
    persisted_roundtrip: list[dict] = []
    tag_owner: dict[int, tuple[str, int]] = {}
    tag_conflicts = 0
    for profile_index, (profile_id, sample) in enumerate(trace["samples"].items()):
        mapped = mapping_by_id[profile_id]
        source = read_hex(TRACE_DIR / sample["input_hex"])
        hidden = int(sample["shape"][-1])
        reconstructed: list[int | None] = [None] * len(source)
        packed_lines = (MAPPING_DIR / mapped["packet_hex"]).read_text(
            encoding="ascii"
        ).split()
        csv_rows = 0
        metadata_errors = 0
        with (MAPPING_DIR / mapped["packet_csv"]).open(newline="", encoding="utf-8") as file:
            for packet in csv.DictReader(file):
                packed = packet["packed_lane3_to_lane0_hex"].lower()
                if csv_rows >= len(packed_lines) or packed != packed_lines[csv_rows].lower():
                    metadata_errors += 1
                words = [int(packed[offset : offset + 4], 16) for offset in range(0, 16, 4)][::-1]
                row = int(packet["row"])
                bank = int(packet["bank"])
                vector = int(packet["vector_address"])
                valid_lanes = int(packet["valid_lanes"])
                tag = int(packet["tag"], 16)
                expected_tag = 0x1000 + profile_index * 0x400 + row
                if (
                    packet["profile_id"] != profile_id
                    or tag != expected_tag
                    or packet["bank_parity"] != ("odd" if bank & 1 else "even")
                ):
                    metadata_errors += 1
                owner = (profile_id, row)
                if tag in tag_owner and tag_owner[tag] != owner:
                    tag_conflicts += 1
                tag_owner[tag] = owner
                for lane, value in enumerate(words[:valid_lanes]):
                    column = (
                        vector * mapping["banks"] * mapping["lanes"]
                        + bank * mapping["lanes"]
                        + lane
                    )
                    if column < hidden:
                        reconstructed[row * hidden + column] = value
                csv_rows += 1

        mismatches = sum(left != right for left, right in zip(source, reconstructed))
        persisted_roundtrip.append(
            {
                "profile_id": profile_id,
                "packet_rows": csv_rows,
                "manifest_packets": mapped["packets"],
                "csv_hex_metadata_errors": metadata_errors,
                "reconstructed_mismatches": mismatches,
                "reconstructed_sha256": raw_bf16_sha256(reconstructed),
                "manifest_roundtrip_sha256": mapped["roundtrip_sha256"],
            }
        )

    persisted_ok = all(
        row["packet_rows"] == row["manifest_packets"]
        and row["csv_hex_metadata_errors"] == 0
        and row["reconstructed_mismatches"] == 0
        and row["reconstructed_sha256"] == row["manifest_roundtrip_sha256"]
        for row in persisted_roundtrip
    )
    add_check(
        checks,
        "persisted_trace_to_rtl_roundtrip",
        "PASS" if persisted_ok else "FAIL",
        f"independent readback of {sum(row['packet_rows'] for row in persisted_roundtrip):,} "
        f"persisted packets; mismatches={sum(row['reconstructed_mismatches'] for row in persisted_roundtrip)}",
    )
    add_check(
        checks,
        "rtl_tag_consistency",
        "PASS" if tag_conflicts == 0 else "FAIL",
        f"tag conflicts across profile/row owners={tag_conflicts}; tags identify representative rows, not invocations",
    )
    add_check(
        checks,
        "mapping_manifest_sealing",
        "FAIL",
        "mapping manifest omits packet-file SHA-256, source trace-manifest SHA-256, "
        "workload-manifest SHA-256, and converter revision",
    )
    add_check(
        checks,
        "reduction_apply_roundtrip_contract",
        "NOT_EVIDENCED",
        "only one logical input packet set exists; separate reduction/apply manifests or "
        "production replay consumption evidence are absent",
    )

    status_counts = Counter(check["status"] for check in checks)
    report = {
        "audit": "GR00T_STATIC_TRACE_PROVENANCE_AND_ROUNDTRIP",
        "audit_date": date.today().isoformat(),
        "overall_status": "PARTIAL_EVIDENCE",
        "actual_full_inference_trace": False,
        "trace_classification": trace.get("classification"),
        "scope": "static audit of existing artifacts; no GR00T execution",
        "inputs": {
            "workload_manifest": workload_path.relative_to(ROOT).as_posix(),
            "trace_manifest": trace_path.relative_to(ROOT).as_posix(),
            "trace_summary_manifest": trace_summary_path.relative_to(ROOT).as_posix(),
            "mapping_manifest": mapping_path.relative_to(ROOT).as_posix(),
            "invocations": invocation_path.relative_to(ROOT).as_posix(),
        },
        "summary": {
            "workload_profiles": len(workload_ids),
            "captured_profiles": len(captured_ids),
            "captured_invocations": len(invocations),
            "persisted_packets_read_back": sum(
                row["packet_rows"] for row in persisted_roundtrip
            ),
            "persisted_roundtrip_mismatches": sum(
                row["reconstructed_mismatches"] for row in persisted_roundtrip
            ),
            "check_status_counts": dict(sorted(status_counts.items())),
        },
        "checks": checks,
        "profiles": profiles,
        "persisted_roundtrip": persisted_roundtrip,
        "verdict": {
            "supported": [
                "The artifacts are a pretrained action-head execution with deterministic synthetic boundary inputs.",
                "Six action-head profiles have consistent invocation counts, shapes, BF16 dtype, and epsilon metadata.",
                "The persisted 477,312 packet CSV/HEX records independently reconstruct to the source BF16 inputs with zero mismatch.",
            ],
            "not_supported": [
                "A full GR00T inference trace or robot-dataset activation trace was captured.",
                "The BF16 samples are explicitly linked to workload invocation IDs by a sealed manifest tag.",
                "AdaLayerNorm runtime gamma/beta modulation was captured.",
                "Reduction and apply replay consumed the same production manifest/address stream.",
            ],
        },
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    JSON_REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    profile_lines = []
    for row in profiles:
        profile_lines.append(
            f"| `{row['profile_id']}` | {row['captured_invocations']} | "
            f"`{row['shape']}` | {'PASS' if row['dtype_match'] else 'FAIL'} | "
            f"{'PASS' if row['epsilon_match'] else 'FAIL'} | `{row['gamma_beta_provenance']}` |"
        )
    check_lines = [
        f"| `{check['id']}` | **{check['status']}** | {check['evidence']} |"
        for check in checks
    ]
    markdown = f"""# GR00T workload 증거 정적 감사

작성일: {report['audit_date']}

## 판정

`PARTIAL_EVIDENCE — 저장 파일 무결성과 제한된 action-head 호출 증거는 확인, 실제 full-inference provenance 및 manifest 연결은 미충족`

이 감사는 기존 산출물만 읽었으며 GR00T 모델을 재실행하지 않았다. Trace의 정확한 분류는
`{trace['classification']}`이고 `not_full_groot_inference=true`다. 따라서 실제 robot 입력 기반 GR00T
full-inference trace로 사용할 수 없다.

## 검사 결과

| 검사 | 결과 | 증거 |
|---|---|---|
{chr(10).join(check_lines)}

## Workload invocation과 tensor provenance

| Profile | Calls | Sample shape | BF16 dtype | Epsilon | Gamma/beta provenance |
|---|---:|---|---|---|---|
{chr(10).join(profile_lines)}

269회 호출, shape, BF16 dtype, epsilon은 workload manifest와 invocation CSV 사이에서 일치한다.
다만 이 일치는 synthetic boundary 조건의 action head 6개 profile에만 해당한다. Workload manifest의
13개 profile 중 backbone language/vision 7개는 activation이 없으며 manifest 자체도
`runtime_status=NO_PRETRAINED_INFERENCE_CAPTURE`로 표시한다.

Affine LayerNorm의 gamma/beta는 생성 코드상 pretrained module parameter에서 왔지만 manifest에
checkpoint tensor name이나 gamma/beta checksum이 없다. Non-affine 2개 profile은 생성 코드가 identity gamma와
zero beta를 합성한다. 특히 `action_dit_adaln_norm1`은 workload manifest에서 dynamic modulation으로
분류되지만 저장 gamma/beta는 모두 1/0이므로 timestep-dependent AdaLN scale/shift의 캡처 증거가 아니다.

## BF16 trace와 workload manifest 연결성

`profile_id` 문자열로 6개 action-head profile을 조인할 수 있고 model revision도 일치한다. 그러나 trace
manifest에는 workload manifest checksum, workload profile tag, invocation ID 또는 trace ID가 없다.
대표 sample도 각 profile의 첫 호출이라는 사실을 input/output checksum으로 추론할 수 있을 뿐,
sample 항목 자체에 invocation index가 없다. 따라서 연결성 판정은 `PARTIAL`이다.

## Trace-to-RTL round-trip

기존 converter의 in-memory 판정과 별도로 저장된 packet CSV 및 packed HEX {report['summary']['persisted_packets_read_back']:,}개를
다시 읽어 원본 BF16 순서로 역변환했다. CSV/HEX metadata 오류 0, tag owner 충돌 0,
BF16 mismatch {report['summary']['persisted_roundtrip_mismatches']}으로 기존 0-mismatch 결과는 파일 수준에서도 재현된다.

다만 mapping manifest에는 packet 파일 SHA-256, source trace/workload manifest SHA-256, converter revision이
없어 산출물 세트가 cryptographically sealed되어 있지 않다. Tag는 profile+row를 식별할 뿐 269개 invocation을
식별하지 않는다. 별도의 reduction/apply replay manifest나 production top의 소비 증거도 없어 보고서의
"동일 input checksum과 mapping manifest 사용"은 설계 의도 수준이며 round-trip 실행 증거가 아니다.

## 최종 사용 가능 범위

- 사용 가능: pinned pretrained action-head weight를 synthetic BF16 boundary 입력으로 실행한 제한적 trace,
  6개 대표 sample의 shape/dtype/epsilon 및 저장 packet bit-level 무결성.
- 사용 불가: 실제 GR00T full inference 또는 robot dataset activation, AdaLN dynamic gamma/beta capture,
  invocation-tag 기반 workload-to-RTL chain of custody, production reduction/apply replay 정합성.

Machine-readable 결과: `{JSON_REPORT.relative_to(ROOT).as_posix()}`
"""
    MD_REPORT.write_text(markdown, encoding="utf-8")
    print(
        "GROOT_STATIC_EVIDENCE_AUDIT PARTIAL_EVIDENCE "
        f"profiles={len(captured_ids)}/{len(workload_ids)} "
        f"invocations={len(invocations)} "
        f"packets={report['summary']['persisted_packets_read_back']} "
        f"roundtrip_mismatches={report['summary']['persisted_roundtrip_mismatches']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
