#!/usr/bin/env bash
set -euo pipefail

install_root="${HOME}/.local/iverilog"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

rm -rf "${install_root}"
mkdir -p "${install_root}"
cd "${work_dir}"
apt download iverilog
dpkg-deb -x iverilog_*.deb "${install_root}"

echo "Icarus Verilog installed under ${install_root}"
