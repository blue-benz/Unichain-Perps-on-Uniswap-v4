# API

## PerpsEngine
- `createMarket(PoolKey, initialPrice, fundingInterval, fundingVelocity, maxOpenNotional)`
- `captureMarkPriceFromHook(PoolKey, sqrtPriceX96, tick)`
- `depositCollateral(amount)` / `withdrawCollateral(amount)`
- `addMargin(marketId, amount)` / `removeMargin(marketId, amount)`
- `openPosition(marketId, isLong, notional, margin)`
- `modifyPosition(marketId, sizeDelta)`
- `closePosition(marketId, reduceNotional)`
- `liquidatePosition(trader, marketId, liquidator)`

## RiskManager
- `setRiskParams(marketId, RiskParams)`
- `validateInitialMargin(...)`
- `validateMaintenanceMargin(...)`

## CollateralVault
- `depositFor`, `withdrawTo`, `lockCollateral`, `unlockCollateral`
- insurance accounting helpers for engine settlement

## PerpsHook
- `beforeSwap`, `afterSwap`
- `setGuardrails(maxAbsAmountSpecified, paused)`
