// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IHederaTokenService } from "hedera-forking/IHederaTokenService.sol";
import { IHRC719 } from "hedera-forking/IHRC719.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LendingMarket } from "../../contracts/LendingMarket.sol";
import { OracleGuard } from "../../contracts/oracle/OracleGuard.sol";
import { IPriceSource } from "../../contracts/oracle/IPriceSource.sol";
import { MockPriceSource } from "../mocks/MockPriceSource.sol";
import { MockHts, HTS_ADDRESS } from "../mocks/MockHts.sol";

/// @notice Shared setup: a mock HTS at 0x167, a test USDC created through it, three mock oracle
///         sources, a 2-of-3 guard, and an initialized market.
abstract contract MarketFixture is Test {
    uint256 internal constant HBAR_PRICE = 0.12e18;
    uint256 internal constant ONE_HBAR = 1e8; // tinybars
    uint256 internal constant ONE_USDC = 1e6;
    uint256 internal constant HTS_FEE = 20 * ONE_HBAR;

    MockPriceSource internal chainlink;
    MockPriceSource internal supra;
    MockPriceSource internal pyth;
    OracleGuard internal guard;
    IERC20 internal usdc;
    LendingMarket internal market;
    IERC20 internal shares;

    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    address internal liquidator = makeAddr("liquidator");

    function setUp() public virtual {
        vm.warp(1_790_000_000);
        vm.etch(HTS_ADDRESS, address(new MockHts()).code);
        vm.deal(address(this), 1_000 * ONE_HBAR);

        chainlink = new MockPriceSource("Chainlink", HBAR_PRICE);
        supra = new MockPriceSource("Supra", HBAR_PRICE);
        pyth = new MockPriceSource("Pyth", HBAR_PRICE);
        guard = _guardedOracle();

        usdc = IERC20(_createUsdc());
        market = _market(guard);
        shares = IERC20(market.shareToken());

        _fund(lender, 100_000 * ONE_USDC);
        _fund(liquidator, 100_000 * ONE_USDC);
        vm.deal(borrower, 100_000 * ONE_HBAR);
    }

    function _guardedOracle() internal returns (OracleGuard) {
        IPriceSource[] memory sources = new IPriceSource[](3);
        sources[0] = chainlink;
        sources[1] = supra;
        sources[2] = pyth;
        uint256[] memory ages = new uint256[](3);
        ages[0] = 1 hours;
        ages[1] = 1 hours;
        ages[2] = 1 hours;
        return new OracleGuard(
            sources,
            ages,
            OracleGuard.Params({
                quorum: 2,
                maxDeviationBps: 500,
                maxChangeBps: 2000,
                cooldown: 30 minutes,
                maxPriceAge: 10 minutes,
                minPriceE18: 0.001e18,
                maxPriceE18: 100e18
            })
        );
    }

    function _market(OracleGuard oracle) internal returns (LendingMarket m) {
        m = new LendingMarket(address(usdc), 6, oracle, _risk());
        m.initialize{ value: HTS_FEE }("Guarded USDC", "gUSDC");
    }

    function _risk() internal pure returns (LendingMarket.RiskParams memory) {
        return LendingMarket.RiskParams({
            ltvBps: 6500,
            liquidationThresholdBps: 8000,
            liquidationBonusBps: 500,
            closeFactorBps: 5000,
            baseRatePerSecond: 634_195_839, // ~2% APR
            slopePerSecond: 6_341_958_396 // +20% APR at full utilization
        });
    }

    function _createUsdc() internal returns (address token) {
        IHederaTokenService.HederaToken memory t;
        t.name = "Test USD Coin";
        t.symbol = "USDC";
        t.treasury = address(this);
        t.expiry =
            IHederaTokenService.Expiry({ second: 0, autoRenewAccount: address(this), autoRenewPeriod: 7_776_000 });
        int64 rc;
        (rc, token) = IHederaTokenService(address(0x167)).createFungibleToken{ value: HTS_FEE }(
            t, int64(uint64(1_000_000_000 * ONE_USDC)), 6
        );
        require(rc == 22, "USDC create failed");
    }

    function _fund(address who, uint256 amount) internal {
        vm.prank(who);
        IHRC719(address(usdc)).associate();
        usdc.transfer(who, amount);
    }

    function _supply(address who, uint256 amount) internal returns (uint256 minted) {
        vm.startPrank(who);
        IHRC719(address(shares)).associate();
        usdc.approve(address(market), amount);
        minted = market.supply(amount);
        vm.stopPrank();
    }

    function _depositAndBorrow(address who, uint256 collateral, uint256 debt) internal {
        vm.startPrank(who);
        market.depositCollateral{ value: collateral }();
        IHRC719(address(usdc)).associate();
        market.borrow(debt);
        vm.stopPrank();
    }

    function _setAll(uint256 priceE18) internal {
        chainlink.set(priceE18);
        supra.set(priceE18);
        pyth.set(priceE18);
    }

    /// Receives the unused part of the HTS creation fee refunded by `initialize`.
    receive() external payable { }
}
