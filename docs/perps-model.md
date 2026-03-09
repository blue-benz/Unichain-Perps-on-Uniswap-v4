# Perps Model

## Pricing
- Mark price: derived from v4 `sqrtPriceX96` after swap.
- Conversion: `priceX18 = (sqrtPriceX96^2 * 1e18) / 2^192`.
- Index proxy: on-chain configurable value per market (`setIndexPrice`), default initialized to mark.

## Funding
Let:
- `premium = (mark - index) / index`
- `ratePerWindow = premium * fundingVelocity`
- `windows = floor((now - lastFundingTs) / fundingInterval)`

Then:
- `cumulativeFundingRate += ratePerWindow * windows`
- Position funding payment: `sizeUsd * (cumFunding - lastCumFunding)`

Sign convention:
- Positive payment: trader pays (collateral decreases).
- Negative payment: trader receives (paid from insurance).

## Margin
- Notional: `abs(sizeUsd)`
- IMR required: `notional * IMR_bps / 10_000`
- MMR required: `notional * MMR_bps / 10_000`

## PnL
- `PnL = sizeUsd * (mark - entry) / entry`
- Positive for profitable long/short depending move direction.

## Liquidation
- Trigger when `equity < maintenance requirement`
- `equity = collateral + unrealizedPnL` (after funding settlement)
- Liquidation haircut:
  - penalty retained in insurance
  - incentive paid to liquidator
  - remaining positive equity returned to trader
- Negative equity increments `market.badDebtUsdX18`
