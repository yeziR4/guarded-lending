"use client";

import { HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { useQuery } from "@tanstack/react-query";
import { useAccount } from "wagmi";
import { useTargetNetwork } from "~~/hooks/scaffold-hbar";
import { POLL_MS } from "~~/utils/lending/format";
import { chainIdToHederaNetwork, getHederaAccountId } from "~~/utils/scaffold-hbar";

/**
 * A fresh EVM address has no Hedera account until it first receives HBAR, and every transaction from it
 * fails with "Sender account not found". Explain that instead of letting the wallet show the raw error.
 */
export const AccountNotice = () => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const { data: accountId, isFetched } = useQuery({
    queryKey: ["hedera-account", address, targetNetwork.id],
    enabled: Boolean(address),
    queryFn: () => getHederaAccountId(address as string, chainIdToHederaNetwork(targetNetwork.id)),
    refetchInterval: query => (query.state.data ? false : POLL_MS),
  });

  if (!address || !isFetched || accountId) return null;

  return (
    <div className="md:col-span-2 rounded-box bg-warning/15 p-4 text-sm">
      <p className="font-semibold m-0">This address is not on Hedera testnet yet.</p>
      <p className="m-0 mt-1">
        Hedera creates an account the first time an address receives HBAR. Send some test HBAR to it, and this page
        unlocks on its own: <HederaPortalFaucet variant="link" label="Hedera portal faucet" showIcon={false} />
      </p>
    </div>
  );
};
