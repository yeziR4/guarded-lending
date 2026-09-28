# Foundry package (Hedera)

Solidity contracts, Forge scripts, and tests for the Hedera EVM.

## Setup

Forge dependencies are tracked as git submodules under `packages/foundry/lib`.
Initialize them from the repo root:

```bash
git submodule update --init --recursive
```

---

## Deploy (Foundry)

From the repo root, contract deploys for this package use **`npm run foundry:deploy`** (runs `packages/foundry`’s deploy script). Inside `packages/foundry`, use **`npm run deploy`** (same entrypoint).

- **Local (recommended):** Start the shared local chain from the repo root, then deploy with `--network localhost` (RPC `http://127.0.0.1:8545`).

  ```bash
  npm run hardhat:chain
  ```

  In another terminal (from repo root or this package):

  ```bash
  npm run foundry:deploy --network localhost
  ```

  This uses the default keystore `scaffold-hbar-default` where applicable (see `Makefile` / `parseArgs.js`).
  The deploy flow auto-creates the local `deployments/` directory before writing `deployments/<chainId>.json`.

- **Plain Anvil (no Hedera fork):** `npm run chain` inside `packages/foundry` runs plain `anvil`—useful for quick iteration, not for full Hedera/HTS parity.

- **Hedera testnet/mainnet:** Use `npm run foundry:deploy --network hedera_testnet` (or `hedera_mainnet`). You **must** use a keystore whose address is a **Hedera-created account** (created and funded via [Hedera Portal](https://portal.hedera.com) or faucet). If you see `Requested resource not found. address '0x...'`, that address does not exist on Hedera. From the repo root, create or import one with `npm run foundry:account:generate` or `npm run foundry:account:import`, then deploy with `--keystore <name>`. For multi-contract deploys, the Makefile uses `--slow` so each transaction is confirmed before the next (avoids `WRONG_NONCE` on Hedera when both txs are in flight).

---

## Tests (Foundry)

- **`npm run test`** inside `packages/foundry` (or `forge test`) – Runs tests on a **local Anvil** chain (no Hedera fork).  
  - **HederaToken** (ERC-20) tests pass.  
  - **HtsTokenCreator** (HTS precompile) tests are **skipped** – these need a Hedera fork or live RPC.

- **`npm run test:local`** inside `packages/foundry` (or `forge test --fork-url http://127.0.0.1:8545 --chain-id 296 --ffi`) – Runs tests against whatever serves **JSON-RPC on 127.0.0.1:8545** with **chain id 296**.

  **Local setup:**

  ```bash
  npm run hardhat:chain
  ```

  Then in another terminal from the repo root:

  ```bash
  npm run foundry:test:local
  ```

  Or from this package: `npm run test:local`.

  This command attaches to the shared local JSON-RPC at `:8545`.

- **`npm run test:testnet`** inside `packages/foundry` – Fork from Hedera testnet RPC (`HEDERA_RPC_URL` or default) with [hedera-forking](https://github.com/hashgraph/hedera-forking) HTS emulation via `htsSetup()` where applicable.

- **`npm run test:mainnet`** inside `packages/foundry` – Fork from Hedera mainnet RPC (read-only / snapshot style checks).

---

## Summary

| Command             | Chain        | HederaToken | HtsTokenCreator |
| ------------------- | ------------ | ----------- | --------------- |
| `npm run test`         | Anvil        | ✅          | ⏭️ (skipped)    |
| `npm run test:local`   | Local fork\* | ✅          | ✅              |
| `npm run test:testnet` | Testnet RPC  | ✅          | ✅              |
| `npm run test:mainnet` | Mainnet RPC  | ✅          | ✅ (read-only)  |

\* Run `npm run hardhat:chain` from the repo root first.

For more on fork testing with HTS emulation, see [forking the Hedera network for local testing](https://docs.hedera.com/hedera/core-concepts/smart-contracts/forking-hedera-network-for-local-testing).
