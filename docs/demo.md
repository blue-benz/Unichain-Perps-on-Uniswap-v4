# Demo Guide

## Judge flow
1. Deploy contracts and create market.
2. Seed collateral and insurance.
3. Open long + short.
4. Execute swap to update mark through hook.
5. Apply funding (window update).
6. Trigger liquidation scenario.
7. Observe PnL settlement and bad-debt accounting.

## Commands
```bash
make demo-local
make demo-unichain
make demo-hedge
```

`demo-hedge` runs the integration scenario and highlights LP hedge narrative metrics.
