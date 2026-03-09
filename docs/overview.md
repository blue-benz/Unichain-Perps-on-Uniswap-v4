# Overview

Unichain Perps on Uniswap v4 is an isolated-margin perpetual futures protocol built around a Uniswap v4 hook.

Core idea:
- Use v4 pool state as deterministic mark-price input.
- Keep heavy derivatives logic outside the hook.
- Provide LP hedge flow: LP exposure can be partially offset by opening perp shorts.

Scope:
- Long/short positions with bounded leverage.
- Discrete funding windows.
- Deterministic risk checks and liquidation.
- Unichain deployment path plus local Anvil simulation.
