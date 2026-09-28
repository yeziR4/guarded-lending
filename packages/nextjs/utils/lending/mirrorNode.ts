import { hedera } from "viem/chains";

/**
 * Hedera mirror node REST API. History (event logs, HCS topic messages) is read here rather than via
 * `eth_getLogs`, which public JSON-RPC relays restrict to narrow block ranges.
 */
export const mirrorNodeUrl = (chainId: number) =>
  chainId === hedera.id ? "https://mainnet.mirrornode.hedera.com" : "https://testnet.mirrornode.hedera.com";

export const hashscanUrl = (chainId: number, path: string) =>
  `https://hashscan.io/${chainId === hedera.id ? "mainnet" : "testnet"}/${path}`;

export type MirrorLog = { topics: `0x${string}`[]; data: `0x${string}`; timestamp: string; transaction_hash: string };

/**
 * Logs emitted by `contract` with the given topic0, newest first. The mirror node only filters by topic
 * inside an explicit timestamp range, so this pages through the contract's logs (up to `maxPages` × 100)
 * and filters client-side. An indexer is the right tool once a market outgrows that.
 */
export const fetchContractLogs = async (chainId: number, contract: string, topic0: string, maxPages = 10) => {
  const base = mirrorNodeUrl(chainId);
  const matches: MirrorLog[] = [];
  let next: string | null = `/api/v1/contracts/${contract}/results/logs?order=desc&limit=100`;

  for (let page = 0; next && page < maxPages; page++) {
    const response = await fetch(`${base}${next}`);
    if (!response.ok) throw new Error(`Mirror node ${response.status} for ${next}`);
    const body: { logs: MirrorLog[]; links: { next: string | null } } = await response.json();
    matches.push(...body.logs.filter(log => log.topics[0] === topic0));
    next = body.links.next;
  }
  return matches;
};

export type TopicMessage = { sequence_number: number; consensus_timestamp: string; message: string };

export const fetchTopicMessages = async (chainId: number, topicId: string, limit = 25) => {
  const url = `${mirrorNodeUrl(chainId)}/api/v1/topics/${topicId}/messages?order=desc&limit=${limit}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Mirror node ${response.status} for ${url}`);
  const body: { messages: TopicMessage[] } = await response.json();
  return body.messages.map(m => ({ ...m, message: atob(m.message) }));
};
