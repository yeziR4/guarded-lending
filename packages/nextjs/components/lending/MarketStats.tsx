"use client";

import { useMarket } from "~~/hooks/lending/useMarket";
import { formatAprFromPerSecond, formatHbar, formatUsdc, formatWadPercent } from "~~/utils/lending/format";

export const MarketStats = () => {
  const market = useMarket();

  return (
    <div className="stats stats-vertical md:stats-horizontal w-full bg-base-100 border border-base-300 shadow-md">
      <div className="stat">
        <div className="stat-title">Supplied</div>
        <div className="stat-value text-2xl">{formatUsdc(market.totalAssets)}</div>
        <div className="stat-desc">USDC incl. accrued interest</div>
      </div>
      <div className="stat">
        <div className="stat-title">Borrowed</div>
        <div className="stat-value text-2xl">{formatUsdc(market.totalBorrows)}</div>
        <div className="stat-desc">Utilization {formatWadPercent(market.utilization)}</div>
      </div>
      <div className="stat">
        <div className="stat-title">Borrow APR</div>
        <div className="stat-value text-2xl">{formatAprFromPerSecond(market.borrowRatePerSecond)}</div>
        <div className="stat-desc">2% base + 20% × utilization</div>
      </div>
      <div className="stat">
        <div className="stat-title">Collateral</div>
        <div className="stat-value text-2xl">{formatHbar(market.totalCollateral)}</div>
        <div className="stat-desc">HBAR locked</div>
      </div>
    </div>
  );
};
