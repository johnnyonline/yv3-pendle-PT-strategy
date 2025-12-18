// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {BaseHealthCheck, BaseStrategy, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {PendleSwapper} from "@periphery/swappers/PendleSwapper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAuction} from "./interfaces/IAuction.sol";
import {IPendleMarket, IPendlePrincipalToken, IPendleStandardizedYield} from "./interfaces/IPendle.sol";

contract PendlePTStrategy is PendleSwapper, BaseHealthCheck {

    using SafeERC20 for *;

    // ===============================================================
    // Storage
    // ===============================================================

    /// @notice Whether withdrawals are open to everyone
    bool public openWithdrawals;

    /// @notice The principal token (PT) of the Pendle market
    IPendlePrincipalToken public principalToken;

    /// @notice Auction contract for selling rewards
    IAuction public auction;

    /// @notice Maximum amount of Pendle tokens to swap for PT at once
    /// @dev Default is `type(uint256).max` (no limit)
    /// @dev Can be set to zero to disable swapping
    uint256 public maxPendleTokenToSwap;

    /// @notice Minimum time between swaps
    /// @dev Default is `type(uint256).max` (automatic swapping disabled)
    uint256 public minSwapInterval;

    /// @notice Timestamp of the last swap
    uint256 public lastSwap;

    /// @notice Addresses allowed to deposit when openDeposits is false
    mapping(address => bool) public allowed;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice The token used for entering/exiting Pendle markets
    /// @dev Must be supported by the Pendle market
    /// @dev Could be the same as `asset`
    ERC20 public immutable PENDLE_TOKEN;

    /// @notice Pendle Standardized Yield Token
    IPendleStandardizedYield public immutable SY;

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @param _asset The underlying asset
    /// @param _pendleToken The Pendle token used for entering/exiting the market
    /// @param _market The market address
    /// @param _name The name
    constructor(
        address _asset,
        address _pendleToken,
        address _market,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {
        // Get `SY` and validate `pendleToken`
        (SY,,) = IPendleMarket(_market).readTokens();
        require(SY.isValidTokenOut(_pendleToken), "!tokenOut");
        require(SY.isValidTokenIn(_pendleToken), "!tokenIn");

        // Set default values
        maxPendleTokenToSwap = type(uint256).max;
        minSwapInterval = type(uint256).max;

        // Set Pendle token
        PENDLE_TOKEN = ERC20(_pendleToken);

        // Update market
        _updateMarket(_market);

        // Approve Pendle token for router
        PENDLE_TOKEN.forceApprove(pendleRouter, type(uint256).max);
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @notice Get the balance of PT tokens held by the strategy
    /// @return The balance of PT tokens held by the strategy
    function balanceOfPT() public view returns (uint256) {
        return principalToken.balanceOf(address(this));
    }

    /// @notice Get the balance of Pendle tokens held by the strategy
    /// @return The balance of Pendle tokens held by the strategy
    function balanceOfPendleToken() public view returns (uint256) {
        return PENDLE_TOKEN.balanceOf(address(this));
    }

    /// @inheritdoc BaseStrategy
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        // If active and user is allowed return max, otherwise return zero
        return !_isExpired() && allowed[_owner] ? type(uint256).max : 0;
    }

    /// @inheritdoc BaseStrategy
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        // If expired or withdrawals are open return max, otherwise return zero
        return _isExpired() || openWithdrawals ? type(uint256).max : 0;
    }

    // ===============================================================
    // Keeper functions
    // ===============================================================

    /// @notice Kick an auction for a given token
    /// @dev Cannot kick strategy asset/Pendle token or SY/LP/PT
    /// @param _token The token that's being sold
    /// @return The available amount for bidding on in the auction
    function kickAuction(
        address _token
    ) external onlyKeepers returns (uint256) {
        address _principalToken = address(principalToken);
        require(
            _token != address(asset) && _token != address(PENDLE_TOKEN) && _token != address(SY)
                && _token != markets[_principalToken] && _token != _principalToken,
            "!token"
        );

        IAuction _auction = auction;
        ERC20(_token).safeTransfer(address(_auction), ERC20(_token).balanceOf(address(this)));
        return _auction.kick(_token);
    }

    // ===============================================================
    // Management functions
    // ===============================================================

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

    /// @notice Set the maximum amount of Pendle tokens to swap for PT at once
    /// @dev Setting this to zero disables swapping
    /// @param _maxPendleTokenToSwap Maximum amount of Pendle tokens to swap at once
    function setMaxPendleTokenToSwap(
        uint256 _maxPendleTokenToSwap
    ) external onlyManagement {
        maxPendleTokenToSwap = _maxPendleTokenToSwap;
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
        auction = IAuction(_auction);
    }

    /// @notice Rollover to a new Pendle market
    /// @dev Free all PT into Pendle token before updating market
    /// @dev Does not buy PT in the new market, that is done during tends
    /// @param _newMarket Address of the new Pendle market
    function rollover(
        address _newMarket
    ) external onlyManagement {
        // Free all PT into Pendle token
        uint256 _toFree = balanceOfPT();

        // PT --> Pendle token
        _pendleSwapFrom(address(principalToken), address(PENDLE_TOKEN), _toFree, 0);

        // Update market
        _updateMarket(_newMarket);
    }

    // ===============================================================
    // Internal mutated functions
    // ===============================================================

    /// @notice Update the Pendle market used by the strategy
    /// @param _market The new Pendle market address
    function _updateMarket(
        address _market
    ) internal {
        // Get SY and PT tokens and validate the market
        (IPendleStandardizedYield _newSY, IPendlePrincipalToken _newPT,) = IPendleMarket(_market).readTokens();
        require(_newSY == SY, "!newSY");

        // Set the new principal token with its market
        _setMarket(address(_newPT), _market);

        // Update the `principalToken`
        principalToken = IPendlePrincipalToken(_newPT);

        // Make sure market is not expired
        require(!_isExpired(), "expired");

        // Set the `guessMaxMultiplier`
        uint256 _tokenDecimals = PENDLE_TOKEN.decimals();
        uint256 _ptDecimals = _newPT.decimals();
        guessMaxMultiplier = 2 * (10 ** (_tokenDecimals > _ptDecimals ? _tokenDecimals - _ptDecimals : 1));

        // Approve PT for router
        _newPT.forceApprove(pendleRouter, type(uint256).max);
    }

    /// @notice Convert asset to pendle token
    /// @dev Override if asset is different from pendle token
    /// @dev Default is `asset == pendleToken`, so no conversion needed
    function _convertAssetToPendleToken(
        uint256 /*_amount*/
    ) internal virtual {
        return;
    }

    /// @notice Convert pendle token to asset
    /// @dev Override if asset is different from pendle token
    /// @dev Default is `asset == pendleToken`, so no conversion needed
    function _convertPendleTokenToAsset(
        uint256 /*_amount*/
    ) internal virtual {
        return;
    }

    /// @notice Free amount of PT tokens into asset
    /// @param _toFree The amount of PT tokens to free
    function _freePT(
        uint256 _toFree
    ) internal {
        if (_toFree == 0) return;

        // PT --> Pendle token
        _toFree = _pendleSwapFrom(address(principalToken), address(PENDLE_TOKEN), _toFree, 0);

        // Pendle token --> asset
        _convertPendleTokenToAsset(_toFree);
    }

    /// @inheritdoc BaseStrategy
    function _deployFunds(
        uint256 /*_amount*/
    ) internal pure override {
        return; // Do nothing, funds are deployed during tend
    }

    /// @inheritdoc BaseStrategy
    function _freeFunds(
        uint256 _amount
    ) internal override {
        uint256 _totalAssets = TokenizedStrategy.totalAssets();
        uint256 _totalInvested = _totalAssets - asset.balanceOf(address(this));
        uint256 _toFree = balanceOfPT() * _amount / _totalInvested;

        // PT --> asset
        _freePT(_toFree);
    }

    /// @inheritdoc BaseStrategy
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        return asset.balanceOf(address(this)) + balanceOfPT();
    }

    /// @inheritdoc BaseStrategy
    function _tend(
        uint256 _totalIdle
    ) internal override {
        // Update last swap time
        lastSwap = block.timestamp;

        // Asset --> Pendle token
        _convertAssetToPendleToken(_totalIdle);

        // Determine amount of Pendle token to swap to PT
        uint256 _amount = Math.min(balanceOfPendleToken(), maxPendleTokenToSwap);

        // Pendle token --> PT
        _pendleSwapFrom(address(PENDLE_TOKEN), address(principalToken), _amount, 0);
    }

    /// @inheritdoc BaseStrategy
    function _tendTrigger() internal view override returns (bool) {
        // Do nothing if strategy is shutdown
        if (TokenizedStrategy.isShutdown()) return false;

        // Do nothing if `totalAssets` is zero
        if (TokenizedStrategy.totalAssets() == 0) return false;

        // Do nothing if market is expired
        if (_isExpired()) return false;

        // Do nothing if swap is disabled
        if (maxPendleTokenToSwap == 0) return false;

        // Do nothing if if not enough time passed since last swap
        if (block.timestamp - lastSwap < minSwapInterval) return false;

        // Do nothing if not enough Pendle tokens to swap
        if (balanceOfPendleToken() < minAmountToSell) return false;

        // Otherwise, swap ahead!
        return true;
    }

    /// @inheritdoc BaseStrategy
    function _emergencyWithdraw(
        uint256 _amount
    ) internal override {
        // PT --> Pendle token
        _amount = _pendleSwapFrom(address(principalToken), address(PENDLE_TOKEN), Math.min(balanceOfPT(), _amount), 0);

        // Pendle token --> asset
        _convertPendleTokenToAsset(Math.min(balanceOfPendleToken(), _amount));
    }

    // ===============================================================
    // Internal view functions
    // ===============================================================

    /// @notice Check if the market has expired
    /// @return True if the market has expired, false otherwise
    function _isExpired() internal view returns (bool) {
        return IPendleMarket(markets[address(principalToken)]).isExpired();
    }

}
