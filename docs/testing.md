# Testing

## Included
- Unit tests: margin/funding/pnl/liquidation behavior.
- Fuzz tests: collateral constraints, funding monotonicity, liquidation non-bypass.
- Integration tests: v4 pool + hook mark capture + long/short flow.

## Commands
```bash
make test
make fuzz
make integration
make coverage
```

Coverage is enforced in CI summary step.
