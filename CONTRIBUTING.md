# Contributing

## Setup
```bash
cp .env.example .env
make bootstrap
make test
npm install
npm run frontend:build
```

## Development rules
- Keep dependency versions pinned and lockfiles committed.
- Add tests for behavior changes (unit + fuzz where relevant).
- Keep hook logic minimal; move heavy logic to engine.
- Avoid introducing non-deterministic risk assumptions.

## PR checklist
- `forge build` passes
- `forge test -vv` passes
- `forge test --match-path test/fuzz/*` passes
- `forge coverage --report summary` runs
- docs updated if formulas/flows changed
