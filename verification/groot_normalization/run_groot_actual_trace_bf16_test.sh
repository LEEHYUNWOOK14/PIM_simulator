#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
# BF16 remains the external activation/gamma/beta/output format.  The legacy
# all-BF16 internal datapath is retained as a documented baseline, but it fails
# the 0.025 max-absolute-error gate.  C11 is the selected minimum passing path:
# FP32 statistics and fused affine internals with one final BF16 RNE conversion.
bash verification/groot_normalization/run_groot_mixed_precision_c11_trace_test.sh
echo "GROOT_ACTUAL_TRACE_BF16_REGRESSION PASS datapath=C11 external_format=BF16 profiles=6"
