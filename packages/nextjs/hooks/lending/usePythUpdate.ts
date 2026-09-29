import { useState } from "react";
import { usePublicClient } from "wagmi";
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { WEIBAR_PER_TINYBAR } from "~~/utils/lending/format";
import { notification } from "~~/utils/scaffold-hbar";

/** Pushes the latest signed Pyth update on-chain; update data comes from `/api/pyth-update`. */
export const usePythUpdate = () => {
  const [isFetching, setIsFetching] = useState(false);
  const publicClient = usePublicClient();
  const { data: pyth } = useDeployedContractInfo({ contractName: "Pyth" });
  const { data: priceId } = useScaffoldReadContract({
    contractName: "PythSource",
    functionName: "PRICE_ID",
    watch: false,
  });
  const { writeContractAsync, isPending } = useScaffoldWriteContract({ contractName: "Pyth" });

  const pushUpdate = async () => {
    if (!priceId || !pyth || !publicClient) return;
    setIsFetching(true);
    try {
      const response = await fetch(`/api/pyth-update?id=${priceId}`);
      const body = (await response.json()) as { updateData?: `0x${string}`[]; error?: string };
      if (!response.ok || !body.updateData) throw new Error(body.error ?? `Update route responded ${response.status}`);
      const updateData = body.updateData;

      const fee = await publicClient.readContract({
        address: pyth.address,
        abi: pyth.abi,
        functionName: "getUpdateFee",
        args: [updateData],
      });
      await writeContractAsync({
        functionName: "updatePriceFeeds",
        args: [updateData],
        value: fee * WEIBAR_PER_TINYBAR,
      });
    } catch (error) {
      notification.error(error instanceof Error ? error.message : "Pyth update failed");
    } finally {
      setIsFetching(false);
    }
  };

  return { pushUpdate, isPending: isFetching || isPending };
};
