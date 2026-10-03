import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-hbar";
import { WEIBAR_PER_TINYBAR } from "~~/utils/lending/format";

type UpdateResponse = { updateData?: `0x${string}`[]; error?: string };

/**
 * Pyth is a pull oracle: it is fresh only right after someone pushes a signed update. When the server has
 * a Pyth API key, `refresh()` pushes one; without a key it does nothing and the guard runs on the push feeds.
 */
export const usePythUpdate = () => {
  const publicClient = usePublicClient();
  const { data: pyth } = useDeployedContractInfo({ contractName: "Pyth" });
  const { data: priceId } = useScaffoldReadContract({
    contractName: "PythSource",
    functionName: "PRICE_ID",
    watch: false,
  });
  const { writeContractAsync } = useScaffoldWriteContract({ contractName: "Pyth" });

  const fetchUpdate = async () => {
    const response = await fetch(`/api/pyth-update?id=${priceId}`);
    return { status: response.status, body: (await response.json()) as UpdateResponse };
  };

  // 501 means no PYTH_API_KEY on the server.
  const { data: configured = false } = useQuery({
    queryKey: ["pyth-configured", priceId],
    enabled: Boolean(priceId),
    staleTime: Infinity,
    queryFn: async () => (await fetchUpdate()).status !== 501,
  });

  const refresh = async () => {
    if (!configured || !pyth || !publicClient) return;
    const { body } = await fetchUpdate();
    if (!body.updateData) throw new Error(body.error ?? "Pyth update unavailable");

    const fee = await publicClient.readContract({
      address: pyth.address,
      abi: pyth.abi,
      functionName: "getUpdateFee",
      args: [body.updateData],
    });
    await writeContractAsync({
      functionName: "updatePriceFeeds",
      args: [body.updateData],
      value: fee * WEIBAR_PER_TINYBAR,
    });
  };

  return { configured, refresh };
};
