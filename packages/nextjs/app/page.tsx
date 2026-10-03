"use client";

import type { NextPage } from "next";
import { AccountNotice } from "~~/components/lending/AccountNotice";
import { BorrowerCard } from "~~/components/lending/BorrowerCard";
import { LenderCard } from "~~/components/lending/LenderCard";
import { LiquidationsCard } from "~~/components/lending/LiquidationsCard";
import { MarketBar, OracleTicker } from "~~/components/lending/Ticker";

const STEPS = ["Get tUSD", "Supply it to earn", "Or lock HBAR", "Borrow against it"];

const scrollToMarket = () => document.getElementById("market")?.scrollIntoView({ behavior: "smooth" });

const Home: NextPage = () => {
  return (
    <div className="flex flex-col items-center grow pb-16">
      <OracleTicker />

      <section className="hedera-gradient dark:bg-none dark:bg-hedera-charcoal w-full min-h-[calc(100vh-8rem)] flex items-center px-5">
        <div className="fade-up max-w-3xl mx-auto text-center text-white">
          <h1 className="text-4xl md:text-6xl font-bold mb-5">Guarded Lending</h1>
          <p className="text-lg md:text-xl text-white/85 m-0">
            Borrow against HBAR, priced by Chainlink, Supra and Pyth together. If they disagree, the market stops
            instead of trusting a forged price.
          </p>
          <div className="flex flex-wrap justify-center gap-x-6 gap-y-2 mt-8 text-white/90">
            {STEPS.map((step, i) => (
              <button key={step} className="cursor-pointer hover:text-white transition-colors" onClick={scrollToMarket}>
                <span className="font-semibold text-white">{i + 1}</span> {step}
              </button>
            ))}
          </div>
          <button
            className="btn btn-lg mt-10 border-0 bg-white text-hedera-violet hover:bg-white/90"
            onClick={scrollToMarket}
          >
            Get started
          </button>
        </div>
      </section>

      <div
        id="market"
        className="w-full max-w-5xl mx-auto px-5 pt-12 min-h-screen scroll-mt-20 grid grid-cols-1 md:grid-cols-2 content-start gap-6"
      >
        <AccountNotice />
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
