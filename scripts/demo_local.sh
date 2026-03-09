#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
: "${DEPLOYER_PRIVATE_KEY:?DEPLOYER_PRIVATE_KEY is required}"
: "${TRADER_A_PRIVATE_KEY:?TRADER_A_PRIVATE_KEY is required}"
: "${TRADER_B_PRIVATE_KEY:?TRADER_B_PRIVATE_KEY is required}"

forge script script/20_DemoLifecycle.s.sol:DemoLifecycleScript \
  --rpc-url "$LOCAL_RPC_URL" \
  --broadcast \
  --slow \
  -vvvv

RUN_JSON="$(find broadcast/20_DemoLifecycle.s.sol -name 'run-latest.json' | head -n 1 || true)"
if [[ -n "$RUN_JSON" && -f "$RUN_JSON" ]]; then
  echo ""
  echo "Local demo transaction hashes:"
  jq -r '.transactions[]?.hash' "$RUN_JSON"
fi
