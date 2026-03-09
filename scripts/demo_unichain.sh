#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${UNICHAIN_RPC_URL:?UNICHAIN_RPC_URL is required}"
: "${DEPLOYER_PRIVATE_KEY:?DEPLOYER_PRIVATE_KEY is required}"
: "${TRADER_A_PRIVATE_KEY:?TRADER_A_PRIVATE_KEY is required}"
: "${TRADER_B_PRIVATE_KEY:?TRADER_B_PRIVATE_KEY is required}"

forge script script/20_DemoLifecycle.s.sol:DemoLifecycleScript \
  --rpc-url "$UNICHAIN_RPC_URL" \
  --broadcast \
  --slow \
  -vvvv

RUN_JSON="$(find broadcast/20_DemoLifecycle.s.sol -name 'run-latest.json' | head -n 1 || true)"
if [[ -n "$RUN_JSON" && -f "$RUN_JSON" ]]; then
  echo ""
  echo "Unichain demo transaction hashes:"
  jq -r '.transactions[]?.hash' "$RUN_JSON" | while read -r hash; do
    if [[ -n "${UNICHAIN_EXPLORER_TX_BASE:-}" ]]; then
      echo "$hash -> ${UNICHAIN_EXPLORER_TX_BASE}${hash}"
    else
      echo "$hash -> TBD"
    fi
  done
fi
