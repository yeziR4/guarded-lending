"use client";

import { useBalance } from "wagmi";
import { useDeployedContractInfo, useScaffoldReadContract, useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { WEIBAR_PER_TINYBAR, formatHbar } from "~~/utils/lending/format";
import { hashscanUrl } from "~~/utils/lending/mirrorNode";

const POLL = { watch: false, query: { refetchInterval: 15_000 } } as const;

/** Long-zero EVM addresses (0x000…00a431e9) map to Hedera entity ids (0.0.10760681). */
const toEntityId = (address: string) => `0.0.${BigInt(address).toString()}`;

export const GuardianCard = () => {
  const { targetNetwork } = useTargetNetwork();
  const { data: guardian } = useDeployedContractInfo({ contractName: "Guardian" });
  const { data: balance } = useBalance({ address: guardian?.address, query: { refetchInterval: 15_000 } });
  const { data: runs } = useScaffoldReadContract({ contractName: "Guardian", functionName: "runs", ...POLL });
  const { data: nextRunAt } = useScaffoldReadContract({ contractName: "Guardian", functionName: "nextRunAt", ...POLL });
  const { data: nextSchedule } = useScaffoldReadContract({
    contractName: "Guardian",
    functionName: "nextSchedule",
    ...POLL,
  });
  const { data: interval } = useScaffoldReadContract({
    contractName: "Guardian",
    functionName: "INTERVAL",
    watch: false,
  });

  const running = nextRunAt !== undefined && nextRunAt > 0n;
  const minutesToRun = running ? Math.ceil((Number(nextRunAt) - Date.now() / 1000) / 60) : 0;

  return (
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-3">
        <div className="flex items-center justify-between">
          <h2 className="card-title">Guardian</h2>
          <span className={`badge ${running ? "badge-success" : "badge-warning"}`}>
            {running ? "Scheduled" : "Stopped"}
          </span>
        </div>
        <p className="text-sm text-base-content/70 m-0">
          Re-runs the oracle check and accrues interest every {interval ? `${Number(interval) / 60} min` : "…"}, booking
          its own next run with the Hedera Schedule Service (HIP-1215). No off-chain keeper.
        </p>
        <ul className="text-sm space-y-1 m-0 p-0 list-none">
          <li>
            Completed runs: <span className="font-semibold">{runs?.toString() ?? "–"}</span>
          </li>
          {running && (
            <li>
              Next run: {new Date(Number(nextRunAt) * 1000).toLocaleTimeString()}{" "}
              <span className="text-base-content/60">
                {minutesToRun > 0 ? `(in ${minutesToRun} min)` : "(due, waiting for network)"}
              </span>
            </li>
          )}
          <li>
            Funding:{" "}
            <span className="font-semibold">{balance ? formatHbar(balance.value / WEIBAR_PER_TINYBAR) : "–"} HBAR</span>
          </li>
        </ul>
        {nextSchedule && BigInt(nextSchedule) !== 0n && (
          <a
            className="link text-sm"
            href={hashscanUrl(targetNetwork.id, `schedule/${toEntityId(nextSchedule)}`)}
            target="_blank"
            rel="noreferrer"
          >
            Schedule {toEntityId(nextSchedule)} on HashScan
          </a>
        )}
      </div>
    </section>
  );
};
