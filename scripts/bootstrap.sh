#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REQUIRED_V4_PERIPHERY_COMMIT="3779387e5d296f39df543d23524b050f89a62917"
V4_PERIPHERY_PATH="lib/uniswap-hooks/lib/v4-periphery"

if ! command -v forge >/dev/null 2>&1; then
  echo "[bootstrap] forge is required (https://book.getfoundry.sh/)" >&2
  exit 1
fi

echo "[bootstrap] initializing git submodules"
git submodule update --init --recursive

if [[ ! -d "$V4_PERIPHERY_PATH/.git" && ! -f "$V4_PERIPHERY_PATH/.git" ]]; then
  echo "[bootstrap] missing $V4_PERIPHERY_PATH after submodule init" >&2
  exit 1
fi

echo "[bootstrap] pinning v4-periphery to $REQUIRED_V4_PERIPHERY_COMMIT"
git -C "$V4_PERIPHERY_PATH" fetch origin main --tags

git -C "$V4_PERIPHERY_PATH" checkout "$REQUIRED_V4_PERIPHERY_COMMIT"
git -C "$V4_PERIPHERY_PATH" submodule update --init --recursive

CURRENT_COMMIT="$(git -C "$V4_PERIPHERY_PATH" rev-parse HEAD)"
if [[ "$CURRENT_COMMIT" != "$REQUIRED_V4_PERIPHERY_COMMIT" ]]; then
  echo "[bootstrap] v4-periphery commit mismatch: expected $REQUIRED_V4_PERIPHERY_COMMIT got $CURRENT_COMMIT" >&2
  exit 1
fi

echo "[bootstrap] verified v4-periphery commit $CURRENT_COMMIT"

if command -v npm >/dev/null 2>&1 && [[ -f package-lock.json ]]; then
  echo "[bootstrap] installing node dependencies with npm"
  npm ci
elif command -v pnpm >/dev/null 2>&1 && [[ -f pnpm-lock.yaml ]]; then
  echo "[bootstrap] installing node dependencies with pnpm"
  pnpm install --frozen-lockfile
else
  echo "[bootstrap] skipping node install (no lockfile tool found)"
fi

echo "[bootstrap] building solidity contracts"
forge build

echo "[bootstrap] done"
