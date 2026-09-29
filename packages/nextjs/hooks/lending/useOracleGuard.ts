import type { Address } from "viem";
import { useReadContract } from "wagmi";
import { useScaffoldReadContract } from "~~/hooks/scaffold-hbar";
import { POLLED } from "~~/utils/lending/format";

/** Mirrors `OracleGuard.Status`. */
export const SOURCE_STATUS = ["Ok", "Reverted", "Stale", "Out of bounds", "Outlier"] as const;
/** Mirrors `OracleGuard.TripReason`. */
export const TRIP_REASON = ["None", "No quorum", "Excessive change"] as const;

const labelAbi = [
  { type: "function", name: "label", inputs: [], outputs: [{ type: "string" }], stateMutability: "view" },
] as const;

const useSource = (index: bigint) => {
  const { data } = useScaffoldReadContract({
    contractName: "OracleGuard",
    functionName: "sourceAt",
    args: [index],
    watch: false,
  });
  const address = data?.[0] as Address | undefined;
  const { data: label } = useReadContract({ address, abi: labelAbi, functionName: "label" });
  return { address, label };
};

export const useOracleGuard = () => {
  const inspect = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "inspect", ...POLLED });
  const lastPrice = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "lastPrice", ...POLLED });
  const lastPriceAt = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "lastPriceAt", ...POLLED });
  const tripReason = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "tripReason", ...POLLED });
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
  // One slot per source wired in Deploy.s.sol.
  const sourceMeta = [useSource(0n), useSource(1n), useSource(2n)];

  const [readings, median, agreeing] = inspect.data ?? [[], 0n, 0n];

  return {
    sources: readings.map((reading, i) => ({ ...reading, ...sourceMeta[i] })),
    median,
    agreeing,
    lastPrice: lastPrice.data,
    lastPriceAt: lastPriceAt.data,
    tripReason: tripReason.data ?? 0,
    quorum,
    maxDeviationBps,
    refetch: () => Promise.all([inspect, lastPrice, lastPriceAt, tripReason].map(q => q.refetch())),
  };
};
