"use client";

import { AmountForm } from "./AmountForm";
import { useAccount, useBalance } from "wagmi";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import {
  ASSET_DECIMALS,
  TINYBAR_DECIMALS,
  WEIBAR_PER_TINYBAR,
  formatAsset,
  formatHbar,
  formatHealthFactor,
} from "~~/utils/lending/format";

export const BorrowerCard = () => {
  const { address } = useAccount();
  const market = useMarket();
  const asset = useHtsToken(market.assetAddress, market.marketAddress);
  const { data: hbar } = useBalance({ address });
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });
  const { collateral, debt, maxDebt, healthFactor } = market.position;

  const refresh = () => Promise.all([asset.refetch(), market.refetch()]);
  // Wallet balances come back in weibars (18 decimals); the market works in tinybars.
  const walletTinybars = hbar ? hbar.value / WEIBAR_PER_TINYBAR : 0n;
  const headroom = maxDebt > debt ? maxDebt - debt : 0n;
  const healthClass = healthFactor < 10n ** 18n ? "text-error" : healthFactor < 12n * 10n ** 17n ? "text-warning" : "";

  const depositCollateral = async (tinybars: bigint) => {
    await writeContractAsync({ functionName: "depositCollateral", value: tinybars * WEIBAR_PER_TINYBAR });
    await refresh();
  };
  const withdrawCollateral = async (tinybars: bigint) => {
    await writeContractAsync({ functionName: "withdrawCollateral", args: [tinybars] });
    await refresh();
  };
  const borrow = async (amount: bigint) => {
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
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-3">
        <h2 className="card-title">Borrow against HBAR</h2>

        <div className="grid grid-cols-2 gap-2 text-sm">
          <div>
            Collateral: <span className="font-semibold">{formatHbar(collateral)} HBAR</span>
          </div>
          <div>
            Debt:{" "}
            <span className="font-semibold">
              {formatAsset(debt)} {market.assetSymbol}
            </span>
          </div>
          <div>
            Borrow limit:{" "}
            <span className="font-semibold">
              {formatAsset(maxDebt)} {market.assetSymbol}
            </span>
          </div>
          <div>
            Health factor: <span className={`font-semibold ${healthClass}`}>{formatHealthFactor(healthFactor)}</span>
          </div>
        </div>

        <div className="divider my-0 text-xs">Collateral</div>
        <AmountForm
          action="Deposit"
          unit="HBAR"
          decimals={TINYBAR_DECIMALS}
          max={walletTinybars}
          onSubmit={depositCollateral}
        />
        <AmountForm
          action="Withdraw"
          unit="HBAR"
          decimals={TINYBAR_DECIMALS}
          max={collateral}
          onSubmit={withdrawCollateral}
        />

        <div className="divider my-0 text-xs">Loan</div>
        {asset.isAssociated === false ? (
          <button className="btn btn-sm btn-outline" onClick={asset.associate}>
            Associate {market.assetSymbol} to receive loans
          </button>
        ) : (
          <>
            <AmountForm
              action="Borrow"
              unit={market.assetSymbol}
              decimals={ASSET_DECIMALS}
              max={headroom}
              onSubmit={borrow}
            />
            <AmountForm
              action="Repay"
              unit={market.assetSymbol}
              decimals={ASSET_DECIMALS}
              max={debt < asset.balance ? debt : asset.balance}
              onSubmit={repay}
            />
          </>
        )}
        <p className="text-xs text-base-content/60 m-0">
          Borrowing and withdrawing collateral re-check the oracle guard; if the breaker is tripped they revert.
          Deposits and repayments always work.
        </p>
      </div>
    </section>
  );
};
