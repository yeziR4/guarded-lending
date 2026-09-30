// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IHederaTokenService } from "hedera-forking/IHederaTokenService.sol";
import { HederaResponseCodes } from "hedera-forking/HederaResponseCodes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TestStablecoin
/// @notice Testnet-only HTS stablecoin with a public, rate-limited faucet, so anyone can try the market
///         without an external faucet. Never use it as a real asset.
contract TestStablecoin {
    using SafeERC20 for IERC20;

    IHederaTokenService private constant HTS = IHederaTokenService(address(0x167));
    int64 private constant HTS_SUCCESS = int64(HederaResponseCodes.SUCCESS);
    int64 private constant AUTO_RENEW_PERIOD = 7_776_000;
    uint256 public constant RENEWAL_RESERVE = 1e8;

    uint256 public constant CLAIM_AMOUNT = 1_000e6;
    uint256 public constant CLAIM_COOLDOWN = 1 hours;

    error AlreadyInitialized();
    error NotInitialized();
    error ClaimTooSoon(uint256 availableAt);
    error HtsCallFailed(int64 responseCode);

    event Claimed(address indexed to, uint256 amount);

    address public token;
    mapping(address account => uint256) public lastClaim;

    /// @notice Creates the token. `msg.value` pays the HTS fee; the reserve is kept and the rest refunded.
    function initialize() external payable {
        if (token != address(0)) revert AlreadyInitialized();

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](1);
        keys[0].keyType = 16; // supply
        keys[0].key.contractId = address(this);

        IHederaTokenService.HederaToken memory hederaToken;
        hederaToken.name = "Test USD";
        hederaToken.symbol = "tUSD";
        hederaToken.treasury = address(this);
        hederaToken.memo = "Testnet faucet token for guarded-lending";
        hederaToken.tokenKeys = keys;
        hederaToken.expiry.autoRenewAccount = address(this);
        hederaToken.expiry.autoRenewPeriod = AUTO_RENEW_PERIOD;

        (int64 rc, address created) = HTS.createFungibleToken{ value: msg.value - RENEWAL_RESERVE }(hederaToken, 0, 6);
        if (rc != HTS_SUCCESS) revert HtsCallFailed(rc);
        token = created;

        uint256 spare = address(this).balance - RENEWAL_RESERVE;
        if (spare > 0) payable(msg.sender).transfer(spare);
    }

    /// @notice Mints `CLAIM_AMOUNT` to the caller, once per `CLAIM_COOLDOWN`. The caller must be associated.
    function claim() external {
        if (token == address(0)) revert NotInitialized();
        uint256 availableAt = lastClaim[msg.sender] + CLAIM_COOLDOWN;
        if (lastClaim[msg.sender] != 0 && block.timestamp < availableAt) revert ClaimTooSoon(availableAt);
        lastClaim[msg.sender] = block.timestamp;

        (int64 rc,,) = HTS.mintToken(token, int64(uint64(CLAIM_AMOUNT)), new bytes[](0));
        if (rc != HTS_SUCCESS) revert HtsCallFailed(rc);
        IERC20(token).safeTransfer(msg.sender, CLAIM_AMOUNT);

        emit Claimed(msg.sender, CLAIM_AMOUNT);
    }
}
