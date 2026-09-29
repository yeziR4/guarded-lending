// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { OracleGuard } from "./oracle/OracleGuard.sol";
import { IHederaTokenService } from "hedera-forking/IHederaTokenService.sol";
import { HederaResponseCodes } from "hedera-forking/HederaResponseCodes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LendingMarket
/// @notice Lenders supply an HTS stablecoin and receive an HTS receipt token; borrowers lock HBAR and
///         borrow the stablecoin. Price-dependent actions go through `OracleGuard` and revert when it
///         is tripped; supplying, adding collateral and repaying never need a price.
contract LendingMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IHederaTokenService private constant HTS = IHederaTokenService(address(0x167));
    int64 private constant HTS_SUCCESS = int64(HederaResponseCodes.SUCCESS);

    uint256 private constant WAD = 1e18;
    uint256 private constant BPS = 10_000;
    /// @dev Inside the Hedera EVM, `msg.value` and balances are denominated in tinybars.
    uint256 private constant HBAR_DECIMALS = 8;
    /// @dev ~90 days, the minimum HTS auto-renew period.
    int64 private constant AUTO_RENEW_PERIOD = 7_776_000;
    /// @notice Tinybars kept at initialization for receipt-token renewals, so they never touch collateral.
    uint256 public constant RENEWAL_RESERVE = 1e8;

    struct RiskParams {
        uint256 ltvBps;
        uint256 liquidationThresholdBps;
        uint256 liquidationBonusBps;
        uint256 closeFactorBps;
        uint256 baseRatePerSecond;
        uint256 slopePerSecond;
    }

    struct Account {
        uint256 collateral;
        uint256 principal;
        uint256 index;
    }

    error InvalidParams();
    error AlreadyInitialized();
    error NotInitialized();
    error ZeroAmount();
    error HtsCallFailed(int64 responseCode);
    error InsufficientLiquidity(uint256 available);
    error InsufficientCollateral();
    error Undercollateralized(uint256 debt, uint256 maxDebt);
    error PositionHealthy();
    error RepayTooLarge(uint256 max);
    error HbarTransferFailed();

    event ShareTokenCreated(address shareToken);
    event Supplied(address indexed lender, uint256 assets, uint256 shares);
    event Withdrawn(address indexed lender, uint256 assets, uint256 shares);
    event CollateralDeposited(address indexed borrower, uint256 amount);
    event CollateralWithdrawn(address indexed borrower, uint256 amount);
    event Borrowed(address indexed borrower, uint256 amount);
    event Repaid(address indexed payer, address indexed borrower, uint256 amount);
    event Liquidated(
        address indexed liquidator, address indexed borrower, uint256 repaid, uint256 collateralSeized, uint256 price
    );
    event InterestAccrued(uint256 interest, uint256 borrowIndex);

    IERC20 public immutable ASSET;
    uint8 public immutable ASSET_DECIMALS;
    OracleGuard public immutable GUARD;

    uint256 public immutable LTV_BPS;
    uint256 public immutable LIQUIDATION_THRESHOLD_BPS;
    uint256 public immutable LIQUIDATION_BONUS_BPS;
    uint256 public immutable CLOSE_FACTOR_BPS;
    uint256 public immutable BASE_RATE_PER_SECOND;
    uint256 public immutable SLOPE_PER_SECOND;

    address public shareToken;
    uint256 public totalBorrows;
    uint256 public borrowIndex = WAD;
    uint256 public lastAccrual;
    uint256 public totalCollateral;
    mapping(address borrower => Account) public accounts;

    /// @param asset HTS token lenders supply (e.g. USDC).
    /// @param assetDecimals Passed in because HTS tokens cannot be queried during `forge script` simulation.
    constructor(address asset, uint8 assetDecimals, OracleGuard guard, RiskParams memory risk) {
        if (asset == address(0) || address(guard) == address(0)) revert InvalidParams();
        if (risk.ltvBps == 0 || risk.ltvBps >= risk.liquidationThresholdBps || risk.liquidationThresholdBps >= BPS) {
            revert InvalidParams();
        }
        // The bonus must fit inside the collateral buffer or liquidations would create bad debt.
        if (risk.liquidationThresholdBps * (BPS + risk.liquidationBonusBps) > BPS * BPS) revert InvalidParams();
        if (risk.closeFactorBps == 0 || risk.closeFactorBps > BPS) revert InvalidParams();

        ASSET = IERC20(asset);
        ASSET_DECIMALS = assetDecimals;
        GUARD = guard;
        LTV_BPS = risk.ltvBps;
        LIQUIDATION_THRESHOLD_BPS = risk.liquidationThresholdBps;
        LIQUIDATION_BONUS_BPS = risk.liquidationBonusBps;
        CLOSE_FACTOR_BPS = risk.closeFactorBps;
        BASE_RATE_PER_SECOND = risk.baseRatePerSecond;
        SLOPE_PER_SECOND = risk.slopePerSecond;
        lastAccrual = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice One-time setup: associates with the asset and creates the receipt token. `msg.value` pays
    ///         the creation fee; `RENEWAL_RESERVE` is kept and the rest refunded.
    /// @dev The market is its own auto-renew account: HTS rejects any account that has not signed (326).
    function initialize(string calldata name, string calldata symbol) external payable nonReentrant {
        if (shareToken != address(0)) revert AlreadyInitialized();

        _check(HTS.associateToken(address(this), address(ASSET)));

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](1);
        keys[0] = IHederaTokenService.TokenKey({
            keyType: 16, // supply key: mint on supply, burn on withdraw
            key: IHederaTokenService.KeyValue({
                inheritAccountKey: false,
                contractId: address(this),
                ed25519: "",
                ECDSA_secp256k1: "",
                delegatableContractId: address(0)
            })
        });

        IHederaTokenService.HederaToken memory token = IHederaTokenService.HederaToken({
            name: name,
            symbol: symbol,
            treasury: address(this),
            memo: "OracleGuard lending market receipt",
            tokenSupplyType: false,
            maxSupply: 0,
            freezeDefault: false,
            tokenKeys: keys,
            expiry: IHederaTokenService.Expiry({
                second: 0, autoRenewAccount: address(this), autoRenewPeriod: AUTO_RENEW_PERIOD
            })
        });

        if (msg.value <= RENEWAL_RESERVE) revert InvalidParams();
        (int64 rc, address created) =
            HTS.createFungibleToken{ value: msg.value - RENEWAL_RESERVE }(token, 0, int32(uint32(ASSET_DECIMALS)));
        _check(rc);

        shareToken = created;
        emit ShareTokenCreated(created);

        uint256 spare = address(this).balance - totalCollateral;
        if (spare > RENEWAL_RESERVE) _sendHbar(msg.sender, spare - RENEWAL_RESERVE);
    }

    /*//////////////////////////////////////////////////////////////
                              LENDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The caller must be associated with the share token (IHRC-719 `associate()`).
    function supply(uint256 assets) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        address share = _share();
        accrueInterest();

        shares = _toShares(assets);
        if (shares == 0) revert ZeroAmount();

        ASSET.safeTransferFrom(msg.sender, address(this), assets);
        _mintShares(share, shares);
        IERC20(share).safeTransfer(msg.sender, shares);

        emit Supplied(msg.sender, assets, shares);
    }

    /// @notice Burns `shares` (approve this market first) and returns the underlying asset.
    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        address share = _share();
        accrueInterest();

        assets = _toAssets(shares);
        uint256 cash = ASSET.balanceOf(address(this));
        if (assets > cash) revert InsufficientLiquidity(cash);

        IERC20(share).safeTransferFrom(msg.sender, address(this), shares);
        _burnShares(share, shares);
        ASSET.safeTransfer(msg.sender, assets);

        emit Withdrawn(msg.sender, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                             BORROWERS
    //////////////////////////////////////////////////////////////*/

    function depositCollateral() external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        accounts[msg.sender].collateral += msg.value;
        totalCollateral += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Account storage account = accounts[msg.sender];
        if (amount > account.collateral) revert InsufficientCollateral();

        accrueInterest();
        uint256 price = _guardedPrice();

        account.collateral -= amount;
        totalCollateral -= amount;
        _requireWithinLtv(account, price);

        _sendHbar(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();
        uint256 price = _guardedPrice();

        uint256 cash = ASSET.balanceOf(address(this));
        if (amount > cash) revert InsufficientLiquidity(cash);

        Account storage account = accounts[msg.sender];
        account.principal = _debt(account) + amount;
        account.index = borrowIndex;
        totalBorrows += amount;
        _requireWithinLtv(account, price);

        ASSET.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    /// @notice Repays up to `amount` of `borrower`'s debt. Anyone may repay for anyone.
    function repay(address borrower, uint256 amount) external nonReentrant returns (uint256 repaid) {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        Account storage account = accounts[borrower];
        uint256 debt = _debt(account);
        repaid = amount > debt ? debt : amount;
        if (repaid == 0) revert ZeroAmount();

        ASSET.safeTransferFrom(msg.sender, address(this), repaid);
        _reduceDebt(account, debt, repaid);

        emit Repaid(msg.sender, borrower, repaid);
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Repays part of an unhealthy position for collateral plus the bonus. Blocked while tripped.
    function liquidate(address borrower, uint256 repayAmount) external nonReentrant returns (uint256 seized) {
        if (repayAmount == 0) revert ZeroAmount();
        accrueInterest();
        uint256 price = _guardedPrice();

        Account storage account = accounts[borrower];
        uint256 debt = _debt(account);
        if (debt * BPS <= _collateralValue(account.collateral, price) * LIQUIDATION_THRESHOLD_BPS) {
            revert PositionHealthy();
        }

        uint256 maxRepay = debt * CLOSE_FACTOR_BPS / BPS;
        if (repayAmount > maxRepay) revert RepayTooLarge(maxRepay);

        seized = _assetToCollateral(repayAmount, price) * (BPS + LIQUIDATION_BONUS_BPS) / BPS;
        if (seized > account.collateral) seized = account.collateral;

        ASSET.safeTransferFrom(msg.sender, address(this), repayAmount);
        _reduceDebt(account, debt, repayAmount);
        account.collateral -= seized;
        totalCollateral -= seized;

        _sendHbar(msg.sender, seized);
        emit Liquidated(msg.sender, borrower, repayAmount, seized, price);
    }

    /*//////////////////////////////////////////////////////////////
                              INTEREST
    //////////////////////////////////////////////////////////////*/

    function accrueInterest() public {
        uint256 elapsed = block.timestamp - lastAccrual;
        if (elapsed == 0) return;
        lastAccrual = block.timestamp;
        if (totalBorrows == 0) return;

        uint256 factor = borrowRatePerSecond() * elapsed;
        uint256 interest = totalBorrows * factor / WAD;
        totalBorrows += interest;
        borrowIndex += borrowIndex * factor / WAD;

        emit InterestAccrued(interest, borrowIndex);
    }

    /// @notice Linear utilization model: base + slope * utilization, WAD-scaled per second.
    function borrowRatePerSecond() public view returns (uint256) {
        return BASE_RATE_PER_SECOND + SLOPE_PER_SECOND * utilization() / WAD;
    }

    function utilization() public view returns (uint256) {
        uint256 supplied = ASSET.balanceOf(address(this)) + totalBorrows;
        return supplied == 0 ? 0 : totalBorrows * WAD / supplied;
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        return ASSET.balanceOf(address(this)) + totalBorrows;
    }

    function debtOf(address borrower) external view returns (uint256) {
        return _debt(accounts[borrower]);
    }

    /// @notice For display, priced at `price` (e.g. `GUARD.lastPrice()`). Collateral in tinybars;
    ///         health factor WAD-scaled, max uint without debt.
    function positionAt(address borrower, uint256 price)
        external
        view
        returns (uint256 collateral, uint256 debt, uint256 maxDebt, uint256 healthFactorWad)
    {
        Account storage account = accounts[borrower];
        collateral = account.collateral;
        debt = _debt(account);
        uint256 value = _collateralValue(collateral, price);
        maxDebt = value * LTV_BPS / BPS;
        healthFactorWad = debt == 0 ? type(uint256).max : value * LIQUIDATION_THRESHOLD_BPS * WAD / (debt * BPS);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Reverts with the breaker reason if the check fails.
    function _guardedPrice() private returns (uint256) {
        GUARD.poke();
        return GUARD.price();
    }

    function _share() private view returns (address share) {
        share = shareToken;
        if (share == address(0)) revert NotInitialized();
    }

    function _debt(Account storage account) private view returns (uint256) {
        if (account.principal == 0) return 0;
        return account.principal * borrowIndex / account.index;
    }

    function _reduceDebt(Account storage account, uint256 debt, uint256 amount) private {
        account.principal = debt - amount;
        account.index = borrowIndex;
        // Per-account rounding can leave totalBorrows a few units below the sum of debts.
        totalBorrows = amount > totalBorrows ? 0 : totalBorrows - amount;
    }

    function _requireWithinLtv(Account storage account, uint256 price) private view {
        uint256 debt = _debt(account);
        uint256 maxDebt = _collateralValue(account.collateral, price) * LTV_BPS / BPS;
        if (debt > maxDebt) revert Undercollateralized(debt, maxDebt);
    }

    /// @dev tinybars * (USD per HBAR, 1e18) -> asset units.
    function _collateralValue(uint256 tinybars, uint256 priceE18) private view returns (uint256) {
        return tinybars * priceE18 * 10 ** ASSET_DECIMALS / (WAD * 10 ** HBAR_DECIMALS);
    }

    /// @dev asset units -> tinybars at `priceE18`.
    function _assetToCollateral(uint256 assets, uint256 priceE18) private view returns (uint256) {
        return assets * WAD * 10 ** HBAR_DECIMALS / (priceE18 * 10 ** ASSET_DECIMALS);
    }

    /// @dev Virtual share/asset offset of 1 blunts first-depositor share-inflation attacks.
    function _toShares(uint256 assets) private view returns (uint256) {
        return assets * (IERC20(shareToken).totalSupply() + 1) / (totalAssets() + 1);
    }

    function _toAssets(uint256 shares) private view returns (uint256) {
        return shares * (totalAssets() + 1) / (IERC20(shareToken).totalSupply() + 1);
    }

    function _mintShares(address share, uint256 amount) private {
        (int64 rc,,) = HTS.mintToken(share, _toInt64(amount), new bytes[](0));
        _check(rc);
    }

    function _burnShares(address share, uint256 amount) private {
        (int64 rc,) = HTS.burnToken(share, _toInt64(amount), new int64[](0));
        _check(rc);
    }

    function _sendHbar(address to, uint256 tinybars) private {
        (bool ok,) = to.call{ value: tinybars }("");
        if (!ok) revert HbarTransferFailed();
    }

    function _check(int64 rc) private pure {
        if (rc != HTS_SUCCESS) revert HtsCallFailed(rc);
    }

    function _toInt64(uint256 amount) private pure returns (int64) {
        if (amount > uint256(uint64(type(int64).max))) revert InvalidParams();
        return int64(uint64(amount));
    }
}
