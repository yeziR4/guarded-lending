import type { Address } from "viem";
import { useReadContract } from "wagmi";
import { useScaffoldReadContract } from "~~/hooks/scaffold-hbar";

/** Mirrors `OracleGuard.Status`. */
export const SOURCE_STATUS = ["Ok", "Reverted", "Stale", "Out of bounds", "Outlier"] as const;
/** Mirrors `OracleGuard.TripReason`. */
export const TRIP_REASON = ["None", "No quorum", "Excessive change"] as const;

const POLL = { watch: false, query: { refetchInterval: 10_000 } } as const;

const labelAbi = [
  { type: "function", name: "label", inputs: [], outputs: [{ type: "string" }], stateMutability: "view" },
] as const;

/** One source's address, freshness limit and provider label. */
const useSource = (index: bigint) => {
  const { data } = useScaffoldReadContract({
    contractName: "OracleGuard",
    functionName: "sourceAt",
    args: [index],
    watch: false,
  });
  const address = data?.[0] as Address | undefined;
  const { data: label } = useReadContract({
    address,
    abi: labelAbi,
    functionName: "label",
    query: { enabled: Boolean(data) },
  });
  return { address, maxAge: data?.[1], label };
};

/** Live view of the guard: per-source readings, consensus, breaker state and configuration. */
export const useOracleGuard = () => {
  const inspect = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "inspect", ...POLL });
  const lastPrice = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "lastPrice", ...POLL });
  const lastPriceAt = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "lastPriceAt", ...POLL });
  const tripReason = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "tripReason", ...POLL });
  const trippedAt = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "trippedAt", ...POLL });
  const { data: quorum } = useScaffoldReadContract({
    contractName: "OracleGuard",
    functionName: "QUORUM",
    watch: false,
  });
  const { data: maxDeviationBps } = useScaffoldReadContract({
    contractName: "OracleGuard",
    functionName: "MAX_DEVIATION_BPS",
    watch: false,
  });
  const { data: cooldown } = useScaffoldReadContract({
    contractName: "OracleGuard",
    functionName: "COOLDOWN",
    watch: false,
  });
  // One slot per source wired in Deploy.s.sol; add a slot here if you add a source.
  const sourceMeta = [useSource(0n), useSource(1n), useSource(2n)];

  const [readings, median, agreeing] = inspect.data ?? [[], 0n, 0n];

  return {
    loaded: inspect.data !== undefined && lastPrice.data !== undefined,
    sources: readings.map((reading, i) => ({ ...reading, ...sourceMeta[i] })),
    median,
    agreeing,
    lastPrice: lastPrice.data,
    lastPriceAt: lastPriceAt.data,
    tripReason: tripReason.data ?? 0,
    trippedAt: trippedAt.data,
    quorum,
    maxDeviationBps,
    cooldown,
    refetch: () => Promise.all([inspect, lastPrice, lastPriceAt, tripReason, trippedAt].map(q => q.refetch())),
  };
};
