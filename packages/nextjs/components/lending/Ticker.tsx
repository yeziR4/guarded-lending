"use client";

import type { ReactNode } from "react";
import { useBalance } from "wagmi";
import { SwitchTheme } from "~~/components/SwitchTheme";
import { useMarket } from "~~/hooks/lending/useMarket";
import { SOURCE_STATUS, TRIP_REASON, useOracleGuard } from "~~/hooks/lending/useOracleGuard";
import { usePythUpdate } from "~~/hooks/lending/usePythUpdate";
import { useDeployedContractInfo, useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import {
  POLLED,
  WEIBAR_PER_TINYBAR,
  formatAge,
  formatAprFromPerSecond,
  formatAsset,
  formatHbar,
  formatPrice,
  formatWadPercent,
} from "~~/utils/lending/format";
import { hashscanUrl } from "~~/utils/lending/mirrorNode";

const BAR = "bg-[#0b0f17] text-[#d7dce5] font-mono text-xs uppercase tracking-wide";
const LABEL = "text-[#f5a524]";
const STATUS_COLOR = [
  "text-[#34eeb6]",
  "text-[#ff6b6b]",
  "text-[#f5a524]",
  "text-[#ff6b6b]",
  "text-[#ff6b6b]",
] as const;

const Item = ({ label, children }: { label: string; children: ReactNode }) => (
  <span className="flex items-center gap-2 px-5 whitespace-nowrap border-r border-white/10">
    <span className={LABEL}>{label}</span>
    {children}
  </span>
);

/** Scrolling oracle feed under the header. */
export const OracleTicker = () => {
  const guard = useOracleGuard();
  const pyth = usePythUpdate();
  const { data: pythSource } = useDeployedContractInfo({ contractName: "PythSource" });
  const tripped = guard.tripReason !== 0;

  const items = (
    <>
      {guard.sources.map((source, i) => {
        const isPyth = source.address?.toLowerCase() === pythSource?.address.toLowerCase();
        const pullWithoutKey = isPyth && !pyth.configured && source.status !== 0;
        return (
          <Item key={i} label={source.label ?? `Source ${i + 1}`}>
            <span>{source.priceE18 > 0n ? formatPrice(source.priceE18) : "–"}</span>
            <span className={pullWithoutKey ? "text-white/50" : STATUS_COLOR[source.status]}>
              {pullWithoutKey ? "● pull oracle · needs API key" : `● ${SOURCE_STATUS[source.status]}`}
            </span>
            {!pullWithoutKey && source.updatedAt > 0n && (
              <span className="text-white/50">{formatAge(source.updatedAt)}</span>
            )}
          </Item>
        );
      })}
      <Item label="Median">{guard.median > 0n ? formatPrice(guard.median) : "–"}</Item>
      <Item label="Agree">
        <span
          className={guard.quorum !== undefined && guard.agreeing >= guard.quorum ? STATUS_COLOR[0] : STATUS_COLOR[1]}
        >
          {guard.agreeing.toString()}/{guard.sources.length} (need {guard.quorum?.toString() ?? "–"})
        </span>
      </Item>
      <Item label="Breaker">
        <span className={tripped ? STATUS_COLOR[1] : STATUS_COLOR[0]}>
          {tripped ? `Tripped · ${TRIP_REASON[guard.tripReason]}` : "Closed"}
        </span>
      </Item>
      <Item label="Last accepted">
        {guard.lastPrice ? formatPrice(guard.lastPrice) : "–"}
        {guard.lastPriceAt ? <span className="text-white/50">{formatAge(guard.lastPriceAt)}</span> : null}
      </Item>
    </>
  );

  return (
    <div className={`${BAR} w-full overflow-hidden border-b border-white/10`} aria-label="Oracle guard feed">
      <div className="ticker-track flex w-max py-2">
        {items}
        {items}
      </div>
    </div>
  );
};

/** Long-zero EVM addresses map to Hedera entity ids, e.g. 0x…a431e9 -> 0.0.10760681. */
const toEntityId = (address: string) => `0.0.${BigInt(address).toString()}`;

/** Fixed market and Guardian status bar at the bottom of the screen. */
export const MarketBar = () => {
  const market = useMarket();
  const { targetNetwork } = useTargetNetwork();
  const { data: guardian } = useDeployedContractInfo({ contractName: "Guardian" });
  const { data: funding } = useBalance({ address: guardian?.address });
  const { data: runs } = useScaffoldReadContract({ contractName: "Guardian", functionName: "runs", ...POLLED });
  const { data: nextRunAt } = useScaffoldReadContract({
    contractName: "Guardian",
    functionName: "nextRunAt",
    ...POLLED,
  });
  const { data: schedule } = useScaffoldReadContract({
    contractName: "Guardian",
    functionName: "nextSchedule",
    ...POLLED,
  });

  const hoursToRun = nextRunAt ? Math.max(0, (Number(nextRunAt) - Date.now() / 1000) / 3600) : undefined;
  const scheduled = schedule !== undefined && BigInt(schedule) !== 0n;

  return (
    <div className={`${BAR} fixed bottom-0 left-0 z-20 w-full border-t border-white/10`}>
      <div className="flex items-center overflow-x-auto py-2">
        <Item label="Supplied">{`${formatAsset(market.totalAssets)} ${market.assetSymbol}`}</Item>
        <Item label="Borrowed">{`${formatAsset(market.totalBorrows)} ${market.assetSymbol}`}</Item>
        <Item label="Util">{formatWadPercent(market.utilization)}</Item>
        <Item label="APR">{formatAprFromPerSecond(market.borrowRatePerSecond)}</Item>
        <Item label="Collateral">{`${formatHbar(market.totalCollateral)} HBAR`}</Item>
        <Item label="Guardian (HSS)">
          {scheduled ? (
            <a
              className="underline decoration-dotted hover:text-white"
              href={hashscanUrl(targetNetwork.id, `schedule/${toEntityId(schedule)}`)}
              target="_blank"
              rel="noreferrer"
            >
              {hoursToRun !== undefined ? `next run in ${hoursToRun.toFixed(1)}h` : "scheduled"}
            </a>
          ) : (
            <span className={STATUS_COLOR[2]}>stopped</span>
          )}
          <span className="text-white/50">
            {runs?.toString() ?? "–"} runs · {funding ? formatHbar(funding.value / WEIBAR_PER_TINYBAR) : "–"} HBAR
          </span>
        </Item>
        <span className="ml-auto px-4 normal-case">
          <SwitchTheme />
        </span>
      </div>
    </div>
  );
};
