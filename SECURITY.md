# Security Policy

## Reporting
Send vulnerability reports privately to project maintainers. Do not open public issues for exploitable bugs.

Include:
- impact and exploit path
- affected contract + function
- reproducible PoC (Foundry preferred)
- mitigation recommendation

## Scope
Primary security-critical modules:
- `PerpsEngine`
- `PerpsHook`
- `RiskManager`
- `LiquidationModule`
- `CollateralVault`

## Known risk classes
- pool-state mark manipulation in thin liquidity
- funding trigger timing behavior
- liquidation griefing
- precision and dust rounding edge cases

## Disclosure process
1. Acknowledge report.
2. Reproduce and severity-rank.
3. Patch + regression tests.
4. Coordinate disclosure timeline.
