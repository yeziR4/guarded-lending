// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IHederaTokenService } from "hedera-forking/IHederaTokenService.sol";

address constant HTS_ADDRESS = address(0x167);
int64 constant HTS_SUCCESS = 22;

/// @notice Token created by MockHts: ERC-20 plus IHRC-719, mint/burn only through the mock.
contract MockHtsToken is ERC20 {
    uint8 private immutable DECIMALS;
    address public immutable TREASURY;
    address public immutable SUPPLY_KEY;

    constructor(string memory name, string memory symbol, uint8 decimals_, address treasury, address supplyKey)
        ERC20(name, symbol)
    {
        DECIMALS = decimals_;
        TREASURY = treasury;
        SUPPLY_KEY = supplyKey;
    }

    modifier onlyHts() {
        require(msg.sender == HTS_ADDRESS, "only HTS");
        _;
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function htsMint(uint256 amount) external onlyHts {
        _mint(TREASURY, amount);
    }

    function htsBurn(uint256 amount) external onlyHts {
        _burn(TREASURY, amount);
    }

    function associate() external pure returns (int64) {
        return HTS_SUCCESS;
    }

    function isAssociated() external pure returns (bool) {
        return true;
    }
}

/// @notice The HTS calls LendingMarket makes, etched at 0x167. Enforces the supply key and HTS's
///         auto-renew signature rule.
contract MockHts {
    uint256 private constant SUPPLY_KEY_TYPE = 16;
    int64 private constant INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE = 326;
    /// @notice Roughly the $1 token-creation fee in tinybars.
    uint256 private constant CREATE_FEE = 13e8;

    function createFungibleToken(IHederaTokenService.HederaToken memory token, int64 initialTotalSupply, int32 decimals)
        external
        payable
        returns (int64, address)
    {
        // Only the calling contract itself can be named without a signature.
        if (token.expiry.autoRenewAccount != address(0) && token.expiry.autoRenewAccount != msg.sender) {
            return (INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE, address(0));
        }
        address supplyKey;
        for (uint256 i = 0; i < token.tokenKeys.length; i++) {
            if (token.tokenKeys[i].keyType & SUPPLY_KEY_TYPE != 0) supplyKey = token.tokenKeys[i].key.contractId;
        }
        require(msg.value >= CREATE_FEE, "create: insufficient fee");
        MockHtsToken created =
            new MockHtsToken(token.name, token.symbol, uint8(uint32(decimals)), token.treasury, supplyKey);
        if (initialTotalSupply > 0) created.htsMint(uint256(uint64(initialTotalSupply)));
        return (HTS_SUCCESS, address(created));
    }

    function associateToken(address, address) external pure returns (int64) {
        return HTS_SUCCESS;
    }

    function mintToken(address token, int64 amount, bytes[] memory) external returns (int64, int64, int64[] memory) {
        MockHtsToken t = MockHtsToken(token);
        require(msg.sender == t.SUPPLY_KEY(), "mint: not supply key");
        t.htsMint(uint256(uint64(amount)));
        return (HTS_SUCCESS, int64(uint64(t.totalSupply())), new int64[](0));
    }

    function burnToken(address token, int64 amount, int64[] memory) external returns (int64, int64) {
        MockHtsToken t = MockHtsToken(token);
        require(msg.sender == t.SUPPLY_KEY(), "burn: not supply key");
        t.htsBurn(uint256(uint64(amount)));
        return (HTS_SUCCESS, int64(uint64(t.totalSupply())));
    }
}
