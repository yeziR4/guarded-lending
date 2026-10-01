"use client";

import type { NextPage } from "next";
import { BorrowerCard } from "~~/components/lending/BorrowerCard";
import { GuardianCard } from "~~/components/lending/GuardianCard";
import { LenderCard } from "~~/components/lending/LenderCard";
import { LiquidationsCard } from "~~/components/lending/LiquidationsCard";
import { MarketStats } from "~~/components/lending/MarketStats";
import { OraclePanel } from "~~/components/lending/OraclePanel";

const Home: NextPage = () => {
  return (
    <div className="flex flex-col items-center grow">
      <div className="hedera-gradient dark:bg-none dark:bg-hedera-charcoal w-full py-12 px-5">
        <div className="max-w-3xl mx-auto text-center text-white">
          <h1 className="text-3xl md:text-4xl font-bold mb-3">Guarded Lending</h1>
          <p className="text-white/85 m-0">
            A stablecoin lending market with HBAR collateral that prices through three independent oracles and stops
            instead of trusting a forged price. The failure mode behind the July 2026 Bonzo Lend exploit, handled.
          </p>
        </div>
      </div>

      <div className="w-full max-w-6xl mx-auto px-5 -mt-6 pb-24 flex flex-col gap-6">
        <MarketStats />
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <div className="lg:col-span-3 flex flex-col gap-6">
            <OraclePanel />
            <GuardianCard />
            <LiquidationsCard />
          </div>
          <div className="lg:col-span-2 flex flex-col gap-6">
            <LenderCard />
            <BorrowerCard />
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
