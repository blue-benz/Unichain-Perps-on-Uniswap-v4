#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source ./.env 2>/dev/null || true

UNICHAIN_RPC_URL="${UNICHAIN_RPC_URL:-${SEPOLIA_RPC_URL:-}}"
DEPLOYER_PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY:-${SEPOLIA_PRIVATE_KEY:-}}"
UNICHAIN_EXPLORER_TX_BASE="${UNICHAIN_EXPLORER_TX_BASE:-https://sepolia.uniscan.xyz/tx/}"
TRADER_GAS_TOPUP_WEI="${TRADER_GAS_TOPUP_WEI:-0.01ether}"
TOPUP_MIN_BALANCE_WEI="${TOPUP_MIN_BALANCE_WEI:-5000000000000000}"

: "${UNICHAIN_RPC_URL:?UNICHAIN_RPC_URL (or SEPOLIA_RPC_URL) is required}"
: "${DEPLOYER_PRIVATE_KEY:?DEPLOYER_PRIVATE_KEY (or SEPOLIA_PRIVATE_KEY) is required}"
: "${TRADER_A_PRIVATE_KEY:?TRADER_A_PRIVATE_KEY is required}"
: "${TRADER_B_PRIVATE_KEY:?TRADER_B_PRIVATE_KEY is required}"

require_deployment=true
for key in COLLATERAL_VAULT_ADDRESS RISK_MANAGER_ADDRESS PERPS_ENGINE_ADDRESS PERPS_HOOK_ADDRESS LIQUIDATION_MODULE_ADDRESS MARKET_ID POOL_CURRENCY0 POOL_CURRENCY1; do
  if [[ -z "${!key:-}" ]]; then
    require_deployment=true
    break
  fi
  require_deployment=false
done

if [[ "$require_deployment" == "true" ]]; then
  echo "[Phase A] No complete Unichain deployment found in .env; deploying first..."
  ./scripts/deploy_unichain.sh
  source ./.env
fi

deployer_addr="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
trader_a_addr="$(cast wallet address --private-key "$TRADER_A_PRIVATE_KEY")"
trader_b_addr="$(cast wallet address --private-key "$TRADER_B_PRIVATE_KEY")"
deployer_addr_lc="$(echo "$deployer_addr" | tr '[:upper:]' '[:lower:]')"
trader_a_addr_lc="$(echo "$trader_a_addr" | tr '[:upper:]' '[:lower:]')"
trader_b_addr_lc="$(echo "$trader_b_addr" | tr '[:upper:]' '[:lower:]')"

echo "[Phase B] User perspective actor setup"
echo "deployer(owner): $deployer_addr"
echo "traderA(LP hedge actor): $trader_a_addr"
echo "traderB(directional trader): $trader_b_addr"

topup_if_needed() {
  local addr="$1"
  local addr_lc="$2"
  if [[ "$addr_lc" == "$deployer_addr_lc" ]]; then
    return
  fi

  local balance
  balance="$(cast balance "$addr" --rpc-url "$UNICHAIN_RPC_URL")"
  if [[ "$balance" -lt "$TOPUP_MIN_BALANCE_WEI" ]]; then
    cast send "$addr" --value "$TRADER_GAS_TOPUP_WEI" --rpc-url "$UNICHAIN_RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" >/dev/null
  fi
}

topup_if_needed "$trader_a_addr" "$trader_a_addr_lc"
topup_if_needed "$trader_b_addr" "$trader_b_addr_lc"

echo "[Phase C] Running lifecycle demo script (reusing deployed addresses from .env)"
DEMO_USE_EXISTING_DEPLOYMENT=true forge script script/20_DemoLifecycle.s.sol:DemoLifecycleScript \
  --rpc-url "$UNICHAIN_RPC_URL" \
  --broadcast \
  --skip-simulation \
  --slow \
  --non-interactive \
  -vvvv

chain_id="$(cast chain-id --rpc-url "$UNICHAIN_RPC_URL")"
RUN_JSON="broadcast/20_DemoLifecycle.s.sol/${chain_id}/run-latest.json"
if [[ ! -f "$RUN_JSON" ]]; then
  RUN_JSON="$(find broadcast/20_DemoLifecycle.s.sol -name 'run-latest.json' | head -n 1 || true)"
fi
if [[ -n "$RUN_JSON" && -f "$RUN_JSON" ]]; then
  echo ""
  echo "=== Unichain Demo Tx Trace (phase proof) ==="
  jq -r '.transactions[]? | [.transactionType, (.contractName // "N/A"), (.contractAddress // "N/A"), (.hash // .transactionHash // "N/A")] | @tsv' "$RUN_JSON" \
    | while IFS=$'\t' read -r tx_type contract_name contract_addr hash; do
      printf "%-7s %-20s %s\n" "$tx_type" "$contract_name" "$hash"
      printf "        address: %s\n" "${contract_addr:-N/A}"
      printf "        url: %s%s\n" "$UNICHAIN_EXPLORER_TX_BASE" "$hash"
    done

  echo ""
  echo "Demo artifact: $RUN_JSON"
fi
