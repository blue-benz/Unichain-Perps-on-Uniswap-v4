# Deployments

Canonical deployment registry for Unichain Perps on Uniswap v4.

## Unichain Sepolia
- Chain ID: `1301`
- RPC: `https://unichain-sepolia.g.alchemy.com/v2/...`
- Explorer base: `https://sepolia.uniscan.xyz/tx/`
- Deploy artifact: `broadcast/10_DeployPerps.s.sol/1301/run-latest.json`
- Deploy timestamp (UTC): `2026-03-10 10:41:07`

### Core protocol contracts
| Component | Address | Deployment TxID | Tx URL |
| --- | --- | --- | --- |
| RiskManager | `0x1c47706ad9527ea45feb940e0c1f14d54f103abc` | `0x86a9ea9c1f42255af5cb33910588a6802c9ad5dbaa74edbadc37f8055ea397e2` | `https://sepolia.uniscan.xyz/tx/0x86a9ea9c1f42255af5cb33910588a6802c9ad5dbaa74edbadc37f8055ea397e2` |
| CollateralVault | `0xee661645166fbd92e712ecbcf786b9c1707997ef` | `0xfd1abdae5df2bd6a949a56e9c6cb1096413d702737848e2962aec188db85ce7a` | `https://sepolia.uniscan.xyz/tx/0xfd1abdae5df2bd6a949a56e9c6cb1096413d702737848e2962aec188db85ce7a` |
| PerpsEngine | `0xac25bd28d5171821ecc9030933778d2ce242fa8a` | `0x6e4de46b4e88e22144c4ddfe65f014845e847b2b8e35698ddd2bef198db5ef66` | `https://sepolia.uniscan.xyz/tx/0x6e4de46b4e88e22144c4ddfe65f014845e847b2b8e35698ddd2bef198db5ef66` |
| PerpsHook (CREATE2) | `0x1ffcdc8fddfdf5b171ed90af03b498e0c1c6c0c0` | `0x2dc281409bbeb26c78c42c0ef6d9ff4abfa904167fd257b12eed8da419b47ca3` | `https://sepolia.uniscan.xyz/tx/0x2dc281409bbeb26c78c42c0ef6d9ff4abfa904167fd257b12eed8da419b47ca3` |
| LiquidationModule | `0x0d428e4ee3da759831bdbf0e75aecf91dda24764` | `0xf6f0437afdbfb5e26fe1fcd58a67400d8a169f2962c0892e36244f6f8902d24c` | `https://sepolia.uniscan.xyz/tx/0xf6f0437afdbfb5e26fe1fcd58a67400d8a169f2962c0892e36244f6f8902d24c` |

### Market and token addresses
| Component | Address | TxID | Tx URL |
| --- | --- | --- | --- |
| CollateralToken (MockERC20) | `0xe78663b6b31a67223f2a23e638142d5916484491` | `0x8588eeb9ae0a0a97c264ee696ef419b108a6667044637340be3640d8355cd0c7` | `https://sepolia.uniscan.xyz/tx/0x8588eeb9ae0a0a97c264ee696ef419b108a6667044637340be3640d8355cd0c7` |
| Pool Currency1 (MockERC20) | `0xcc84e73f16f0c52f49130ee39e379b4497fa6299` | `0x7ed7bb21e6a02624ead740ce42ad4e8889a78cbcbac5397bed822762809a68fe` | `https://sepolia.uniscan.xyz/tx/0x7ed7bb21e6a02624ead740ce42ad4e8889a78cbcbac5397bed822762809a68fe` |
| Pool Currency0 (MockERC20) | `0xbdeea35f47e305791080c74b2551a521c406b7a2` | `0xff93feb869c547278c749e9bac550f3ec7e3bc32d2e7c4823ff97ecd6fb1678d` | `https://sepolia.uniscan.xyz/tx/0xff93feb869c547278c749e9bac550f3ec7e3bc32d2e7c4823ff97ecd6fb1678d` |
| Market ID (`createMarket`) | `0x33972942cefbf97c03ea29e76ef387aa1a01c5cb18256d3e1b76081ba0211727` | `0x1362286948a128d02bf80db77c7edb4ebe43523c68a90d85c386e7cbb946e6c4` | `https://sepolia.uniscan.xyz/tx/0x1362286948a128d02bf80db77c7edb4ebe43523c68a90d85c386e7cbb946e6c4` |

## Latest Unichain Demo Run
- Script: `script/20_DemoLifecycle.s.sol:DemoLifecycleScript`
- Artifact: `broadcast/20_DemoLifecycle.s.sol/1301/run-latest.json`
- Run timestamp (UTC): `2026-03-10 13:44:40`
- Status: `19/19 successful tx receipts`

See the phase-by-phase tx ledger in [`README.md`](./README.md) under `Demo Run (Lifecycle Script + TxIDs)`.
