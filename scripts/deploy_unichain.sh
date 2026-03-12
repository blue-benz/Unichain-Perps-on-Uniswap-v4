#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source ./.env 2>/dev/null || true

UNICHAIN_RPC_URL="${UNICHAIN_RPC_URL:-${SEPOLIA_RPC_URL:-}}"
PRIVATE_KEY="${PRIVATE_KEY:-${SEPOLIA_PRIVATE_KEY:-}}"
UNICHAIN_EXPLORER_TX_BASE="${UNICHAIN_EXPLORER_TX_BASE:-https://sepolia.uniscan.xyz/tx/}"

: "${UNICHAIN_RPC_URL:?UNICHAIN_RPC_URL (or SEPOLIA_RPC_URL) is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY (or SEPOLIA_PRIVATE_KEY) is required}"

upsert_env_var() {
  local key="$1"
  local value="$2"
  if [[ ! -f .env ]]; then
    touch .env
  fi
  if grep -q "^${key}=" .env; then
    sed -i.bak "s#^${key}=.*#${key}=${value}#g" .env
    rm -f .env.bak
  else
    echo "${key}=${value}" >> .env
  fi
}

extract_contract_address() {
  local run_json="$1"
  local contract_name="$2"
  jq -r --arg name "$contract_name" \
    '.transactions[] | select(.contractName == $name and (.transactionType == "CREATE" or .transactionType == "CREATE2")) | .contractAddress' \
    "$run_json" | tail -n 1
}

extract_contract_tx() {
  local run_json="$1"
  local contract_name="$2"
  jq -r --arg name "$contract_name" \
    '.transactions[] | select(.contractName == $name and (.transactionType == "CREATE" or .transactionType == "CREATE2")) | .hash' \
    "$run_json" | tail -n 1
}

forge script script/10_DeployPerps.s.sol:DeployPerpsScript \
  --rpc-url "$UNICHAIN_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --skip-simulation \
  --slow \
  --non-interactive \
  -vvvv

BROADCAST_DIR="broadcast/10_DeployPerps.s.sol"
chain_id="$(cast chain-id --rpc-url "$UNICHAIN_RPC_URL")"
LATEST_RUN="${BROADCAST_DIR}/${chain_id}/run-latest.json"
if [[ ! -f "$LATEST_RUN" ]]; then
  LATEST_RUN="$(find "$BROADCAST_DIR" -name 'run-latest.json' | head -n 1 || true)"
fi
if [[ -z "$LATEST_RUN" || ! -f "$LATEST_RUN" ]]; then
  echo "Could not find broadcast output in $BROADCAST_DIR"
  exit 1
fi

engine_address="$(extract_contract_address "$LATEST_RUN" "PerpsEngine")"
hook_address="$(extract_contract_address "$LATEST_RUN" "PerpsHook")"
vault_address="$(extract_contract_address "$LATEST_RUN" "CollateralVault")"
risk_address="$(extract_contract_address "$LATEST_RUN" "RiskManager")"
liq_address="$(extract_contract_address "$LATEST_RUN" "LiquidationModule")"

engine_tx="$(extract_contract_tx "$LATEST_RUN" "PerpsEngine")"
hook_tx="$(extract_contract_tx "$LATEST_RUN" "PerpsHook")"
vault_tx="$(extract_contract_tx "$LATEST_RUN" "CollateralVault")"
risk_tx="$(extract_contract_tx "$LATEST_RUN" "RiskManager")"
liq_tx="$(extract_contract_tx "$LATEST_RUN" "LiquidationModule")"

market_created_sig="$(cast keccak "MarketCreated(bytes32,bytes32,uint256)")"
market_id="$(jq -r --arg sig "$market_created_sig" '.receipts[]?.logs[]? | select(.topics[0] == $sig) | .topics[1]' "$LATEST_RUN" | tail -n 1)"

currency0="${POOL_CURRENCY0:-}"
currency1="${POOL_CURRENCY1:-}"
if [[ -z "$currency0" || -z "$currency1" ]]; then
  mock_tokens_raw="$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "MockERC20") | .contractAddress' "$LATEST_RUN")"
  mock_token_count="$(echo "$mock_tokens_raw" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$mock_token_count" -ge 3 ]]; then
    collateral_token="$(echo "$mock_tokens_raw" | sed -n '1p')"
    token_a="$(echo "$mock_tokens_raw" | sed -n '2p')"
    token_b="$(echo "$mock_tokens_raw" | sed -n '3p')"
    token_a_lc="$(echo "$token_a" | tr '[:upper:]' '[:lower:]')"
    token_b_lc="$(echo "$token_b" | tr '[:upper:]' '[:lower:]')"
    if [[ "$token_a_lc" < "$token_b_lc" ]]; then
      currency0="$token_a"
      currency1="$token_b"
    else
      currency0="$token_b"
      currency1="$token_a"
    fi
    upsert_env_var "COLLATERAL_TOKEN" "$collateral_token"
  fi
fi

upsert_env_var "UNICHAIN_RPC_URL" "$UNICHAIN_RPC_URL"
upsert_env_var "PRIVATE_KEY" "$PRIVATE_KEY"
upsert_env_var "COLLATERAL_VAULT_ADDRESS" "$vault_address"
upsert_env_var "RISK_MANAGER_ADDRESS" "$risk_address"
upsert_env_var "PERPS_ENGINE_ADDRESS" "$engine_address"
upsert_env_var "PERPS_HOOK_ADDRESS" "$hook_address"
upsert_env_var "LIQUIDATION_MODULE_ADDRESS" "$liq_address"
if [[ -n "$market_id" ]]; then
  upsert_env_var "MARKET_ID" "$market_id"
fi
if [[ -n "$currency0" && -n "$currency1" ]]; then
  upsert_env_var "POOL_CURRENCY0" "$currency0"
  upsert_env_var "POOL_CURRENCY1" "$currency1"
fi

echo ""
echo "=== Unichain deployment complete ==="
echo "RiskManager          $risk_address"
echo "CollateralVault      $vault_address"
echo "PerpsEngine          $engine_address"
echo "PerpsHook            $hook_address"
echo "LiquidationModule    $liq_address"
echo "MarketId             ${market_id:-TBD}"
echo ""
echo "Deployment tx URLs:"
for tx in "$risk_tx" "$vault_tx" "$engine_tx" "$hook_tx" "$liq_tx"; do
  if [[ -n "$tx" && "$tx" != "null" ]]; then
    echo "$tx -> ${UNICHAIN_EXPLORER_TX_BASE}${tx}"
  fi
done

echo ""
echo "Stored in .env:"
echo "  COLLATERAL_VAULT_ADDRESS"
echo "  RISK_MANAGER_ADDRESS"
echo "  PERPS_ENGINE_ADDRESS"
echo "  PERPS_HOOK_ADDRESS"
echo "  LIQUIDATION_MODULE_ADDRESS"
echo "  MARKET_ID"
echo "  POOL_CURRENCY0"
echo "  POOL_CURRENCY1"
