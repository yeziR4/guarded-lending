# Hedera notes: things that behave differently

Each item here cost real debugging time while building this template on testnet. The code already handles all of them; this page explains why it looks the way it does.

## HBAR has two units depending on where you are

| Where | Unit | Decimals |
| --- | --- | --- |
| Inside the EVM (`msg.value`, `address.balance`, contract storage) | tinybar | 8 |
| JSON-RPC (`value` in a transaction, `eth_getBalance`) | weibar | 18 |

1 tinybar = 10¹⁰ weibar. `LendingMarket` stores collateral in tinybars. The frontend sends `value: tinybars * 10n ** 10n` (`WEIBAR_PER_TINYBAR` in `utils/lending/format.ts`). `cast send --value 30ether` means 30 HBAR.

## Accounts must associate before holding a token

An account cannot receive an HTS token it has not associated with. Every HTS token exposes IHRC-719 on its EVM facade, so a MetaMask-style wallet can call `associate()` on the token address directly. The dashboard checks `isAssociated()` (a view that reads the *caller's* status, so the read is sent `from` the connected account) and shows an "Associate" button when needed. The market associates itself with USDC in `initialize()`.

## A contract can only sign for itself inside an HTS call

Our first `initialize()` named the caller's wallet as the new token's auto-renew account. HTS rejected the creation with response code **326, `INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE`**. Naming an account in a token-creation call requires that account's signature, and a contract calling the precompile can only provide its own. The market is therefore its own auto-renew account and keeps a 1 HBAR `RENEWAL_RESERVE` so renewal fees never come out of borrowers' collateral. The HTS mock in `test/mocks/MockHts.sol` enforces this rule, so the regression is covered offline.

## HTS and HSS do not exist in Forge's local simulation

`forge script` executes the script locally before broadcasting. The system contracts at `0x167` (HTS) and `0x16b` (HSS) have no code there, so any call into them fails in simulation. Even `IERC20(usdc).decimals()` on an HTS token fails, because the token's EVM facade delegates to `0x167`. Two consequences:

- `Deploy.s.sol` only deploys contracts. The market takes the asset's decimals as a constructor argument instead of reading them.
- The HTS/HSS calls (`initialize`, `Guardian.start`) run afterwards as plain transactions from `scripts-js/setupMarket.js`.

`cast send` exits 0 even when the transaction reverts, so the setup script checks the receipt status itself.

## `block.timestamp` is the start of the record block

The first live Guardian booked its tick for second 1790605316. HSS executed it on time, at consensus timestamp 1790605316.07, but inside a record block that had started a second or two earlier. `block.timestamp` reports the block start, so the Guardian saw a time *before* `nextRunAt`, decided the run was early, and did not book the next one. `Guardian.BLOCK_TIME_TOLERANCE` (10 s) fixes this, and `test_tick_scheduledExecutionSeesEarlierBlockTime_stillReschedules` pins the regression.

## HIP-1215 scheduled calls: what to expect

- The scheduling contract pays for execution. On testnet a Guardian tick with a 400k gas limit cost about 0.18 HBAR. Hedera charges at least 80% of the gas limit, so do not over-provision it.
- Schedule from a direct `CALL` to `0x16b`. Scheduling from a `DELEGATECALL` frame currently fails at execution on testnet ([hiero-consensus-node#27263](https://github.com/hiero-ledger/hiero-consensus-node/issues/27263)).
- A booked schedule is its own entity (`0.0.x`) and is visible on HashScan with its execution timestamp.

## Read history from the mirror node, not `eth_getLogs`

Public relays such as Hashio limit `eth_getLogs` to narrow block ranges. The mirror node REST API is the Hedera-native way to read history, with one catch: it only filters logs by topic inside an explicit timestamp range. `fetchContractLogs` therefore pages through a contract's logs and filters client-side. The relayer uses a `timestamp=gt:<cursor>` range, which is allowed.

## Pyth needs an API key since 26 Aug 2026

Hermes (`pyth.dourolabs.app/hermes`) requires `Authorization: Bearer <key>`. The key must stay server-side, so the dashboard fetches update data through `/api/pyth-update`. The on-chain Pyth contract address on Hedera did not change; it was upgraded in place.

## Build and lint pitfalls in the base stack

- `@coinbase/cdp-sdk` (pulled in by wagmi's Base Account connector) imports optional `@x402/*` peers unconditionally, which breaks `next build` when they are not installed. `next.config.ts` aliases them to empty modules.
- npm hoists the frontend's prettier plugins to the root `node_modules`, and prettier 2 auto-loads them, so the Foundry package's `prettier --check` failed on untouched files. The Makefile passes `--no-plugin-search`.
- On Windows: PowerShell may block `npm.ps1` (use `npm.cmd`), `make` is not installed by default (use the plain `forge` commands in the README), and `forge install` writes backslashes into `foundry.lock` keys. They must be `lib/<name>`, or scaffold-hbar cannot pin the library version.
