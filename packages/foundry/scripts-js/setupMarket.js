/**
 * Post-deploy calls that need HTS/HSS, which forge script simulation lacks: create the receipt token,
 * take the first price, start the Guardian. Idempotent.
 *
 * Usage: npm run setup -- --network hedera_testnet --keystore <name> [--guardian-funding 20]
 */
import { spawnSync } from "child_process";
import { config } from "dotenv";
import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

config();
const __dirname = dirname(fileURLToPath(import.meta.url));

const NETWORKS = {
  hedera_testnet: {
    chainId: 296,
    rpc: process.env.HEDERA_RPC_URL || "https://testnet.hashio.io/api",
    explorer: "testnet",
  },
  hedera_mainnet: {
    chainId: 295,
    rpc: "https://mainnet.hashio.io/api",
    explorer: "mainnet",
  },
};

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const networkName = arg("network", "hedera_testnet");
const keystore = arg("keystore");
// JSON-RPC values are weibars (18 decimals), so "ether" units below are whole HBAR.
const htsFeeHbar = arg("hts-fee", "30");
const guardianFundingHbar = arg("guardian-funding", "20");

const network = NETWORKS[networkName];
if (!network) {
  console.error(
    `Unknown network '${networkName}'. Use one of: ${Object.keys(NETWORKS).join(
      ", ",
    )}`,
  );
  process.exit(1);
}
if (!keystore) {
  console.error("Missing --keystore <name> (see `npm run account:import`).");
  process.exit(1);
}

const deploymentsPath = join(
  __dirname,
  "..",
  "deployments",
  `${network.chainId}.json`,
);
if (!existsSync(deploymentsPath)) {
  console.error(`No deployments found at ${deploymentsPath}. Deploy first.`);
  process.exit(1);
}

// deployments/<chainId>.json maps address -> contract name.
const byName = Object.fromEntries(
  Object.entries(JSON.parse(readFileSync(deploymentsPath, "utf8")))
    .filter(([key]) => key.startsWith("0x"))
    .map(([address, name]) => [name, address]),
);
for (const name of ["LendingMarket", "OracleGuard", "Guardian"]) {
  if (!byName[name]) {
    console.error(`${name} missing from ${deploymentsPath}.`);
    process.exit(1);
  }
}

function send(label, to, signature, args = [], value) {
  console.log(`\n▶ ${label}`);
  const cmd = [
    "send",
    to,
    signature,
    ...args,
    "--rpc-url",
    network.rpc,
    "--account",
    keystore,
    "--legacy",
    "--json",
  ];
  if (value) cmd.push("--value", `${value}ether`);
  // stdout carries the JSON receipt; stdin/stderr stay attached so cast can prompt for the password.
  const result = spawnSync("cast", cmd, {
    stdio: ["inherit", "pipe", "inherit"],
    encoding: "utf8",
  });

  let receipt;
  try {
    receipt = JSON.parse(result.stdout);
  } catch {
    receipt = undefined;
  }
  // `cast send` exits 0 even when the transaction reverts, so check the receipt status.
  if (result.status !== 0 || receipt?.status !== "0x1") {
    console.error(`\n❌ ${label} failed.`);
    if (receipt?.transactionHash)
      console.error(
        `   https://hashscan.io/${network.explorer}/tx/${receipt.transactionHash}`,
      );
    process.exit(result.status || 1);
  }
  console.log(
    `   ✔ https://hashscan.io/${network.explorer}/tx/${receipt.transactionHash}`,
  );
}

function call(to, signature) {
  const result = spawnSync(
    "cast",
    ["call", to, signature, "--rpc-url", network.rpc],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    console.error(
      `\n❌ Could not read ${signature} on ${to}:\n${result.stderr}`,
    );
    process.exit(1);
  }
  return result.stdout.trim().split(" ")[0];
}

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

if (call(byName.LendingMarket, "shareToken()(address)") === ZERO_ADDRESS) {
  send(
    `Initialize market (HTS fee from ${htsFeeHbar} HBAR; 1 HBAR renewal reserve kept, rest refunded)`,
    byName.LendingMarket,
    "initialize(string,string)",
    ["Guarded USDC", "gUSDC"],
    htsFeeHbar,
  );
} else {
  console.log("\n✔ Market already initialized");
}

send("Oracle check", byName.OracleGuard, "poke()");

const nextRunAt = BigInt(call(byName.Guardian, "nextRunAt()(uint256)"));
if (nextRunAt <= BigInt(Math.floor(Date.now() / 1000))) {
  send(
    `Start Guardian (funded with ${guardianFundingHbar} HBAR)`,
    byName.Guardian,
    "start()",
    [],
    guardianFundingHbar,
  );
} else {
  console.log(
    `\n✔ Guardian already scheduled for ${new Date(
      Number(nextRunAt) * 1000,
    ).toISOString()}`,
  );
}

console.log("\n✅ Market initialized, price accepted, Guardian scheduled.");
