import { Address } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { htsTokenAbi } from "~~/contracts/externalContracts";
import { useTransactor } from "~~/hooks/scaffold-hbar";

const POLL = { refetchInterval: 10_000 } as const;

/**
 * Balance, allowance and association state for an HTS fungible token held by the connected wallet.
 *
 * On Hedera an account must be associated with a token before it can receive it. HTS tokens expose
 * IHRC-719 `associate()` on their EVM facade so a MetaMask-style wallet can opt in with one call.
 * `isAssociated()` reads the caller's own status, so the read is sent `from` the connected account.
 */
export const useHtsToken = (token: Address | undefined, spender: Address | undefined) => {
  const { address: account } = useAccount();
  const enabled = Boolean(token && account);
  const writeTx = useTransactor();
  const { writeContractAsync, isPending } = useWriteContract();

  const balance = useReadContract({
    address: token,
    abi: htsTokenAbi,
    functionName: "balanceOf",
    args: account ? [account] : undefined,
    query: { enabled, ...POLL },
  });
  const allowance = useReadContract({
    address: token,
    abi: htsTokenAbi,
    functionName: "allowance",
    args: account && spender ? [account, spender] : undefined,
    query: { enabled: enabled && Boolean(spender), ...POLL },
  });
  const associated = useReadContract({
    address: token,
    abi: htsTokenAbi,
    functionName: "isAssociated",
    account,
    query: { enabled },
  });

  const associate = async () => {
    if (!token) return;
    await writeTx(() => writeContractAsync({ address: token, abi: htsTokenAbi, functionName: "associate" }));
    await associated.refetch();
  };

  /** Approves exactly `amount` if the current allowance is lower. */
  const ensureAllowance = async (amount: bigint) => {
    if (!token || !spender || (allowance.data ?? 0n) >= amount) return;
    await writeTx(() =>
      writeContractAsync({ address: token, abi: htsTokenAbi, functionName: "approve", args: [spender, amount] }),
    );
    await allowance.refetch();
  };

  return {
    balance: balance.data ?? 0n,
    isAssociated: associated.data,
    associate,
    ensureAllowance,
    isPending,
    refetch: () => Promise.all([balance.refetch(), allowance.refetch()]),
  };
};
