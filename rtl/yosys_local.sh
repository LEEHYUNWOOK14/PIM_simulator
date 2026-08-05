#!/usr/bin/env bash
set -euo pipefail

install_root="${HOME}/.local/yosys"
yosys_bin="${install_root}/usr/bin/yosys"
if [[ ! -x "${yosys_bin}" ]]; then
    echo "Yosys not found. Run: bash rtl/bootstrap_yosys_local.sh" >&2
    exit 1
fi

export PATH="${install_root}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${install_root}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
exec "${yosys_bin}" "$@"
