"use client";

import { useQuery } from "@tanstack/react-query";
import { useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { fetchTopicMessages, hashscanUrl } from "~~/utils/lending/mirrorNode";

/**
 * Audit topic for the shared deployment in deployedContracts.ts, so a fresh scaffold shows a live log.
 * Set NEXT_PUBLIC_AUDIT_TOPIC_ID to the topic your own relayer created.
 */
const SHARED_AUDIT_TOPICS: Record<number, string> = { 296: "0.0.10772847" };

/** Shape of the messages the relayer (`packages/foundry/scripts-js/hcsRelay.js`) publishes. */
type AuditEntry = {
  event: "Checked" | "Tripped" | "Reset";
  median?: string;
  agreeing?: number;
  sources?: { label: string; price: string; status: string }[];
  reason?: string;
  tx: string;
};

const parse = (raw: string): AuditEntry | undefined => {
  try {
    return JSON.parse(raw) as AuditEntry;
  } catch {
    return undefined;
  }
};

const EVENT_BADGE = { Checked: "badge-ghost", Tripped: "badge-error", Reset: "badge-success" } as const;

/**
 * Every guard decision, mirrored to a Hedera Consensus Service topic. HCS gives the log a consensus
 * timestamp and fixed order that nobody (including this app's operator) can rewrite, so a post-mortem
 * starts from a verifiable record of what each oracle reported.
 */
export const AuditLog = () => {
  const { targetNetwork } = useTargetNetwork();
  const topicId = process.env.NEXT_PUBLIC_AUDIT_TOPIC_ID || SHARED_AUDIT_TOPICS[targetNetwork.id];
  const { data, isLoading, error } = useQuery({
    queryKey: ["audit", targetNetwork.id, topicId],
    enabled: Boolean(topicId),
    refetchInterval: 15_000,
    queryFn: () => fetchTopicMessages(targetNetwork.id, topicId as string),
  });

  return (
    <section className="card bg-base-100 border border-base-300 shadow-md">
      <div className="card-body gap-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="card-title">Oracle audit log (HCS)</h2>
          {topicId && (
            <a
              className="link text-sm"
              href={hashscanUrl(targetNetwork.id, `topic/${topicId}`)}
              target="_blank"
              rel="noreferrer"
            >
              Topic {topicId}
            </a>
          )}
        </div>

        {!topicId && (
          <p className="text-sm m-0">
            Run <code className="bg-base-200 px-1 rounded">npm run foundry:relay</code> to create a topic and start
            mirroring guard events, then set{" "}
            <code className="bg-base-200 px-1 rounded">NEXT_PUBLIC_AUDIT_TOPIC_ID</code>.
          </p>
        )}
        {isLoading && <span className="loading loading-dots loading-sm" />}
        {error && <p className="text-sm text-error m-0">Could not load topic messages.</p>}

        <ul className="flex flex-col gap-2 m-0 p-0 list-none max-h-96 overflow-y-auto">
          {data?.map(message => {
            const entry = parse(message.message);
            if (!entry) return null;
            return (
              <li key={message.sequence_number} className="rounded-box bg-base-200 p-2 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-base-content/60">#{message.sequence_number}</span>
                  <span className={`badge badge-sm ${EVENT_BADGE[entry.event]}`}>{entry.event}</span>
                  {entry.median && <span className="font-mono">{entry.median}</span>}
                  {entry.reason && <span>{entry.reason}</span>}
                  <a
                    className="link text-base-content/60 ml-auto"
                    href={hashscanUrl(targetNetwork.id, `transaction/${entry.tx}`)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {new Date(Number(message.consensus_timestamp.split(".")[0]) * 1000).toLocaleString()}
                  </a>
                </div>
                {entry.sources && (
                  <div className="text-xs text-base-content/70 mt-1">
                    {entry.sources.map(s => `${s.label} ${s.price} (${s.status})`).join(" · ")}
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
};
