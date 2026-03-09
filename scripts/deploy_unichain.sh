#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${UNICHAIN_RPC_URL:?UNICHAIN_RPC_URL is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"

source ./.env 2>/dev/null || true

forge script script/10_DeployPerps.s.sol:DeployPerpsScript \
  --rpc-url "$UNICHAIN_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow \
  -vvvv

BROADCAST_DIR="broadcast/10_DeployPerps.s.sol"
if [[ -d "$BROADCAST_DIR" ]]; then
  LATEST_RUN="$(find "$BROADCAST_DIR" -name 'run-latest.json' | head -n 1 || true)"
  if [[ -n "$LATEST_RUN" && -f "$LATEST_RUN" ]]; then
    echo ""
    echo "tx hashes:"
    jq -r '.transactions[]?.hash' "$LATEST_RUN" | while read -r hash; do
      if [[ -n "${UNICHAIN_EXPLORER_TX_BASE:-}" ]]; then
        echo "$hash -> ${UNICHAIN_EXPLORER_TX_BASE}${hash}"
      else
        echo "$hash -> TBD"
      fi
    done
  fi
fi
