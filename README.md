# Guarded Lending

A Scaffold-HBAR template for a lending market that prices through several independent oracles and **stops instead of trusting a forged price**.

```bash
npm create scaffold-hbar@latest -- --template yeziR4/guarded-lending
```

Lenders supply USDC and receive gUSDC. Borrowers lock HBAR and borrow USDC. Every price-dependent action goes through `OracleGuard`: the median of Chainlink, Supra and Pyth, accepted only when a quorum agrees.

## Why

In July 2026 Bonzo Lend lost about $9M. Its contracts worked as designed. They trusted one oracle, and that oracle's verifier accepted a forged price about 10¹² too high ([incident report](https://bonzo.finance/blog/bonzo-lend-incident-report-oracle-provider-exploit)). `test/BonzoReplay.t.sol` replays the attack against this market twice. Wired to a single feed, the pool is drained. Through the guard, the attack reverts. How the guard decides: [docs/oracle-guard.md](docs/oracle-guard.md).

## What each piece uses, and why

| Piece | Uses | Why it needs it |
| --- | --- | --- |
| `OracleGuard` + 3 sources | **Chainlink, Supra, Pyth** | One compromised provider cannot move the price; disagreement halts borrowing |
| `LendingMarket` | **HTS** | Creates and mints gUSDC, so a deposit is a native token that shows in any wallet and on HashScan |
| `Guardian` | **HSS** (HIP-1215) | Re-runs the oracle check and accrues interest on a schedule it books itself, with no off-chain keeper |
| `hcsRelay.js` | **HCS** | An ordered, timestamped record of every oracle decision, for post-mortems |
| Dashboard | Mirror node | Live sources, breaker state, lend/borrow/liquidate, audit log |

## Run it

The template ships wired to a live testnet deployment, so this works before you deploy anything:

```bash
cd <your-app>
npm run next:dev
```

Open http://localhost:3000. Chainlink and Supra show **Ok**, Pyth shows **Stale** (see [Pyth](#pyth)), and the guard shows "2 of 3 agree". To use the market, connect a testnet wallet and get HBAR from the [portal faucet](https://portal.hedera.com/faucet) and USDC from the [Circle faucet](https://faucet.circle.com). The UI asks you to **associate** each token first, which Hedera requires before an account can hold it.

**Prerequisites:**
- Node ≥ 20.18.3
- git with `user.name` and `user.email` set
- `make`
- [Foundry](https://book.getfoundry.sh/getting-started/installation) **below 1.8** (`foundryup --install v1.5.1`). Foundry 1.8 breaks deploys against Hedera's RPC; see [why](docs/hedera-notes.md#pin-foundry-below-18).

## Deploy your own

```bash
npm run foundry:account:import   # stores your testnet ECDSA key (HEX, not DER) in Foundry's encrypted keystore

cd packages/foundry
forge script script/Deploy.s.sol --rpc-url hedera_testnet --account <name> --broadcast --slow --legacy
node scripts-js/generateTsAbis.js
npm run setup -- --network hedera_testnet --keystore <name>   # HTS token, first price, starts the Guardian
npm run relay -- --keystore <name>                             # optional: HCS audit log
```

`setup` exists because `forge script` simulates locally, where the HTS and HSS system contracts don't exist. It is safe to re-run. The relayer prints a topic id on its first run; set it as `NEXT_PUBLIC_AUDIT_TOPIC_ID` in `packages/nextjs/.env.local`.

**Costs (testnet):**
- Deploy: about 5 HBAR.
- Token creation: about $1; send 15 and the rest is refunded.
- Guardian: about 1.7 HBAR per tick, every 6 h by default.

The Guardian has no owner, so its funding can't be withdrawn. Fund it for as long as you want it to run.

## Configuration

`script/Deploy.s.sol`, overridable by environment variable:

| Variable | Default | |
| --- | --- | --- |
| `GUARD_QUORUM` | 2 | Sources that must agree (strict majority) |
| `GUARD_MAX_DEVIATION_BPS` | 500 | Max distance from the median to agree |
| `GUARD_MAX_CHANGE_BPS` | 2000 | Max move per check before the breaker trips |
| `GUARD_COOLDOWN` | 1800 | Healthy seconds before a tripped breaker resets |
| `GUARD_MAX_PRICE_AGE` | 7200 | Oldest price the market will use |
| `CHAINLINK_MAX_AGE` / `SUPRA_MAX_AGE` / `PYTH_MAX_AGE` | 2h / 2h / 10m | Per-source staleness |
| `GUARDIAN_INTERVAL` / `GUARDIAN_GAS_LIMIT` | 6h / 2M | Booking a tick costs ~1.4M gas, so keep the limit ≥ 1.6M |

Risk parameters (65% LTV, 80% liquidation threshold, 5% bonus) are in the same script.

### Pyth

Pyth only updates on-chain when someone pushes a signed update, and since August 2026 its API needs a key. Without `PYTH_API_KEY` (server-side, in `packages/nextjs/.env.local`), Pyth stays stale and the guard runs on Chainlink and Supra. With it, "Refresh Pyth" brings the third source in.

## Test

```bash
npm run foundry:test            # 46 offline tests, including the Bonzo replay; HTS and HSS are mocked
npm run foundry:test:testnet    # the real guard against live testnet feeds
bash scripts/check-gate.sh --local   # fresh scaffold, lint, test, build, boot
```

## Extend

- **Add a source:** implement `IPriceSource`, wire it in `Deploy.s.sol` with its max age, and add a slot in `hooks/lending/useOracleGuard.ts`.
- **Reuse the guard alone:** it has no dependency on the market. Call `poke()` then `price()`.

## Testnet deployment

| | |
| --- | --- |
| OracleGuard | [`0x3598…BbE3`](https://hashscan.io/testnet/contract/0x35987868E2677B7F778888B32c4db30Ad812BbE3) |
| LendingMarket | [`0x3cd2…03b5`](https://hashscan.io/testnet/contract/0x3cd26C4d74Ec3e96b190195Df2084C63901d03b5) |
| Guardian | [`0xda97…8B1`](https://hashscan.io/testnet/contract/0xda970AfF580EF5D0D917b94aa552921B8166B8B1) |
| gUSDC | [`0.0.10760610`](https://hashscan.io/testnet/token/0.0.10760610) |
| Audit topic | [`0.0.10772847`](https://hashscan.io/testnet/topic/0.0.10772847) |
| First oracle check | [`0x3d6d…d19a`](https://hashscan.io/testnet/tx/0x3d6df3cfde1e2f726d939996dfb3774d1499d9dad50db37bf7e1deaaab61d19a) |

Hedera behaviour that differs from other EVM chains, and how this template handles it: [docs/hedera-notes.md](docs/hedera-notes.md). Not audited.

MIT
