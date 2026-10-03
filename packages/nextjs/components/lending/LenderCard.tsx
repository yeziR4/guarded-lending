"use client";

import { AmountForm } from "./AmountForm";
import { useAccount } from "wagmi";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { useDeployedContractInfo, useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { ASSET_DECIMALS, formatAsset } from "~~/utils/lending/format";

export const LenderCard = () => {
  const { address } = useAccount();
  const market = useMarket();
  const asset = useHtsToken(market.assetAddress, market.marketAddress);
  const shares = useHtsToken(market.shareToken, market.marketAddress);
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });
  const { data: faucet } = useDeployedContractInfo({ contractName: "TestStablecoin" });
  const { writeContractAsync: writeFaucet } = useScaffoldWriteContract({ contractName: "TestStablecoin" });

  const refresh = () => Promise.all([asset.refetch(), shares.refetch(), market.refetch()]);

  const claim = async () => {
    await asset.ensureAssociated();
    await writeFaucet({ functionName: "claim" });
    await asset.refetch();
  };

  const supply = async (amount: bigint) => {
    await shares.ensureAssociated();
    await asset.ensureAllowance(amount);
    await writeContractAsync({ functionName: "supply", args: [amount] });
    await refresh();
  };

  const withdraw = async (amount: bigint) => {
    await shares.ensureAllowance(amount);
    await writeContractAsync({ functionName: "withdraw", args: [amount] });
    await refresh();
  };

  const symbol = market.assetSymbol;
  const empty = asset.balance === 0n && shares.balance === 0n;

  return (
    <section className="card bg-base-100 shadow-sm">
      <div className="card-body gap-3">
        <h2 className="card-title">Lend {symbol}</h2>
        <p className="text-sm text-base-content/70 m-0">
          Supplying mints <span className="font-semibold">{market.shareSymbol}</span>, a Hedera token you redeem for
          your {symbol} plus interest.
        </p>

        {!address && <p className="text-sm font-medium m-0">Connect a wallet on Hedera testnet to start.</p>}

        {address && faucet && (
          <button className={`btn ${empty ? "btn-primary" : "btn-ghost btn-sm"}`} onClick={claim}>
            {empty ? `Start: get 1,000 ${symbol}` : `Get 1,000 more ${symbol}`}
          </button>
        )}

        {address && (
          <p className="text-xs text-base-content/60 m-0">
            Wallet {formatAsset(asset.balance)} {symbol} · Supplied {formatAsset(shares.balance)} {market.shareSymbol}
          </p>
        )}

        {asset.balance > 0n && (
          <AmountForm
            label={`Supply ${symbol}`}
            action="Supply"
            unit={symbol}
            decimals={ASSET_DECIMALS}
            max={asset.balance}
            onSubmit={supply}
          />
        )}

        {shares.balance > 0n && (
          <AmountForm
            label="Withdraw"
            action="Withdraw"
            unit={market.shareSymbol}
            decimals={ASSET_DECIMALS}
            max={shares.balance}
            onSubmit={withdraw}
          />
        )}
      </div>
    </section>
  );
};
