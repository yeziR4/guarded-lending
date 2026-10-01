# Hedera notes

Places where Hedera behaves differently from other EVM chains, and what this template does about each one.

## Pin Foundry below 1.8

Foundry 1.8 sends EIP-1898 block objects for state reads, and the Hedera JSON-RPC relay rejects them with `-32602 Invalid parameter 1: ... [object Object]`. That breaks every `forge script` and every `--fork-url` test; offline `forge test` is unaffected. Use `foundryup --install v1.5.1` (1.7.1 also works). CI pins 1.5.1. See [lattice#227](https://github.com/dadadave80/lattice/issues/227).

## Two units for HBAR

Inside the EVM (`msg.value`, balances, storage) HBAR is **tinybars**, with 8 decimals. Over JSON-RPC it is **weibars**, with 18 decimals. The market stores tinybars, and the frontend multiplies by 10¹⁰ (`WEIBAR_PER_TINYBAR`) when sending value. `cast send --value 30ether` sends 30 HBAR.

## Token association

An account must associate with an HTS token before it can receive it. HTS tokens expose IHRC-719 `associate()` on their EVM address, so a normal wallet can do it in one call. The dashboard shows an "Associate" button when `isAssociated()` returns false. That call reads the caller's own status, so it is sent `from` the connected account.

## A contract can only sign for itself in an HTS call

When a contract creates a token, every account it names (auto-renew, treasury, keys) must sign. The contract can only provide its own signature, so naming any other account fails with **326 `INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE`**. The market is therefore its own auto-renew account and keeps a 1 HBAR `RENEWAL_RESERVE`, so renewals never touch collateral.

## No HTS or HSS in `forge script` simulation

`forge script` runs locally before broadcasting, and the system contracts `0x167` (HTS) and `0x16b` (HSS) do not exist there. Even `decimals()` on an HTS token fails. So `Deploy.s.sol` only deploys contracts, and `setupMarket.js` sends the HTS/HSS calls afterwards. `cast send` exits 0 on a reverted transaction, so the script checks the receipt status itself.

## Scheduled calls (HIP-1215)

- **`block.timestamp` can be earlier than the booked second.** It reports the start of Hedera's ~2 s record block. The Guardian allows 10 s of tolerance.
- **Booking costs about 1.4M gas**, because the schedule fee is charged as gas. A tick that books its successor needs a gas limit ≥ 1.6M. The Guardian books inside a `try/catch`, so a failed booking stops the loop without undoing the oracle check. Each tick costs about 1.7 HBAR on testnet, and Hedera charges at least 80% of the gas limit.
- **Call `0x16b` directly.** Scheduling from a DELEGATECALL frame fails at execution on testnet ([hiero-consensus-node#27263](https://github.com/hiero-ledger/hiero-consensus-node/issues/27263)).

## History comes from the mirror node

Public relays limit `eth_getLogs` ranges, so the dashboard reads event logs from the mirror node REST API. The mirror node only filters logs by topic inside a timestamp range, so `fetchContractLogs` pages through a contract's logs and filters client-side.

## Pyth needs an API key

Since 26 Aug 2026 Hermes (`pyth.dourolabs.app/hermes`) needs `Authorization: Bearer <key>`. `/api/pyth-update` keeps the key server-side. The on-chain Pyth address on Hedera is unchanged.

## Base-stack fixes in this template

- `create-scaffold-hbar` runs `npm run format` after install. With two prettier versions installed, the import-sort plugin corrupted TypeScript (`[K in keyof T]` became `[ in ]`). The workspaces now share prettier 3.
- `@coinbase/cdp-sdk`, pulled in through wagmi, imports optional `@x402/*` packages. `next.config.ts` aliases them to empty modules so `next build` works.
- On Windows, `forge install` writes `lib\\name` keys into `foundry.lock`. They must be `lib/name`, or the CLI cannot pin library versions.
