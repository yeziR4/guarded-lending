import type { Address } from "viem";
import { useAccount } from "wagmi";
import { useDeployedContractInfo, useScaffoldReadContract } from "~~/hooks/scaffold-hbar";
import { POLLED, POLL_MS } from "~~/utils/lending/format";

/** Market-wide figures plus the connected wallet's position, priced at the guard's last accepted price. */
export const useMarket = () => {
  const { address } = useAccount();
  const { data: market } = useDeployedContractInfo({ contractName: "LendingMarket" });
  const { data: usdc } = useDeployedContractInfo({ contractName: "USDC" });

  const shareToken = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "shareToken",
    watch: false,
  });
  const totalAssets = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "totalAssets",
    ...POLLED,
  });
  const totalBorrows = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "totalBorrows",
    ...POLLED,
  });
  const totalCollateral = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "totalCollateral",
    ...POLLED,
  });
  const utilization = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "utilization",
    ...POLLED,
  });
  const borrowRate = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "borrowRatePerSecond",
    ...POLLED,
  });
  const lastPrice = useScaffoldReadContract({ contractName: "OracleGuard", functionName: "lastPrice", ...POLLED });
  const position = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "positionAt",
    args: [address, lastPrice.data],
    watch: false,
    query: { enabled: Boolean(address && lastPrice.data), refetchInterval: POLL_MS },
  });

  const [collateral, debt, maxDebt, healthFactor] = position.data ?? [0n, 0n, 0n, 0n];

  return {
    marketAddress: market?.address,
    usdcAddress: usdc?.address,
    shareToken: shareToken.data as Address | undefined,
    totalAssets: totalAssets.data ?? 0n,
    totalBorrows: totalBorrows.data ?? 0n,
    totalCollateral: totalCollateral.data ?? 0n,
    utilization: utilization.data ?? 0n,
    borrowRatePerSecond: borrowRate.data ?? 0n,
    price: lastPrice.data,
    position: { collateral, debt, maxDebt, healthFactor },
    refetch: () =>
      Promise.all(
        [totalAssets, totalBorrows, totalCollateral, utilization, borrowRate, position].map(q => q.refetch()),
      ),
  };
};
