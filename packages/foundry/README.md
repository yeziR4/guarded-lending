# Foundry package

Contracts, tests, deploy scripts and Node helpers for the guarded lending market. Product overview: [../../README.md](../../README.md).

## Contracts

| Contract | Role |
| --- | --- |
| `oracle/OracleGuard.sol` | Median of sources, quorum, bounds, change limit, self-resetting breaker |
| `oracle/sources/ChainlinkSource.sol` | Chainlink push feed (`latestRoundData`) |
| `oracle/sources/SupraSource.sol` | Supra push oracle (`getSvalue`, millisecond timestamps) |
| `oracle/sources/PythSource.sol` | Pyth pull oracle (`getPriceUnsafe`, confidence check) |
| `LendingMarket.sol` | USDC lending against HBAR; gUSDC receipt token via HTS |
| `Guardian.sol` | Keeperless timer via HIP-1215 scheduled calls |

## Tests

```bash
forge test                                                   # offline: 46 unit/fuzz tests, HTS + HSS mocked
forge test --match-contract BonzoReplay -vv                  # the exploit replay
forge test --match-path "test/fork/*" \
  --fork-url https://testnet.hashio.io/api --chain-id 296 -vv  # real guard vs live testnet feeds
```

`test/mocks/MockHts.sol` stands in for the HTS system contract at `0x167`, and `MockScheduleService.sol` for HSS at `0x16b`. They are etched with `vm.etch`. Both enforce the Hedera rules the contracts depend on; the live network behaviour is covered by the testnet deployment.

## Scripts

| Script | Purpose |
| --- | --- |
| `script/Deploy.s.sol` | Deploys sources, guard, market, Guardian. Parameters via env vars (see root README) |
| `script/DeployGuardian.s.sol` | Deploys a new Guardian for the recorded guard and market |
| `scripts-js/setupMarket.js` | `npm run setup`: HTS token creation, first `poke()`, `Guardian.start()` |
| `scripts-js/hcsRelay.js` | `npm run relay`: publishes guard events to an HCS topic |
| `scripts-js/generateTsAbis.js` | Writes `packages/nextjs/contracts/deployedContracts.ts` from broadcasts |

Each deploy run merges its contracts into `deployments/<chainId>.json`, which `setup` and `relay` read to find addresses.

## Accounts

Keys live in Foundry's encrypted keystore (`~/.foundry/keystores`), never in `.env`:

```bash
npm run account:import     # or: cast wallet import <name> --interactive
npm run account            # list keystores and balances
```
