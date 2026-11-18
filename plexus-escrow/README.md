# PLEXUS escrow (PlexusEscrowV2)

BSC USDT escrow contract, its tests, deployment scripts and audit.

| Command | What it does |
|---|---|
| `npm test` | 80 unit tests |
| `npm run test:invariant` | randomised accounting test |
| `npm run coverage`, `npm run analyze` | coverage, Slither |
| `npm run deploy:local`, `npm run verify:local` | deploy to a local node, check the 39 business rules |
| `npm run deploy:testnet`, `npm run verify:testnet` | deploy to BSC testnet, verify the source |
| `npm run smoke:testnet`, `npm run fulltest:testnet` | on-chain tests |
| `npm run export:app` | regenerate the app's ABI, deployment and golden test files |

The audit is in `audit/contract-audit.md`. The app's wallet module is in `../lib/blockchain/v2/`.
