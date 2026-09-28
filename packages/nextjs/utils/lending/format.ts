import { formatUnits } from "viem";

export const USDC_DECIMALS = 6;
/** Contract storage and `msg.value` inside the Hedera EVM are in tinybars. */
export const TINYBAR_DECIMALS = 8;
/** JSON-RPC transaction values are in weibars (18 decimals): 1 tinybar = 10^10 weibar. */
export const WEIBAR_PER_TINYBAR = 10n ** 10n;
const SECONDS_PER_YEAR = 31_536_000n;

const number = (value: bigint, decimals: number, digits: number) =>
  Number(formatUnits(value, decimals)).toLocaleString(undefined, { maximumFractionDigits: digits });

export const formatPrice = (priceE18: bigint) => `$${Number(formatUnits(priceE18, 18)).toFixed(4)}`;
export const formatUsdc = (units: bigint) => number(units, USDC_DECIMALS, 2);
export const formatHbar = (tinybars: bigint) => number(tinybars, TINYBAR_DECIMALS, 2);
export const formatBps = (bps: bigint) => `${Number(bps) / 100}%`;
export const formatWadPercent = (wad: bigint) => `${(Number(formatUnits(wad, 18)) * 100).toFixed(2)}%`;
export const formatAprFromPerSecond = (ratePerSecondWad: bigint) =>
  formatWadPercent(ratePerSecondWad * SECONDS_PER_YEAR);

export const formatAge = (fromUnixSeconds: bigint | number, nowSeconds = Math.floor(Date.now() / 1000)) => {
  const age = nowSeconds - Number(fromUnixSeconds);
  if (age < 0) return "just now";
  if (age < 90) return `${age}s ago`;
  if (age < 5400) return `${Math.round(age / 60)}m ago`;
  if (age < 172_800) return `${Math.round(age / 3600)}h ago`;
  return `${Math.round(age / 86_400)}d ago`;
};

/** Health factor is WAD-scaled; `type(uint256).max` means no debt. */
export const formatHealthFactor = (hfWad: bigint) =>
  hfWad > 10n ** 30n ? "∞" : Number(formatUnits(hfWad, 18)).toFixed(2);
