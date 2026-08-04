#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"

cd "$ROOT_DIR"

echo "[1/3] Accuracy tests"
./sim --gtest_filter=PIMKernelFixture.add
./sim --gtest_filter=PIMKernelFixture.relu
./sim --gtest_filter=PIMKernelFixture.mul
./sim --gtest_filter=PIMKernelFixture.gemv
./sim --gtest_filter=PIMKernelFixture.gemv_tree

echo "[2/3] Benchmark tests"
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv

echo "[3/3] Bandwidth tests"
./sim --gtest_filter=MemBandwidthFixture.hbm_read_bandwidth
./sim --gtest_filter=MemBandwidthFixture.hbm_write_bandwidth

echo "Done."
