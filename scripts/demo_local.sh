#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source ./.env 2>/dev/null || true

LOCAL_RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
# Local Anvil demo always deploys fresh contracts on the ephemeral chain.
DEMO_USE_EXISTING_DEPLOYMENT="false"
ANVIL_FUNDER_PRIVATE_KEY="${ANVIL_FUNDER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
LOCAL_GAS_TOPUP_WEI="${LOCAL_GAS_TOPUP_WEI:-5ether}"
: "${DEPLOYER_PRIVATE_KEY:?DEPLOYER_PRIVATE_KEY is required}"
: "${TRADER_A_PRIVATE_KEY:?TRADER_A_PRIVATE_KEY is required}"
: "${TRADER_B_PRIVATE_KEY:?TRADER_B_PRIVATE_KEY is required}"

deployer_addr="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
trader_a_addr="$(cast wallet address --private-key "$TRADER_A_PRIVATE_KEY")"
trader_b_addr="$(cast wallet address --private-key "$TRADER_B_PRIVATE_KEY")"
funder_addr="$(cast wallet address --private-key "$ANVIL_FUNDER_PRIVATE_KEY")"
funder_addr_lc="$(echo "$funder_addr" | tr '[:upper:]' '[:lower:]')"

echo "[Phase 0] Local actor setup + gas top-up"
echo "funder(default anvil): $funder_addr"
echo "deployer(owner): $deployer_addr"
echo "traderA(LP hedge actor): $trader_a_addr"
echo "traderB(directional trader): $trader_b_addr"

for addr in "$deployer_addr" "$trader_a_addr" "$trader_b_addr"; do
  addr_lc="$(echo "$addr" | tr '[:upper:]' '[:lower:]')"
  if [[ "$addr_lc" != "$funder_addr_lc" ]]; then
    cast send "$addr" --value "$LOCAL_GAS_TOPUP_WEI" --rpc-url "$LOCAL_RPC_URL" --private-key "$ANVIL_FUNDER_PRIVATE_KEY" >/dev/null
  fi
done

echo "[Phase A] Running local end-to-end lifecycle demo on Anvil"
DEMO_USE_EXISTING_DEPLOYMENT="$DEMO_USE_EXISTING_DEPLOYMENT" forge script script/20_DemoLifecycle.s.sol:DemoLifecycleScript \
  --rpc-url "$LOCAL_RPC_URL" \
  --broadcast \
  --slow \
  -vvvv

chain_id="$(cast chain-id --rpc-url "$LOCAL_RPC_URL")"
RUN_JSON="broadcast/20_DemoLifecycle.s.sol/${chain_id}/run-latest.json"
if [[ ! -f "$RUN_JSON" ]]; then
  RUN_JSON="$(find broadcast/20_DemoLifecycle.s.sol -name 'run-latest.json' | head -n 1 || true)"
fi
if [[ -n "$RUN_JSON" && -f "$RUN_JSON" ]]; then
  echo ""
  echo "=== Local Demo Tx Trace (phase proof) ==="
  jq -r '.transactions[]? | [.transactionType, (.contractName // "N/A"), (.contractAddress // "N/A"), (.hash // .transactionHash // "N/A")] | @tsv' "$RUN_JSON" \
    | while IFS=$'\t' read -r tx_type contract_name contract_addr hash; do
      printf "%-7s %-20s %s\n" "$tx_type" "$contract_name" "$hash"
      printf "        address: %s\n" "${contract_addr:-N/A}"
      printf "        url: N/A (anvil local)\n"
    done
  echo ""
  echo "Demo artifact: $RUN_JSON"
fi
