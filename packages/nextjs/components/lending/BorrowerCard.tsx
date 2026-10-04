"use client";

import { AmountForm } from "./AmountForm";
import { useAccount, useBalance } from "wagmi";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { usePythUpdate } from "~~/hooks/lending/usePythUpdate";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import {
  ASSET_DECIMALS,
  TINYBAR_DECIMALS,
  WEIBAR_PER_TINYBAR,
  formatAsset,
  formatHbar,
  formatHealthFactor,
} from "~~/utils/lending/format";

const WAD = 10n ** 18n;

export const BorrowerCard = () => {
  const { address } = useAccount();
  const market = useMarket();
  const asset = useHtsToken(market.assetAddress, market.marketAddress);
  const pyth = usePythUpdate();
  const { data: hbar } = useBalance({ address });
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });
  const { collateral, debt, maxDebt, healthFactor } = market.position;
  const symbol = market.assetSymbol;

  const refresh = () => Promise.all([asset.refetch(), market.refetch()]);
  // Wallet balances come back in weibars; the market works in tinybars.
  const walletTinybars = hbar ? hbar.value / WEIBAR_PER_TINYBAR : 0n;
  const liquidity = market.totalAssets > market.totalBorrows ? market.totalAssets - market.totalBorrows : 0n;
  const headroom = maxDebt > debt ? maxDebt - debt : 0n;
  const borrowable = headroom < liquidity ? headroom : liquidity;
  const healthClass = healthFactor < WAD ? "text-error" : healthFactor < (12n * WAD) / 10n ? "text-warning" : "";

  const deposit = async (tinybars: bigint) => {
    await writeContractAsync({ functionName: "depositCollateral", value: tinybars * WEIBAR_PER_TINYBAR });
    await refresh();
  };
  const withdraw = async (tinybars: bigint) => {
    await pyth.refresh();
    await writeContractAsync({ functionName: "withdrawCollateral", args: [tinybars] });
    await refresh();
  };
  const borrow = async (amount: bigint) => {
    await asset.ensureAssociated();
    await pyth.refresh();
    await writeContractAsync({ functionName: "borrow", args: [amount] });
    await refresh();
  };
  const repay = async (amount: bigint) => {
    if (!address) return;
    await asset.ensureAllowance(amount);
    await writeContractAsync({ functionName: "repay", args: [address, amount] });
    await refresh();
  };

  return (
    <section className="card bg-base-100 shadow-sm">
      <div className="card-body gap-3">
        <h2 className="card-title">Borrow against HBAR</h2>
        <p className="text-sm text-base-content/70 m-0">
          Lock HBAR, borrow up to 65% of its value in {symbol}. Every borrow is priced through the oracle guard.
        </p>

        {collateral > 0n && (
          <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm rounded-box bg-base-200 p-3">
            <span>Collateral</span>
            <span className="text-right font-semibold">{formatHbar(collateral)} HBAR</span>
            <span>Debt</span>
            <span className="text-right font-semibold">
              {formatAsset(debt)} {symbol}
            </span>
            <span>Borrow limit</span>
            <span className="text-right font-semibold">
              {formatAsset(maxDebt)} {symbol}
            </span>
            <span>Health factor</span>
            <span className={`text-right font-semibold ${healthClass}`}>{formatHealthFactor(healthFactor)}</span>
          </div>
        )}

        {address && (
          <AmountForm
            label="Deposit HBAR collateral"
            action="Deposit"
            unit="HBAR"
            decimals={TINYBAR_DECIMALS}
            max={walletTinybars}
            onSubmit={deposit}
          />
        )}
        {collateral > 0n && liquidity === 0n && (
          <p className="text-sm m-0">
            Nothing to borrow yet: no {symbol} has been supplied. Supply some in the Lend card first.
          </p>
        )}
        {collateral > 0n && liquidity > 0n && (
          <AmountForm
            label={`Borrow ${symbol}`}
            action="Borrow"
            unit={symbol}
            decimals={ASSET_DECIMALS}
            max={borrowable}
            onSubmit={borrow}
          />
        )}
        {debt > 0n && (
          <AmountForm
            label="Repay"
            action="Repay"
            unit={symbol}
            decimals={ASSET_DECIMALS}
            max={debt < asset.balance ? debt : asset.balance}
            onSubmit={repay}
          />
        )}
        {collateral > 0n && (
          <AmountForm
            label="Withdraw HBAR collateral"
            action="Withdraw"
            unit="HBAR"
            decimals={TINYBAR_DECIMALS}
            max={collateral}
            onSubmit={withdraw}
          />
        )}
      </div>
    </section>
  );
};
