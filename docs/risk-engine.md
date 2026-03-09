# Risk Engine

`RiskManager` provides per-market risk parameters:
- `initialMarginBps`
- `maintenanceMarginBps`
- `maxLeverageBps`
- `liquidationPenaltyBps`
- `liquidationIncentiveBps`
- `maxPremiumBps` (funding premium clamp)

Validation paths:
- Open/increase: IMR + leverage checks.
- Margin removal and post-modification: MMR check.
- Liquidation: unhealthy if equity below MMR.

All checks are deterministic and purely on-chain.
