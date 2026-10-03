"use client";

import { AmountForm } from "./AmountForm";
import { useQuery } from "@tanstack/react-query";
import { Address, getAddress, toEventSelector } from "viem";
import { HederaAddress } from "~~/components/scaffold-hbar";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { useScaffoldReadContract, useScaffoldWriteContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { ASSET_DECIMALS, POLL_MS, formatAsset, formatHealthFactor } from "~~/utils/lending/format";
import { fetchContractLogs } from "~~/utils/lending/mirrorNode";

const BORROWED_TOPIC = toEventSelector("Borrowed(address,uint256)");
const WAD = 10n ** 18n;

export const LiquidationsCard = () => {
  const { targetNetwork } = useTargetNetwork();
  const market = useMarket();
  const asset = useHtsToken(market.assetAddress, market.marketAddress);
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });
  const { data: closeFactorBps = 0n } = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "CLOSE_FACTOR_BPS",
    watch: false,
  });

  // Borrowers seen in `Borrowed` events, read from the mirror node.
  const { data: borrowers, isLoading } = useQuery({
    queryKey: ["borrowers", targetNetwork.id, market.marketAddress],
    enabled: Boolean(market.marketAddress),
    refetchInterval: 3 * POLL_MS,
    queryFn: async () => {
      const logs = await fetchContractLogs(targetNetwork.id, market.marketAddress as Address, BORROWED_TOPIC);
      return [...new Set(logs.map(log => getAddress(`0x${log.topics[1].slice(26)}`)))];
    },
  });

  const liquidate = async (borrower: Address, amount: bigint) => {
    await asset.ensureAllowance(amount);
    await writeContractAsync({ functionName: "liquidate", args: [borrower, amount] });
  };

  return (
    <section className="card bg-base-100 shadow-sm">
      <div className="card-body gap-3">
        <h2 className="card-title">Liquidations</h2>
        <p className="text-sm text-base-content/70 m-0">
          Positions below health factor 1 can be repaid by anyone for the equivalent HBAR plus a 5% bonus, priced
          through the guard.
        </p>
        {isLoading && <span className="loading loading-dots loading-sm" />}
        {borrowers?.length === 0 && <p className="text-sm m-0">No borrowers yet.</p>}
        {borrowers?.map(borrower => (
          <BorrowerRow
            key={borrower}
            borrower={borrower}
            price={market.price}
            symbol={market.assetSymbol}
            closeFactorBps={closeFactorBps}
            onLiquidate={amount => liquidate(borrower, amount)}
          />
        ))}
      </div>
    </section>
  );
};

type BorrowerRowProps = {
  borrower: Address;
  price: bigint | undefined;
  symbol: string;
  closeFactorBps: bigint;
  onLiquidate: (amount: bigint) => Promise<void>;
};

const BorrowerRow = ({ borrower, price, symbol, closeFactorBps, onLiquidate }: BorrowerRowProps) => {
  const { targetNetwork } = useTargetNetwork();
  const { data: position } = useScaffoldReadContract({
    contractName: "LendingMarket",
    functionName: "positionAt",
    args: [borrower, price],
    watch: false,
    query: { enabled: price !== undefined, refetchInterval: POLL_MS },
  });

  if (!position || position[1] === 0n) return null;
  const [, debt, , healthFactor] = position;
  const liquidatable = healthFactor < WAD;

  return (
    <div className="rounded-box bg-base-200 p-3 flex flex-col gap-2">
      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
        <HederaAddress address={borrower} chain={targetNetwork} />
        <span>
          Debt {formatAsset(debt)} {symbol}
        </span>
        <span className={liquidatable ? "text-error font-semibold" : ""}>HF {formatHealthFactor(healthFactor)}</span>
      </div>
      {liquidatable && (
        <AmountForm
          label="Repay up to half the debt and receive HBAR at a 5% bonus"
          action="Liquidate"
          unit={symbol}
          decimals={ASSET_DECIMALS}
          max={(debt * closeFactorBps) / 10_000n}
          onSubmit={onLiquidate}
        />
      )}
    </div>
  );
};
