#!/usr/bin/env bash
# Unit tests, including the 46 Kiln wire v2 cases.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
# shellcheck disable=SC1091
source "${root}/scripts/swift-env.sh"
swift test
