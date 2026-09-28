"use client";

import { SOURCE_STATUS, TRIP_REASON, useOracleGuard } from "~~/hooks/lending/useOracleGuard";
import { usePythUpdate } from "~~/hooks/lending/usePythUpdate";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { formatAge, formatBps, formatPrice } from "~~/utils/lending/format";

const STATUS_BADGE = ["badge-success", "badge-error", "badge-warning", "badge-error", "badge-error"] as const;

export const OraclePanel = () => {
  const guard = useOracleGuard();
  const { pushUpdate, isPending: isPythPending } = usePythUpdate();
  const { writeContractAsync: writeGuard, isPending: isPoking } = useScaffoldWriteContract({
    contractName: "OracleGuard",
  });

  const tripped = guard.tripReason !== 0;
  const quorumMet = guard.quorum !== undefined && guard.agreeing >= guard.quorum;

  const poke = async () => {
    await writeGuard({ functionName: "poke" });
    await guard.refetch();
  };

  return (
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="card-title">HBAR/USD oracle guard</h2>
            <p className="text-sm text-base-content/70 m-0">
              Median of independent providers. {guard.quorum?.toString() ?? "–"} must agree within{" "}
              {guard.maxDeviationBps !== undefined ? formatBps(guard.maxDeviationBps) : "–"} or the market stops
              pricing.
            </p>
          </div>
          <div className={`badge badge-lg ${tripped ? "badge-error" : "badge-success"}`}>
            {tripped ? `Breaker tripped: ${TRIP_REASON[guard.tripReason]}` : "Breaker closed"}
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="table table-sm">
            <thead>
              <tr>
                <th>Source</th>
                <th className="text-right">Price</th>
                <th className="text-right">Updated</th>
                <th className="text-right">Status</th>
              </tr>
            </thead>
            <tbody>
              {/* Source order is fixed in the guard's constructor, so the index is a stable key. */}
              {guard.sources.map((source, index) => (
                <tr key={index}>
                  <td className="font-medium">{source.label ?? `Source ${index + 1}`}</td>
                  <td className="text-right font-mono">{source.priceE18 > 0n ? formatPrice(source.priceE18) : "–"}</td>
                  <td className="text-right">{source.updatedAt > 0n ? formatAge(source.updatedAt) : "–"}</td>
                  <td className="text-right">
                    <span className={`badge badge-sm ${STATUS_BADGE[source.status]}`}>
                      {SOURCE_STATUS[source.status]}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="stats stats-vertical sm:stats-horizontal bg-base-200">
          <div className="stat">
            <div className="stat-title">Median now</div>
            <div className="stat-value text-2xl font-mono">{guard.median > 0n ? formatPrice(guard.median) : "–"}</div>
            <div className={`stat-desc ${quorumMet ? "text-success" : "text-error"}`}>
              {guard.agreeing.toString()} of {guard.sources.length} agree (need {guard.quorum?.toString() ?? "–"})
            </div>
          </div>
          <div className="stat">
            <div className="stat-title">Last accepted</div>
            <div className="stat-value text-2xl font-mono">{guard.lastPrice ? formatPrice(guard.lastPrice) : "–"}</div>
            <div className="stat-desc">{guard.lastPriceAt ? formatAge(guard.lastPriceAt) : "never"}</div>
          </div>
        </div>

        <div className="card-actions justify-end">
          <button className="btn btn-sm btn-outline" onClick={pushUpdate} disabled={isPythPending}>
            {isPythPending && <span className="loading loading-spinner loading-xs" />}
            Refresh Pyth
          </button>
          <button className="btn btn-sm btn-primary" onClick={poke} disabled={isPoking}>
            {isPoking && <span className="loading loading-spinner loading-xs" />}
            Run check (poke)
          </button>
        </div>
      </div>
    </section>
  );
};
