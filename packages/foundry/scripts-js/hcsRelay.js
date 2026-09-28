/**
 * Mirrors every OracleGuard decision to a Hedera Consensus Service topic.
 *
 * The guard's events already live on-chain, but HCS turns them into an ordered, consensus-timestamped
 * audit log with its own identity: one topic per market, readable by anyone through the mirror node,
 * with a submit key so only this relayer can write to it. The dashboard's "Oracle audit log" reads it.
 *
 * Usage: npm run relay -- --keystore <name> [--network hedera_testnet] [--topic 0.0.x] [--interval 30]
 * First run without --topic (or AUDIT_TOPIC_ID) creates the topic and prints its id.
 */
import {
  AccountId,
  Client,
  PrivateKey,
  TopicCreateTransaction,
  TopicMessageSubmitTransaction,
} from "@hiero-ledger/sdk";
import { spawnSync } from "child_process";
import { config } from "dotenv";
import { ethers } from "ethers";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

config();
const __dirname = dirname(fileURLToPath(import.meta.url));

const NETWORKS = {
  hedera_testnet: {
    chainId: 296,
    rpc: "https://testnet.hashio.io/api",
    mirror: "https://testnet.mirrornode.hedera.com",
  },
  hedera_mainnet: {
    chainId: 295,
    rpc: "https://mainnet.hashio.io/api",
    mirror: "https://mainnet.mirrornode.hedera.com",
  },
};
const STATUS = ["Ok", "Reverted", "Stale", "OutOfBounds", "Outlier"];
const TRIP_REASON = ["None", "NoQuorum", "ExcessiveChange"];

const guardAbi = [
  "event Checked(uint256 medianE18, uint256 agreeing, (uint256 priceE18, uint256 updatedAt, uint8 status)[] readings)",
  "event Tripped(uint8 reason, uint256 medianE18)",
  "event Reset(uint256 priceE18)",
  "function sourceCount() view returns (uint256)",
  "function sourceAt(uint256) view returns (address source, uint256 maxAge)",
];
const labelAbi = ["function label() view returns (string)"];

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const network = NETWORKS[arg("network", "hedera_testnet")];
const keystore = arg("keystore");
const intervalMs = Number(arg("interval", "30")) * 1000;
if (!network || !keystore) {
  console.error(
    "Usage: npm run relay -- --keystore <name> [--network hedera_testnet] [--topic 0.0.x]",
  );
  process.exit(1);
}

const deployments = JSON.parse(
  readFileSync(
    join(__dirname, "..", "deployments", `${network.chainId}.json`),
    "utf8",
  ),
);
const guardAddress = Object.keys(deployments).find(
  (key) => deployments[key] === "OracleGuard",
);
if (!guardAddress) {
  console.error("OracleGuard not found in deployments. Deploy first.");
  process.exit(1);
}

/** Lets `cast` prompt for the keystore password and hand back the key, so this script never sees the password. */
function decryptKeystore(name) {
  const result = spawnSync("cast", ["wallet", "decrypt-keystore", name], {
    stdio: ["inherit", "pipe", "inherit"],
    encoding: "utf8",
  });
  const key = result.stdout?.match(/0x[0-9a-fA-F]{64}/)?.[0];
  if (result.status !== 0 || !key) {
    console.error("Could not decrypt keystore.");
    process.exit(1);
  }
  return key;
}

async function mirror(path) {
  const response = await fetch(`${network.mirror}${path}`);
  if (!response.ok)
    throw new Error(`Mirror node ${response.status} for ${path}`);
  return response.json();
}

const price = (e18) =>
  `$${Number(ethers.utils.formatUnits(e18, 18)).toFixed(4)}`;

const privateKeyHex = decryptKeystore(keystore);
const wallet = new ethers.Wallet(privateKeyHex);
const { account } = await mirror(`/api/v1/accounts/${wallet.address}`);
const operatorKey = PrivateKey.fromStringECDSA(privateKeyHex.slice(2));
const client = (
  network.chainId === 295 ? Client.forMainnet() : Client.forTestnet()
).setOperator(AccountId.fromString(account), operatorKey);

let topicId = arg("topic", process.env.AUDIT_TOPIC_ID);
if (!topicId) {
  const receipt = await (
    await new TopicCreateTransaction()
      .setTopicMemo(`OracleGuard audit log ${guardAddress}`)
      .setSubmitKey(operatorKey.publicKey)
      .execute(client)
  ).getReceipt(client);
  topicId = receipt.topicId.toString();
  console.log(`\n🆕 Created HCS topic ${topicId}`);
  console.log(
    `   Set NEXT_PUBLIC_AUDIT_TOPIC_ID=${topicId} in packages/nextjs/.env.local`,
  );
  console.log(
    `   Pass --topic ${topicId} (or set AUDIT_TOPIC_ID) on the next run.\n`,
  );
}

const provider = new ethers.providers.JsonRpcProvider(network.rpc);
const guard = new ethers.Contract(guardAddress, guardAbi, provider);
const labels = [];
for (let i = 0; i < (await guard.sourceCount()).toNumber(); i++) {
  const [source] = await guard.sourceAt(i);
  labels.push(await new ethers.Contract(source, labelAbi, provider).label());
}

// The cursor (last relayed consensus timestamp) survives restarts so no event is published twice.
const cursorPath = join(
  __dirname,
  "..",
  `.relay-cursor-${network.chainId}-${topicId}.json`,
);
let cursor = existsSync(cursorPath)
  ? JSON.parse(readFileSync(cursorPath, "utf8")).timestamp
  : "0";

function toMessage(parsed, log) {
  const base = { event: parsed.name, tx: log.transaction_hash };
  if (parsed.name === "Checked") {
    return {
      ...base,
      median: price(parsed.args.medianE18),
      agreeing: parsed.args.agreeing.toNumber(),
      sources: parsed.args.readings.map((r, i) => ({
        label: labels[i],
        price: price(r.priceE18),
        status: STATUS[r.status],
      })),
    };
  }
  if (parsed.name === "Tripped") {
    return {
      ...base,
      reason: TRIP_REASON[parsed.args.reason],
      median: price(parsed.args.medianE18),
    };
  }
  return { ...base, median: price(parsed.args.priceE18) };
}

async function relayOnce() {
  const { logs } = await mirror(
    `/api/v1/contracts/${guardAddress}/results/logs?timestamp=gt:${cursor}&order=asc&limit=100`,
  );
  for (const log of logs) {
    let parsed;
    try {
      parsed = guard.interface.parseLog({ topics: log.topics, data: log.data });
    } catch {
      continue; // PriceAccepted and any other events are implied by Checked
    }
    const message = JSON.stringify(toMessage(parsed, log));
    await (
      await new TopicMessageSubmitTransaction()
        .setTopicId(topicId)
        .setMessage(message)
        .execute(client)
    ).getReceipt(client);
    cursor = log.timestamp;
    writeFileSync(cursorPath, JSON.stringify({ timestamp: cursor }));
    console.log(`→ ${topicId}  ${parsed.name}  ${message.length}B`);
  }
}

console.log(
  `Relaying OracleGuard ${guardAddress} → HCS topic ${topicId} every ${
    intervalMs / 1000
  }s (Ctrl+C to stop)`,
);
for (;;) {
  try {
    await relayOnce();
  } catch (error) {
    console.error(`Relay error: ${error.message}`);
  }
  await new Promise((resolve) => setTimeout(resolve, intervalMs));
}
