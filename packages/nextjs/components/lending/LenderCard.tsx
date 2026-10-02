"use client";

import { AmountForm } from "./AmountForm";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { useDeployedContractInfo, useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { ASSET_DECIMALS, formatAsset } from "~~/utils/lending/format";

export const LenderCard = () => {
  const market = useMarket();
  const asset = useHtsToken(market.assetAddress, market.marketAddress);
  const shares = useHtsToken(market.shareToken, market.marketAddress);
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });
  const { data: faucet } = useDeployedContractInfo({ contractName: "TestStablecoin" });
  const { writeContractAsync: writeFaucet } = useScaffoldWriteContract({ contractName: "TestStablecoin" });

  const refresh = () => Promise.all([asset.refetch(), shares.refetch(), market.refetch()]);

  const supply = async (amount: bigint) => {
    await asset.ensureAllowance(amount);
    await writeContractAsync({ functionName: "supply", args: [amount] });
    await refresh();
  };

  const withdraw = async (amount: bigint) => {
    await shares.ensureAllowance(amount);
    await writeContractAsync({ functionName: "withdraw", args: [amount] });
    await refresh();
  };

  const claim = async () => {
    await writeFaucet({ functionName: "claim" });
    await asset.refetch();
  };

  return (
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-3">
        <h2 className="card-title">Lend {market.assetSymbol}</h2>
        <p className="text-sm text-base-content/70 m-0">
          Deposits mint <span className="font-semibold">{market.shareSymbol}</span>, a native HTS token that accrues
          borrower interest.
        </p>

        {asset.isAssociated === false ? (
          <button className="btn btn-sm btn-outline" onClick={asset.associate}>
            Associate {market.assetSymbol} with your account
          </button>
        ) : (
          <>
            <div className="text-xs text-base-content/60">
              Wallet: {formatAsset(asset.balance)} {market.assetSymbol}
            </div>
            <AmountForm
              action="Supply"
              unit={market.assetSymbol}
              decimals={ASSET_DECIMALS}
              max={asset.balance}
              disabled={shares.isAssociated === false}
              onSubmit={supply}
            />
          </>
        )}

        {shares.isAssociated === false ? (
          <button className="btn btn-sm btn-outline" onClick={shares.associate}>
            Associate {market.shareSymbol} to receive deposit shares
          </button>
        ) : (
          <>
            <div className="text-xs text-base-content/60">
              Your shares: {formatAsset(shares.balance)} {market.shareSymbol}
            </div>
            <AmountForm
              action="Withdraw"
              unit={market.shareSymbol}
              decimals={ASSET_DECIMALS}
              max={shares.balance}
              onSubmit={withdraw}
            />
          </>
        )}

        {faucet?.address ? (
          <button className="btn btn-sm btn-ghost" onClick={claim}>
            Get 1,000 {market.assetSymbol} (testnet faucet)
          </button>
        ) : (
          <a className="link text-xs" href="https://faucet.circle.com" target="_blank" rel="noreferrer">
            Get testnet USDC (Circle faucet)
          </a>
        )}
      </div>
    </section>
  );
};
