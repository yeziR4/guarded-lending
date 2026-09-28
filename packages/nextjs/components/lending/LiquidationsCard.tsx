"use client";

import { AmountForm } from "./AmountForm";
import { useQuery } from "@tanstack/react-query";
import { Address, getAddress, toEventSelector } from "viem";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { useScaffoldReadContract, useScaffoldWriteContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { USDC_DECIMALS, formatHealthFactor, formatUsdc } from "~~/utils/lending/format";
import { fetchContractLogs } from "~~/utils/lending/mirrorNode";

const BORROWED_TOPIC = toEventSelector("Borrowed(address,uint256)");
const WAD = 10n ** 18n;

/** Borrowers seen in `Borrowed` events, newest first, read from the mirror node. */
const useBorrowers = (market: Address | undefined, chainId: number) =>
  useQuery({
    queryKey: ["borrowers", chainId, market],
    enabled: Boolean(market),
    refetchInterval: 30_000,
    queryFn: async () => {
      const logs = await fetchContractLogs(chainId, market as Address, BORROWED_TOPIC);
      return [...new Set(logs.map(log => getAddress(`0x${log.topics[1].slice(26)}`)))];
    },
  });

export const LiquidationsCard = () => {
  const { targetNetwork } = useTargetNetwork();
  const market = useMarket();
  const { data: borrowers, isLoading } = useBorrowers(market.marketAddress, targetNetwork.id);

  return (
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-3">
        <h2 className="card-title">Liquidations</h2>
        <p className="text-sm text-base-content/70 m-0">
          A position with health factor below 1 can be repaid by anyone, who receives the equivalent HBAR plus a 5%
          bonus. Liquidations use the guarded price, so a forged oracle update cannot trigger them.
        </p>
        {isLoading && <span className="loading loading-dots loading-sm" />}
        {borrowers?.length === 0 && <p className="text-sm m-0">No borrowers yet.</p>}
        <div className="flex flex-col gap-2">
          {borrowers?.map(borrower => (
            <BorrowerRow key={borrower} borrower={borrower} price={market.price} />
          ))}
        </div>
      </div>
    </section>
  );
};

const BorrowerRow = ({ borrower, price }: { borrower: Address; price: bigint | undefined }) => {
  const { targetNetwork } = useTargetNetwork();
  const market = useMarket();
  const usdc = useHtsToken(market.usdcAddress, market.marketAddress);
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });
  const { data: closeFactorBps } = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "CLOSE_FACTOR_BPS",
    watch: false,
  });
  const { data: position, refetch } = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "positionAt",
    args: [borrower, price],
    watch: false,
    query: { enabled: price !== undefined, refetchInterval: 15_000 },
  });

  if (!position || position[1] === 0n) return null;
  const [, debt, , healthFactor] = position;
  const liquidatable = healthFactor < WAD;
  const maxRepay = closeFactorBps ? (debt * closeFactorBps) / 10_000n : 0n;

  const liquidate = async (amount: bigint) => {
    await usdc.ensureAllowance(amount);
    await writeContractAsync({ functionName: "liquidate", args: [borrower, amount] });
    await refetch();
  };

  return (
    <div className="rounded-box border border-base-300 p-3 flex flex-col gap-2">
      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
        <HederaAddress address={borrower} chain={targetNetwork} />
        <span>Debt {formatUsdc(debt)} USDC</span>
        <span className={liquidatable ? "text-error font-semibold" : ""}>HF {formatHealthFactor(healthFactor)}</span>
      </div>
      {liquidatable && (
        <AmountForm action="Liquidate" unit="USDC" decimals={USDC_DECIMALS} max={maxRepay} onSubmit={liquidate} />
      )}
    </div>
  );
};
