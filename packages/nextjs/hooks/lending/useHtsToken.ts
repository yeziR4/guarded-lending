import { Address } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { htsTokenAbi } from "~~/contracts/externalContracts";
import { useTransactor } from "~~/hooks/scaffold-hbar";
import { POLL_MS } from "~~/utils/lending/format";

/**
 * Balance, allowance and association for an HTS token. Hedera accounts must `associate()` (IHRC-719)
 * before receiving a token; `isAssociated()` reads the caller's status, so it is sent `from` the account.
 */
export const useHtsToken = (token: Address | undefined, spender: Address | undefined) => {
  const { address: account } = useAccount();
  const enabled = Boolean(token && account);
  const writeTx = useTransactor();
  const { writeContractAsync } = useWriteContract();

  const balance = useReadContract({
    address: token,
    abi: htsTokenAbi,
    functionName: "balanceOf",
    args: account ? [account] : undefined,
    query: { enabled, refetchInterval: POLL_MS },
  });
  const allowance = useReadContract({
    address: token,
    abi: htsTokenAbi,
    functionName: "allowance",
    args: account && spender ? [account, spender] : undefined,
    query: { enabled: enabled && Boolean(spender), refetchInterval: POLL_MS },
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
    refetch: () => Promise.all([balance.refetch(), allowance.refetch()]),
  };
};
