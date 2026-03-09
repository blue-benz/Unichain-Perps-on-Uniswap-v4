# Architecture

## Components
- `PerpsHook`: receives swap callbacks from `PoolManager`, enforces guardrails, forwards mark data.
- `PerpsEngine`: market/position state, funding accrual, margin operations, PnL accounting.
- `RiskManager`: configurable IMR/MMR/leverage/penalty parameters by market.
- `CollateralVault`: custody for free + locked collateral and insurance balance.
- `LiquidationModule`: external liquidation entrypoint for keeper flows.

## Lifecycle
1. Swap occurs on v4 pool.
2. `PerpsHook.afterSwap` reads `slot0` and pushes mark price to `PerpsEngine`.
3. Traders deposit collateral and open/modify positions in `PerpsEngine`.
4. Funding accrues per window from mark/index premium.
5. Unhealthy positions are liquidated via `LiquidationModule`.

## Design boundaries
- Hook is intentionally minimal.
- Risk logic is isolated in `RiskManager`.
- Token movements are isolated in `CollateralVault`.
