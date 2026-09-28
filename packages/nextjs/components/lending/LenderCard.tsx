"use client";

import { AmountForm } from "./AmountForm";
import { useHtsToken } from "~~/hooks/lending/useHtsToken";
import { useMarket } from "~~/hooks/lending/useMarket";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { USDC_DECIMALS, formatUsdc } from "~~/utils/lending/format";

export const LenderCard = () => {
  const market = useMarket();
  const usdc = useHtsToken(market.usdcAddress, market.marketAddress);
  const shares = useHtsToken(market.shareToken, market.marketAddress);
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "LendingMarket" });

  const refresh = () => Promise.all([usdc.refetch(), shares.refetch(), market.refetch()]);

  const supply = async (amount: bigint) => {
    await usdc.ensureAllowance(amount);
    await writeContractAsync({ functionName: "supply", args: [amount] });
    await refresh();
  };

  const withdraw = async (amount: bigint) => {
    await shares.ensureAllowance(amount);
    await writeContractAsync({ functionName: "withdraw", args: [amount] });
    await refresh();
  };

  return (
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-3">
        <h2 className="card-title">Lend USDC</h2>
        <p className="text-sm text-base-content/70 m-0">
          Deposits mint <span className="font-semibold">gUSDC</span>, a native HTS token that accrues borrower interest.
        </p>

        {usdc.isAssociated === false ? (
          <button className="btn btn-sm btn-outline" onClick={usdc.associate}>
            Associate USDC with your account
          </button>
        ) : (
          <>
            <div className="text-xs text-base-content/60">Wallet: {formatUsdc(usdc.balance)} USDC</div>
            <AmountForm
              action="Supply"
              unit="USDC"
              decimals={USDC_DECIMALS}
              max={usdc.balance}
              disabled={shares.isAssociated === false}
              onSubmit={supply}
            />
          </>
        )}

        {shares.isAssociated === false ? (
          <button className="btn btn-sm btn-outline" onClick={shares.associate}>
            Associate gUSDC to receive deposit shares
          </button>
        ) : (
          <>
            <div className="text-xs text-base-content/60">Your shares: {formatUsdc(shares.balance)} gUSDC</div>
            <AmountForm
              action="Withdraw"
              unit="gUSDC"
              decimals={USDC_DECIMALS}
              max={shares.balance}
              onSubmit={withdraw}
            />
          </>
        )}

        <a className="link text-xs" href="https://faucet.circle.com" target="_blank" rel="noreferrer">
          Get testnet USDC (Circle faucet, Hedera testnet)
        </a>
      </div>
    </section>
  );
};
