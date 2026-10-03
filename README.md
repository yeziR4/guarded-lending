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
| Dashboard | Mirror node | Live sources, breaker state, lend/borrow/liquidate |

## Run it

The template ships wired to a live testnet deployment, so this works before you deploy anything:

```bash
cd <your-app>
npm run next:dev
```

Open http://localhost:3000. Chainlink and Supra show **Ok**, Pyth shows **Stale** (see [Pyth](#pyth)), and the guard shows "2 of 3 agree". To use the market, connect a testnet wallet and get HBAR from the [portal faucet](https://portal.hedera.com/faucet), then press **Get 1,000 tUSD** in the Lend card. The UI asks you to **associate** each token first, which Hedera requires before an account can hold it.

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
```

`setup` exists because `forge script` simulates locally, where the HTS and HSS system contracts don't exist. It is safe to re-run.

**Costs (testnet):**
- Deploy: about 5 HBAR.
- Token creation: send 30 HBAR; the unused part is refunded.
- Guardian: about 1.7 HBAR per tick, every 12 h by default.

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
| `CHAINLINK_MAX_AGE` / `SUPRA_MAX_AGE` / `PYTH_MAX_AGE` | 25h / 3h / 10m | Per-source staleness: the feed's heartbeat plus a margin |
| `GUARDIAN_INTERVAL` / `GUARDIAN_GAS_LIMIT` | 12h / 2M | Booking a tick costs ~1.4M gas, so keep the limit ≥ 1.6M |

Risk parameters (65% LTV, 80% liquidation threshold, 5% bonus) are in the same script.

### Pyth

Pyth only updates on-chain when someone pushes a signed update, and since August 2026 its API needs a key. Without `PYTH_API_KEY` (server-side, in `packages/nextjs/.env.local`), Pyth stays stale and the guard runs on Chainlink and Supra. With it, "Refresh Pyth" brings the third source in.

## Test

```bash
npm run foundry:test            # 49 offline tests, including the Bonzo replay; HTS and HSS are mocked
npm run foundry:test:testnet    # the real guard against live testnet feeds
bash scripts/check-gate.sh --local   # fresh scaffold, lint, test, build, boot
```

## Extend

- **Add a source:** implement `IPriceSource`, wire it in `Deploy.s.sol` with its max age, and add a slot in `hooks/lending/useOracleGuard.ts`.
- **Reuse the guard alone:** it has no dependency on the market. Call `poke()` then `price()`.

## Testnet deployment

The shared deployment lends **tUSD**, a test stablecoin with a built-in faucet (`TestStablecoin.sol`), so anyone can try the full flow. Deploy your own against Circle USDC by leaving `LENDING_ASSET` unset.

| | |
| --- | --- |
| OracleGuard | [`0x56D8…78e0`](https://hashscan.io/testnet/contract/0x56D851518AC4eef57e97Ba5686cE5519fE5a78e0) |
| LendingMarket | [`0x861f…61a3`](https://hashscan.io/testnet/contract/0x861f5528f44210a121937657Fddde90e725161a3) |
| Guardian | [`0x7911…516E`](https://hashscan.io/testnet/contract/0x7911cE302a11ab2babFeED757C724C14Aa6E516E) |
| tUSD faucet | [`0x5007…8074`](https://hashscan.io/testnet/contract/0x5007b82a0E3ea33933822705D609153B10618074) |
| tUSD / gtUSD | [`0.0.10792808`](https://hashscan.io/testnet/token/0.0.10792808) / [`0.0.10838545`](https://hashscan.io/testnet/token/0.0.10838545) |
| First oracle check | [`0x26ef…2337`](https://hashscan.io/testnet/tx/0x26efc4326cbb505e2b7b1349e4e09b6539490006825b9c518877bd7799142337) |

Hedera behaviour that differs from other EVM chains, and how this template handles it: [docs/hedera-notes.md](docs/hedera-notes.md). Not audited.

MIT
