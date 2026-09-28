# How the oracle guard decides

`OracleGuard` turns several independent price providers into one price a lending market can trust, and refuses to produce a price when it cannot.

## The checks, in order

Every `poke()` reads all sources (`inspect()` does the same without writing state) and classifies each reading:

| # | Check | Outcome for that source | Why |
| --- | --- | --- | --- |
| 1 | The source reverts (non-positive answer, incomplete round, Pyth confidence too wide) | `Reverted` | Provider-level sanity lives in each adapter, so provider quirks never leak into the guard |
| 2 | Older than the source's own max age | `Stale` | Providers update on different cadences: Chainlink testnet every few minutes, Supra about hourly, Pyth only when pushed |
| 3 | Outside `[minPrice, maxPrice]` | `OutOfBounds` | A 10¹² forgery is rejected here, before any statistics |
| 4 | More than `maxDeviationBps` from the median of the survivors | `Outlier` | One provider disagreeing with the rest is ignored, not averaged in |

Then the guard decides:

| Condition | Result |
| --- | --- |
| Fewer than `quorum` sources agree | **Trip**: `NoQuorum` |
| The median moved more than `maxChangeBps` since the last accepted price | **Trip**: `ExcessiveChange` |
| Otherwise | **Accept** the median as `lastPrice` |

While tripped, `price()` reverts with `BreakerTripped(reason)`. Every consumer fails closed by default, because using the price means calling `price()`.

### Recovery

A tripped breaker resets itself when the sources have reached quorum on every check for a full `cooldown`. Any unhealthy check during the cooldown restarts it. On reset, the guard **re-anchors** on the new median: after a genuine 30% crash, the breaker trips on `ExcessiveChange`, waits out the cooldown while all providers agree on the new level, then accepts it. Without re-anchoring, the change limit would compare every future price to the pre-crash anchor and the market would stay frozen forever.

There is no owner, no pause key and no manual override. Sources and parameters are fixed at deployment. To change them, deploy a new guard and a new market.

## Why these defaults

| Parameter | Default | Reasoning |
| --- | --- | --- |
| Quorum | 2 of 3 | A strict majority. The constructor rejects any quorum that would let two disjoint groups both qualify |
| Max deviation | 5% | On testnet, Chainlink (USD) and Supra (USDT) routinely sit 1–3% apart. 5% leaves room for that basis without letting a meaningful forgery through |
| Max change per check | 20% | HBAR has moved more than 20% in a day, but rarely between two checks an hour apart. A bigger move trips, waits and re-anchors |
| Cooldown | 30 min | Long enough for a transient oracle fault to show itself, short enough not to strand borrowers |
| Bounds | $0.001 to $100 | Orders of magnitude around any plausible HBAR price. They exist to stop absurd values, not to express a view |
| Max price age (market) | 2 h | The Guardian refreshes hourly; the market also refreshes on every priced action |

## The Bonzo Lend incident, replayed

**What happened (11 July 2026).** The attacker deposited about 250 SAUCE (a few dollars), then submitted a Supra price update whose BLS signature was all zeros. Supra's verifier ran the pairing check on zero inputs, which trivially passes, and accepted a SAUCE price roughly 10¹² too high. Bonzo, which used Supra as its single source, valued the collateral accordingly, and the attacker borrowed about 6.6M USDC and 34.5M WHBAR. Bonzo paused lending about 50 minutes later. Sources: [Bonzo incident report](https://bonzo.finance/blog/bonzo-lend-incident-report-oracle-provider-exploit), [CryptoSlate analysis](https://cryptoslate.com/how-a-zeroed-oracle-signature-unlocked-9m-from-hedera-defi-lender-bonzo-lend/).

**The replay** (`packages/foundry/test/BonzoReplay.t.sol`) runs the **same `LendingMarket` code** against the same forged Supra update, changing only how the oracle is wired:

| Test | Oracle wiring | Result |
| --- | --- | --- |
| `test_singleFeedMarket_isDrainedByOneForgedPrice` | Supra only, quorum 1, no meaningful bounds (Bonzo's shape) | Attacker borrows the entire 100,000 USDC pool against ~$30 of HBAR |
| `test_guardedMarket_ignoresForgedFeedAndKeepsPricingHonestly` | 3 sources, 2-of-3 guard | Supra is `OutOfBounds`, the price stays at the honest median, and the borrow reverts `Undercollateralized` |
| `test_guardedMarket_rejectsPlausibleForgeryAsOutlier` | Same, but the forgery is only 10× (inside the bounds) | Supra is an `Outlier`; same result |
| `test_guardedMarket_failsClosedWhenMajorityCompromised` | Two of three sources forged, to different values | No quorum, so the breaker trips and borrowing halts instead of paying out |

`testFuzz_singleCompromisedSourceCannotMovePrice` in `OracleGuard.t.sol` generalizes the first property: for any forged value from any single source, the accepted price does not change.

```bash
cd packages/foundry
forge test --match-contract BonzoReplay -vv
```

## What the guard does not do

- **It does not fix the provider.** The zero-signature bug lived in Supra's verifier. The guard makes a single broken provider harmless; it does not make it correct.
- **It cannot out-vote a colluding majority.** If two of three providers report the same forged price, the median is forged. The change limit still caps how far one check can move the price (20%), and a tripped breaker needs a full cooldown of agreement to reset.
- **It is not a TWAP.** Every accepted price is a spot median. Markets for thinly traded collateral should add a time-weighted source.
