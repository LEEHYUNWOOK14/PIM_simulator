#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYERS="${LAYERS:-uib14_extra_expand uib14_ib_expand uib14_extra_project}"
DEPTH_LIST="${DEPTH_LIST:-32 64 128}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/mobilenetv4_pointwise_shape_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

extract_csv_field() {
  local layer="$1" column="$2"
  awk -F, -v layer="$layer" -v column="$column" '
    NR == 1 { for (i = 1; i <= NF; i++) columns[$i] = i; next }
    $1 == layer { print $columns[column]; exit }
  ' "$ROOT_DIR/data/mobilenetv4/conv_small_uib14.csv"
}

first=true
for layer in $LAYERS; do
  height="$(extract_csv_field "$layer" height)"
  width="$(extract_csv_field "$layer" width)"
  input_channels="$(extract_csv_field "$layer" input_channels)"
  output_channels="$(extract_csv_field "$layer" output_channels)"
  if [[ -z "$height" || -z "$width" || -z "$input_channels" || -z "$output_channels" ]]; then
    echo "Unknown layer in workload CSV: $layer" >&2
    exit 1
  fi

  for depth in $DEPTH_LIST; do
    echo "[pointwise layer=$layer depth=$depth]"
    child="$TMP_DIR/${layer}_${depth}.csv"
    MOBILENETV4_LAYER_NAME="$layer" \
    TEST_FILTER=MobileNetV4WorkloadTest.PointwiseBatchRunsMobileNetV4Shape \
    RESULT_MARKER=MOBILENETV4_BATCH_POINTWISE_RESULT \
    FILL_POLICY=row_interleaved FILL_CHANNELS_LIST=32 \
    BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
    POST_FILL_GUARD_CYCLES=0 EPOCH_RELEASE=true \
    ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH="$depth" \
    RESULT_FILE="$child" \
      bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null

    if [[ "$first" == "true" ]]; then
      printf 'layer,height,width,input_channels,output_channels,' > "$RESULT_FILE"
      head -n 1 "$child" >> "$RESULT_FILE"
      first=false
    fi
    printf '%s,%s,%s,%s,%s,' "$layer" "$height" "$width" \
      "$input_channels" "$output_channels" >> "$RESULT_FILE"
    tail -n 1 "$child" >> "$RESULT_FILE"
  done
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
