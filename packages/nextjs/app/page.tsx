"use client";

import type { NextPage } from "next";
import { BorrowerCard } from "~~/components/lending/BorrowerCard";
import { LenderCard } from "~~/components/lending/LenderCard";
import { LiquidationsCard } from "~~/components/lending/LiquidationsCard";
import { MarketBar, OracleTicker } from "~~/components/lending/Ticker";

const STEPS = ["Get tUSD", "Supply it to earn", "Or lock HBAR", "Borrow against it"];

const Home: NextPage = () => {
  return (
    <div className="flex flex-col items-center grow pb-16">
      <OracleTicker />

      <div className="hedera-gradient dark:bg-none dark:bg-hedera-charcoal w-full py-10 px-5">
        <div className="max-w-3xl mx-auto text-center text-white">
          <h1 className="text-3xl md:text-4xl font-bold mb-3">Guarded Lending</h1>
          <p className="text-white/85 m-0">
            Borrow against HBAR, priced by Chainlink, Supra and Pyth together. If they disagree, the market stops
            instead of trusting a forged price.
          </p>
          <ol className="flex flex-wrap justify-center gap-2 mt-5 p-0 list-none text-sm">
            {STEPS.map((step, i) => (
              <li key={step} className="badge badge-lg bg-white/15 border-0 text-white">
                {i + 1}. {step}
              </li>
            ))}
          </ol>
        </div>
      </div>

      <div className="w-full max-w-5xl mx-auto px-5 mt-8 grid grid-cols-1 md:grid-cols-2 gap-6">
        <LenderCard />
        <BorrowerCard />
        <div className="md:col-span-2">
          <LiquidationsCard />
        </div>
      </div>

      <MarketBar />
    </div>
  );
};

export default Home;
