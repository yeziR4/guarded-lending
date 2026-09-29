# How the oracle guard decides

Each `poke()` reads every source and classifies it:

| Status | When |
| --- | --- |
| `Reverted` | The adapter rejected the data (non-positive price, incomplete round, Pyth confidence too wide) |
| `Stale` | Older than that source's max age |
| `OutOfBounds` | Outside `[minPrice, maxPrice]` |
| `Outlier` | Further than `maxDeviationBps` from the median of the remaining sources |
| `Ok` | Counts towards the quorum |

Then it decides:
- **Fewer than `quorum` sources agree:** trip, reason `NoQuorum`.
- **The median moved more than `maxChangeBps` since the last accepted price:** trip, reason `ExcessiveChange`.
- **Otherwise:** accept the median.

While tripped, `price()` reverts, so every consumer fails closed. The breaker resets itself after a full `cooldown` in which every check reaches quorum, and it re-anchors on the new median, so a genuine crash stops the market briefly instead of freezing it for good. There is no admin override.

## Defaults

| Parameter | Default | Reason |
| --- | --- | --- |
| Quorum | 2 of 3 | A strict majority, enforced by the constructor |
| Max deviation | 5% | Chainlink (USD) and Supra (USDT) routinely sit 1–3% apart on testnet |
| Max change per check | 20% | A bigger move trips, waits out the cooldown and re-anchors |
| Cooldown | 30 min | Long enough for a transient fault to show, short enough not to strand borrowers |
| Bounds | $0.001 to $100 | Only there to stop absurd values |

## The Bonzo Lend replay

On 11 July 2026 an attacker submitted a Supra price update with an all-zero signature. Supra's verifier accepted it, and Bonzo, which used Supra alone, valued about 250 SAUCE of collateral some 10¹² times too high. About $9M was borrowed out ([incident report](https://bonzo.finance/blog/bonzo-lend-incident-report-oracle-provider-exploit)).

`packages/foundry/test/BonzoReplay.t.sol` runs the same `LendingMarket` against a forged Supra price and changes only the oracle wiring:

| Test | Wiring | Result |
| --- | --- | --- |
| `singleFeedMarket_isDrainedByOneForgedPrice` | Supra only | The attacker borrows the whole 100k USDC pool against ~$30 of HBAR |
| `guardedMarket_ignoresForgedFeedAndKeepsPricingHonestly` | Guard, 2 of 3 | Supra is `OutOfBounds`, the borrow reverts `Undercollateralized` |
| `guardedMarket_rejectsPlausibleForgeryAsOutlier` | Guard, forgery only 10× | Supra is an `Outlier`, same result |
| `guardedMarket_failsClosedWhenMajorityCompromised` | Two sources forged | No quorum: the breaker trips and borrowing halts |

```bash
cd packages/foundry && forge test --match-contract BonzoReplay -vv
```

## Limits

- The guard makes one broken provider harmless. It does not fix the provider.
- If a majority of providers report the same forged price, the median is forged. The change limit still caps each step at 20%.
- Prices are spot medians, not time-weighted. Thinly traded collateral should add a TWAP source.
