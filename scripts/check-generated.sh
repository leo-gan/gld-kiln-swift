#!/usr/bin/env bash
# Regenerate twice and diff against tests/generated.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
# shellcheck disable=SC1091
source "${root}/scripts/swift-env.sh"
swift build --product gld-kilngen-swift
binpath="$(swift build --product gld-kilngen-swift --show-bin-path)"
gen="${binpath}/gld-kilngen-swift"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/a" "${tmp}/b"
shopt -s nullglob
for schema in testdata/schema/*.json; do
  "${gen}" --schema "${schema}" --out "${tmp}/a"
  "${gen}" --schema "${schema}" --out "${tmp}/b"
done
diff -ru "${tmp}/a" "${tmp}/b"
diff -ru tests/generated "${tmp}/a"
