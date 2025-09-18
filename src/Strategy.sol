// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {BaseHealthCheck, BaseStrategy, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAuction} from "./interfaces/IAuction.sol";
import {
    IPendleMarket,
    IPendlePrincipalToken,
    IPendleRouter,
    IPendleStandardizedYield,
    IPendleYieldToken,
    PendleLimitOrderData,
    PendleSwapData,
    PendleTokenInput
} from "./interfaces/IPendle.sol";

contract PendlePTStrategy is BaseHealthCheck {

    using SafeERC20 for *;

    // ===============================================================
    // Storage
    // ===============================================================

    /// @notice Whether deposits are open to everyone
    bool public openDeposits;

    /// @notice Whether withdrawals are open to everyone
    bool public openWithdrawals;

    /// @notice Whether should claim YT rewards and yield
    bool public shouldClaimYT;

    /// @notice Auction contract for selling rewards
    address public auction;

    /// @notice Maximum amount of YT to market sell for SY in a single harvest
    /// @dev Selling YTs realizes yield that otherwise may accrue to depositors over time.
    ///       By selling YTs, the vault captures potential future yield upfront.
    ///       This can disadvantage new depositors, since past depositors already benefited
    ///       from the realized gains, while new depositors contribute fresh YTs without sharing
    ///       in those prior benefits
    uint256 public maxYTToSell;

    /// @notice Addresses allowed to deposit when openDeposits is false
    mapping(address => bool) public allowed;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Pendle Market
    IPendleMarket public immutable LP;

    /// @notice Pendle Yield Token
    IPendleYieldToken public immutable YT;

    /// @notice Pendle Principal Token
    IPendlePrincipalToken public immutable PT;

    /// @notice Pendle Standardized Yield Token
    IPendleStandardizedYield public immutable SY;

    /// @notice Pendle Router
    IPendleRouter public constant ROUTER = IPendleRouter(0x888888888889758F76e7103c6CbF23ABbF58F946);

    /// @notice Dust threshold
    uint256 public constant DUST_THRESHOLD = 10_000;

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @param _asset The underlying asset
    /// @param _market The market address
    /// @param _name The name
    constructor(address _asset, address _market, string memory _name) BaseHealthCheck(_asset, _name) {
        LP = IPendleMarket(_market);
        require(!_isExpired(), "expired");

        (SY, PT, YT) = LP.readTokens();
        require(SY.isValidTokenOut(_asset) && SY.isValidTokenIn(_asset), "!valid");

        asset.forceApprove(address(ROUTER), type(uint256).max);
        SY.forceApprove(address(ROUTER), type(uint256).max);
        YT.forceApprove(address(ROUTER), type(uint256).max);
        PT.forceApprove(address(ROUTER), type(uint256).max);
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @inheritdoc BaseStrategy
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        // If active and deposits are open or user is allowed return max, otherwise return zero
        return !_isExpired() && (openDeposits || allowed[_owner]) ? type(uint256).max : 0;
    }

    /// @inheritdoc BaseStrategy
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        // If expired or withdrawals are open return max, otherwise return zero
        return _isExpired() || openWithdrawals ? type(uint256).max : 0;
    }

    /// @notice Get the balance of PT tokens held by the strategy
    /// @return The balance of PT tokens held by the strategy
    function balanceOfPT() public view returns (uint256) {
        return PT.balanceOf(address(this));
    }

    // ===============================================================
    // Keeper functions
    // ===============================================================

    /// @notice Kick an auction for a given token
    /// @dev Cannot kick strategy asset or SY/PT/YT/LP
    /// @param _token The token that's being sold
    /// @return The available amount for bidding on in the auction
    function kickAuction(
        address _token
    ) external onlyKeepers returns (uint256) {
        require(
            _token != address(LP) && _token != address(SY) && _token != address(PT) && _token != address(YT)
                && _token != address(asset),
            "!token"
        );

        address _auction = auction;
        ERC20(_token).safeTransfer(_auction, ERC20(_token).balanceOf(address(this)));
        return IAuction(_auction).kick(_token);
    }

    // ===============================================================
    // Management functions
    // ===============================================================

    /// @notice Allow anyone to deposit
    /// @dev This is irreversible
    function allowDeposits() external onlyManagement {
        openDeposits = true;
    }

    /// @notice Allow anyone to withdraw before expiry
    /// @dev This is irreversible
    function allowWithdrawals() external onlyManagement {
        openWithdrawals = true;
    }

    /// @notice Allow a specific address to deposit
    /// @dev This is irreversible
    /// @param _address Address to allow
    function setAllowed(
        address _address
    ) external onlyManagement {
        allowed[_address] = true;
    }

    /// @notice Set whether to claim YT rewards and yield
    /// @param _shouldClaimYT Whether to claim YT rewards and yield
    function setShouldClaimYT(
        bool _shouldClaimYT
    ) external onlyManagement {
        shouldClaimYT = _shouldClaimYT;
    }

    /// @notice Set the maximum amount of YT to sell
    /// @dev Used to limit the amount of YT sold in a single harvest to minimize slippage
    /// @param _maxYTToSell Maximum amount of YT to sell in a single harvest
    function setMaxYTToSell(
        uint256 _maxYTToSell
    ) external onlyManagement {
        maxYTToSell = _maxYTToSell;
    }

    /// @notice Update the auction address
    /// @param _auction Address of new auction.
    function setAuction(
        address _auction
    ) external onlyManagement {
        require(IAuction(_auction).receiver() == address(this), "!receiver");
        require(IAuction(_auction).want() == address(asset), "!want");
        auction = _auction;
    }

    // ===============================================================
    // Internal mutated functions
    // ===============================================================

    /// @inheritdoc BaseStrategy
    function _deployFunds(
        uint256 _amount
    ) internal override {
        // Empty swap data as we're not swapping anything
        PendleSwapData memory _swapData;

        // Asset --> PY
        ROUTER.mintPyFromToken(
            address(this), // receiver
            address(YT), // YT
            0, // minPyOut
            PendleTokenInput({
                tokenIn: address(asset),
                netTokenIn: _amount,
                tokenMintSy: address(asset),
                pendleSwap: address(0),
                swapData: _swapData
            })
        );
    }

    /// @inheritdoc BaseStrategy
    function _freeFunds(
        uint256 _amount
    ) internal override {
        // Free proportional share
        uint256 _totalAssets = TokenizedStrategy.totalAssets();
        uint256 _totalInvested = _totalAssets - asset.balanceOf(address(this));
        uint256 _toFree = balanceOfPT() * _amount / _totalInvested;

        // PT --> asset
        _freePT(_toFree);
    }

    /// @inheritdoc BaseStrategy
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (!TokenizedStrategy.isShutdown()) {
            bool _isActive = !_isExpired();
            uint256 _yt = YT.balanceOf(address(this));
            if (_yt > DUST_THRESHOLD) {
                if (shouldClaimYT) {
                    // Claim any rewards or accrued interest (in SY) from the YT
                    YT.redeemDueInterestAndRewards(
                        address(this), // user
                        true, // redeemInterest
                        true // redeemRewards
                    );
                }

                // Sell YT only if market is active
                if (_isActive) {
                    uint256 _maxYTToSell = maxYTToSell;
                    if (_maxYTToSell > 0) {
                        // Empty limit order as we control the amount with `maxYTToSell`
                        PendleLimitOrderData memory limit;

                        // YT --> SY
                        ROUTER.swapExactYtForSy(
                            address(this), // receiver
                            address(LP), // market
                            Math.min(_yt, _maxYTToSell), // exactYtIn
                            0, // minSyOut
                            limit
                        );
                    }
                } else {
                    // Redeem any SY that were claimed after expiry
                    _redeemSY(SY.balanceOf(address(this)));
                }
            }

            // If market is active, deploy all idle SY
            if (_isActive) _deploySY();
        }

        return asset.balanceOf(address(this)) + balanceOfPT();
    }

    /// @inheritdoc BaseStrategy
    function _emergencyWithdraw(
        uint256 _amount
    ) internal override {
        _freePT(Math.min(balanceOfPT(), _amount));
    }

    /// @notice Deploy all idle SY tokens into PY
    /// @dev Mints PY (PT/YT) while keeping the YT, which means there's no slippage
    function _deploySY() internal {
        uint256 _sy = SY.balanceOf(address(this));
        if (_sy > DUST_THRESHOLD) {
            // SY --> PY
            ROUTER.mintPyFromSy(
                address(this), // receiver
                address(YT), // YT
                _sy, // netSyIn
                0 // minPyOut
            );
        }
    }

    /// @notice Free `_amount` of PT tokens into asset
    /// @param _amount The amount of PT tokens to free
    function _freePT(
        uint256 _amount
    ) internal {
        if (_amount == 0) return;

        // Initialize variable that stores amount of SY received from selling/redeeming PT
        uint256 _sy;

        // If active, market sell for SY. Otherwise redeem
        if (!_isExpired()) {
            // Empty limit order. Deal with it
            PendleLimitOrderData memory limit;

            // PT --> SY
            (_sy,) = ROUTER.swapExactPtForSy(
                address(this), // receiver
                address(LP), // market
                _amount, // exactPtIn
                0, // minSyOut
                limit
            );
        } else {
            // PT must be transferred to the YT contract prior to calling `redeemPY`
            PT.safeTransfer(address(YT), _amount);

            // PT --> SY
            _sy = YT.redeemPY(address(this));
        }

        // SY --> asset
        _redeemSY(_sy);
    }

    /// @notice Redeem SY tokens to asset
    function _redeemSY(
        uint256 _amount
    ) internal {
        if (_amount == 0) return;

        // SY --> asset
        SY.redeem(
            address(this), // receiver
            _amount, // amountSharesToRedeem
            address(asset), // tokenOut
            0, // minTokenOut
            false // burnFromInternalBalance
        );
    }

    // ===============================================================
    // Internal view functions
    // ===============================================================

    /// @notice Check if the market has expired
    /// @return True if the market has expired, false otherwise
    function _isExpired() internal view returns (bool) {
        return LP.isExpired();
    }

}
