# Security

## Primary controls
- `onlyPoolManager` on hook entrypoints via `BaseHook`.
- Hook capture path authorized through `PerpsEngine.hook`.
- Reentrancy protection on user-mutative endpoints.
- Vault isolated from strategy logic.
- Bounded funding premium via `maxPremiumBps`.

## Threats considered
- Mark-price manipulation through low-liquidity swaps.
- Funding gaming at window boundaries.
- Liquidation griefing.
- Unauthorized hook spoofing.
- Rounding/dust edge cases.

## Mitigations
- Hook-side max swap amount guardrail.
- Funding updates in discrete windows.
- Maintenance checks after margin/position changes.
- Dedicated liquidation module path.
- Fuzz tests for undercollateralized opens and liquidation non-bypass.

## Residual risk
- Mark price remains pool-dependent and can be influenced by transient order flow in thin markets.
- Insurance depletion can limit positive funding payouts.
- Oracle-free index mode trades external accuracy for deterministic behavior.
