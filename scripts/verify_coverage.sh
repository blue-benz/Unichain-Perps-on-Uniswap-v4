#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_output="$(mktemp)"
trap 'rm -f "$tmp_output"' EXIT

FOUNDRY_PROFILE=coverage forge coverage --exclude-tests --report summary | tee "$tmp_output"

total_line="$(grep -E '^\| Total' "$tmp_output" | tail -n 1 || true)"
if [[ -z "$total_line" ]]; then
  echo "ERROR: Could not find Total coverage line in output."
  exit 1
fi

line_pct="$(echo "$total_line" | awk -F'|' '{gsub(/ /, "", $3); split($3, a, "%"); print a[1]}')"
if [[ "$line_pct" != "100.00" ]]; then
  echo "ERROR: Source line coverage must be 100.00%, got ${line_pct}%."
  exit 1
fi

echo "Coverage check passed: source line coverage is ${line_pct}%."
