#!/usr/bin/env bash
set -euo pipefail

install_root="${HOME}/.local/yosys"
work_dir="$(mktemp -d)"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

mkdir -p "${install_root}"
cd "${work_dir}"
apt download yosys yosys-abc python3-click libtcl8.6
for package in ./*.deb; do
    dpkg-deb -x "${package}" "${install_root}"
done

yosys_bin="${install_root}/usr/bin/yosys"
if [[ ! -x "${yosys_bin}" ]]; then
    echo "Yosys binary was not installed" >&2
    exit 1
fi

echo "YOSYS_LOCAL_INSTALL PASS"
PATH="${install_root}/usr/bin:${PATH}" \
LD_LIBRARY_PATH="${install_root}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" \
    "${yosys_bin}" -V
