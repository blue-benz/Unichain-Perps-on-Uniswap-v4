# Deployment

## Prerequisites
- Foundry installed.
- `.env` populated (see `.env.example`).
- Submodules initialized with pinned dependencies.

## Bootstrap
```bash
make bootstrap
```

## Local (Anvil)
```bash
anvil
make demo-local
```

## Unichain deploy
```bash
source .env
make deploy-unichain
```

Required env:
- `UNICHAIN_RPC_URL`
- `PRIVATE_KEY`

Optional env:
- `UNICHAIN_EXPLORER_TX_BASE`
- `COLLATERAL_TOKEN`, `CURRENCY_A`, `CURRENCY_B`

## Address registry
Populate deployed addresses in README after broadcast completes.
