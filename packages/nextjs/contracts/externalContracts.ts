/**
 * This file contains external contract definitions (contracts not deployed by this project).
 * Add entries here to interact with pre-deployed contracts on any supported chain.
 */
import { erc20Abi } from "viem";
import { GenericContractsDeclaration } from "~~/utils/scaffold-hbar/contract";

/** IHRC-719: HTS tokens expose `associate()` so an EVM wallet can opt in to holding them. */
const hrc719Abi = [
  {
    type: "function",
    name: "associate",
    inputs: [],
    outputs: [{ name: "", type: "int64" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isAssociated",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;

const htsTokenAbi = [...erc20Abi, ...hrc719Abi] as const;

const pythAbi = [
  {
    type: "function",
    name: "getUpdateFee",
    inputs: [{ name: "updateData", type: "bytes[]" }],
    outputs: [{ name: "feeAmount", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "updatePriceFeeds",
    inputs: [{ name: "updateData", type: "bytes[]" }],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

const PYTH = "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729";

const externalContracts = {
  296: {
    Pyth: { address: PYTH, abi: pythAbi },
  },
  295: {
    Pyth: { address: PYTH, abi: pythAbi },
  },
} as const;

export { htsTokenAbi };
export default externalContracts satisfies GenericContractsDeclaration;
