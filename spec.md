# Unichain Perps on Uniswap v4 - Technical Spec

## 1. Objective
Build a Uniswap-v4-native perpetual futures primitive on Unichain, focused on deterministic on-chain hedging and LP shorting workflows.

## 2. System Model
- Margin mode: **isolated margin** (single position per trader per market).
- Market key: `marketId = PoolId.unwrap(poolKey.toId())`.
- Collateral: single ERC20 per deployment (`CollateralVault`).

## 3. Component Responsibilities
- `PerpsHook`
  - Implements `beforeSwap` and `afterSwap`.
  - Enforces pool-manager-only call path through `BaseHook`.
  - Applies pre-swap guardrail (`maxAbsAmountSpecified`).
  - Captures mark price from `slot0` and forwards to engine.
- `PerpsEngine`
  - Market config and position storage.
  - Funding window updates.
  - Margin operations and position lifecycle.
  - Liquidation settlement and bad-debt tracking.
- `RiskManager`
  - Per-market IMR/MMR/leverage/liquidation parameters.
  - Deterministic validation for open/maintenance checks.
- `CollateralVault`
  - Free/locked collateral balances.
  - Insurance ledger.
- `LiquidationModule`
  - Public liquidation entrypoint for keepers.

## 4. Pricing
### 4.1 Mark price
Derived from pool state after swaps:

`markPriceX18 = (sqrtPriceX96^2 * 1e18) / 2^192`

### 4.2 Index proxy
On-chain configurable `indexPriceX18` per market.
Default mode is oracle-free deterministic proxy.

## 5. Funding
Given:
- `premiumX18 = (mark - index) / index`
- `premium` clamped by `maxPremiumBps`
- `ratePerWindowX18 = premiumX18 * fundingVelocityX18`
- `windows = floor((now - lastFundingTs) / fundingInterval)`

Then:
- `cumulativeFundingRateX18 += ratePerWindowX18 * windows`

Position settlement:
- `fundingPayment = sizeUsdX18 * (cumFunding - lastCumFunding)`
- Positive payment => trader pays.
- Negative payment => trader receives from insurance.

## 6. Margin & Liquidation
- `notional = abs(sizeUsdX18)`
- `IMR = notional * initialMarginBps / 10_000`
- `MMR = notional * maintenanceMarginBps / 10_000`
- `PnL = sizeUsdX18 * (mark - entry) / entry`
- `equity = collateral + unrealizedPnL` (post-funding settlement)

Liquidation condition:
- `equity < MMR`

Liquidation settlement:
- Locked collateral is transferred into insurance bucket.
- Positive residual equity split:
  - liquidation penalty retained in insurance
  - liquidator incentive payout
  - trader refund
- Negative residual equity increments `badDebtUsdX18`.

## 7. Example (units: USD x 1e18)
Long: notional 1,000; collateral 100; entry 1.00
- IMR @ 10% = 100
- MMR @ 5% = 50

If mark = 0.94:
- PnL = -60
- equity = 40
- liquidation allowed because 40 < 50

## 8. MEV & Manipulation Notes
- Price comes from pool state, so thin-liquidity pools are manipulable.
- Guardrails limit extreme single-call swap size in hook path.
- Funding updates are windowed to reduce per-transaction trigger gaming.
- Residual manipulation risk remains and is documented as non-zero.

## 9. Assumptions
- `/context/unichain` was not present in this workspace; chain-specific explorer/rpc defaults are env-driven.
- `v4-periphery` is pinned by bootstrap script to commit `3779387e5d296f39df543d23524b050f89a62917`.
