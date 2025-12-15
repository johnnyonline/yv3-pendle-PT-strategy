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

    /// @notice Auction contract for selling rewards
    address public auction;

    /// @notice Maximum amount of asset to swap for PT at once
    /// @dev Default is 0 (swapping disabled)
    uint256 public maxAssetToSwap;

    /// @notice Minimum idle asset required to trigger a swap
    uint256 public minAssetToSwap;

    /// @notice Minimum time between swaps
    uint256 public minSwapInterval;

    /// @notice Timestamp of the last swap
    uint256 public lastSwap;

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
    function allowDeposits() external onlyManagement { // @todo -- remove (and then implement base thing from schlag comment)
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

    /// @notice Set the maximum amount of asset to swap for PT at once
    /// @dev Setting this to zero disables swapping
    /// @param _maxAssetToSwap Maximum amount of asset to swap at once
    function setMaxAssetToSwap(
        uint256 _maxAssetToSwap
    ) external onlyManagement {
        maxAssetToSwap = _maxAssetToSwap;
    }

    /// @notice Set the minimum idle asset required to trigger a swap
    /// @dev Setting this to `type(uint256).max` disables swapping
    /// @param _minAssetToSwap Minimum asset balance to swap
    function setMinAssetToSwap(
        uint256 _minAssetToSwap
    ) external onlyManagement {
        minAssetToSwap = _minAssetToSwap;
    }

    /// @notice Set the minimum time between swaps
    /// @param _minSwapInterval Minimum seconds between swaps
    function setMinSwapInterval(
        uint256 _minSwapInterval
    ) external onlyManagement {
        minSwapInterval = _minSwapInterval;
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
    function _deployFunds(uint256 /*_amount*/) internal override {
        return; // Do nothing, funds are deployed during tend
    }

    /// @inheritdoc BaseStrategy
    function _freeFunds(
        uint256 _amount
    ) internal override {
        uint256 _totalAssets = TokenizedStrategy.totalAssets();
        uint256 _totalInvested = _totalAssets - asset.balanceOf(address(this));
        uint256 _toFree = balanceOfPT() * _amount / _totalInvested;

        _freePT(_toFree);
    }

    /// @inheritdoc BaseStrategy
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        return asset.balanceOf(address(this)) + balanceOfPT();
    }

    /// @inheritdoc BaseStrategy
    function _tend(uint256 /*_totalIdle*/) internal override {
        // Update last swap time
        lastSwap = block.timestamp;

        // Empty swap data as we are using a supported token
        PendleSwapData memory _swapData;

        // Asset --> PT
        ROUTER.swapExactTokenForPtSimple( // @todo -- use swapExactTokenForPt
            address(this), // receiver
            address(LP), // market
            0, // minPtOut
            PendleTokenInput({
                tokenIn: address(asset),
                netTokenIn: Math.min(asset.balanceOf(address(this)), maxAssetToSwap),
                tokenMintSy: address(asset),
                pendleSwap: address(0),
                swapData: _swapData
            })
        );
    }

    /// @inheritdoc BaseStrategy
    function _tendTrigger() internal view override returns (bool) {
        // Do nothing if market is expired
        if (_isExpired()) return false;

        // Do nothing if strategy is shutdown
        if (TokenizedStrategy.isShutdown()) return false;

        // Do nothing if swap is disabled
        if (maxAssetToSwap == 0) return false;

        // Do nothing if if not enough time passed since last swap
        if (block.timestamp - lastSwap < minSwapInterval) return false;

        // Do nothing if not enough asset to swap
        if (asset.balanceOf(address(this)) < minAssetToSwap) return false;

        // Otherwise, swap ahead!
        return true;
    }

    /// @inheritdoc BaseStrategy
    function _emergencyWithdraw(
        uint256 _amount
    ) internal override {
        _freePT(Math.min(balanceOfPT(), _amount));
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
