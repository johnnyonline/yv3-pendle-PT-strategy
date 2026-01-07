// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {BaseHealthCheck, BaseStrategy, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {PendleSwapper} from "@periphery/swappers/PendleSwapper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAuction} from "./interfaces/IAuction.sol";
import {IPendleOracle, IPendleMarket, IPendlePrincipalToken, IPendleStandardizedYield} from "./interfaces/IPendle.sol";

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

    /// @notice Minimum amount of Pendle tokens to trigger a tend
    /// @dev Default is 0 (tend triggered based on `minAmountToSell` only)
    uint256 public minPendleTokenToTrigger;

    /// @notice Maximum amount of Pendle tokens to swap for PT at once
    /// @dev Default is `type(uint256).max` (no limit)
    /// @dev Can be set to zero to disable swapping
    uint256 public maxPendleTokenToSwap;

    /// @notice Minimum time between swaps
    /// @dev Default is `type(uint256).max` (automatic swapping disabled)
    uint256 public minSwapInterval;

    /// @notice Timestamp of the last swap
    uint256 public lastSwap;

    /// @notice Slippage tolerance for Pendle token to PT swaps in basis points
    uint256 public swapSlippageBPS;

    /// @notice Addresses allowed to deposit when openDeposits is false
    /// @dev Generally this strategy should be used by a single depositor only
    mapping(address => bool) public allowed;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Governance address
    address public immutable GOV;

    /// @notice The token used for entering/exiting Pendle markets
    /// @dev Must be supported by the Pendle market
    /// @dev Could be the same as `asset`
    ERC20 public immutable PENDLE_TOKEN;

    /// @notice Pendle Standardized Yield Token
    IPendleStandardizedYield public immutable SY;

    /// @notice The Pendle pyYtLpOracle oracle
    IPendleOracle public immutable ORACLE;

    /// @notice Duration for TWAP calculations in the Pendle oracle
    uint32 private constant _TWAP_DURATION = 1800; // 30 minutes

    /// @notice The WAD constant
    uint256 private constant _WAD = 1e18;

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @param _asset The underlying asset
    /// @param _pendleToken The Pendle token used for entering/exiting the market
    /// @param _market The market address
    /// @param _oracle The pyYtLpOracle oracle address
    /// @param _gov The governance address
    /// @param _name The name
    constructor(
        address _asset,
        address _pendleToken,
        address _market,
        address _oracle,
        address _gov,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {
        // Get `SY` and validate `pendleToken`
        (SY,,) = IPendleMarket(_market).readTokens();
        require(SY.isValidTokenOut(_pendleToken), "!tokenOut");
        require(SY.isValidTokenIn(_pendleToken), "!tokenIn");

        // Make sure Pendle token is SY's underlying asset
        // See `_PTInPendleToken` for more details
        (, address _syAsset,) = SY.assetInfo();
        require(_syAsset == _pendleToken, "!pendleToken");

        // Set oracle
        ORACLE = IPendleOracle(_oracle);

        // Set governance
        GOV = _gov;

        // Set Pendle token
        PENDLE_TOKEN = ERC20(_pendleToken);

        // Set default values
        maxPendleTokenToSwap = type(uint256).max; // No limit by default
        minSwapInterval = type(uint256).max; // No automatic swapping by default
        swapSlippageBPS = 50; // 0.5% slippage tolerance by default

        // Update market
        _updateMarket(_market);

        // Set min amount to sell to 0.001 unit of principal token
        _setMinAmountToSell(10 ** (principalToken.decimals() - 3));

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
    function allowWithdrawals(
        bool _allowWithdrawals
    ) external onlyManagement {
        openWithdrawals = _allowWithdrawals;
    }

    /// @notice Allow a specific address to deposit
    /// @dev This is irreversible
    /// @param _address Address to allow
    function setAllowed(
        address _address
    ) external onlyManagement {
        allowed[_address] = true;
    }

    /// @notice Set the minimum amount of Pendle tokens to trigger a tend
    /// @param _minPendleTokenToTrigger Minimum amount of Pendle tokens to trigger
    function setMinPendleTokenToTrigger(
        uint256 _minPendleTokenToTrigger
    ) external onlyManagement {
        minPendleTokenToTrigger = _minPendleTokenToTrigger;
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

    /// @notice Set the acceptable slippage for Pendle token to PT swaps in basis points
    /// @param _swapSlippageBPS Acceptable slippage in basis points
    function setSwapSlippageBPS(
        uint256 _swapSlippageBPS
    ) external onlyManagement {
        require(_swapSlippageBPS <= MAX_BPS, "!swapSlippageBPS");
        swapSlippageBPS = _swapSlippageBPS;
    }

    /// @notice Set the minimum amount of tokens to sell in a swap
    /// @dev Should be used to avoid swapping dust amounts
    /// @param _minAmountToSell Minimum amount of tokens needed to execute a swap
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        _setMinAmountToSell(_minAmountToSell);
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

    // ===============================================================
    // Governance functions
    // ===============================================================

    /// @notice Rollover to a new Pendle market
    /// @dev Free all PT into Pendle token before updating market
    /// @dev Does not buy PT in the new market, that is done during tends
    /// @param _newMarket Address of the new Pendle market
    function rollover(
        address _newMarket
    ) external {
        // Make sure caller is governance
        require(msg.sender == GOV, "!governance");

        // Make sure market expired
        require(_isExpired(), "!expired");

        // Free all PT into Pendle token
        uint256 _toFree = balanceOfPT();

        // Calculate expected Pendle token out
        uint256 _expectedAmountOut = _PTInPendleToken(_toFree);

        // Calculate minimum acceptable amount out of Pendle token
        uint256 _minAmountOut = _expectedAmountOut * (MAX_BPS - swapSlippageBPS) / MAX_BPS;

        // PT --> Pendle token
        _pendleSwapFrom(address(principalToken), address(PENDLE_TOKEN), _toFree, _minAmountOut);

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
        // Check oracle is ready
        (bool _increaseCardinalityRequired,, bool _oldestObservationSatisfied) =
            ORACLE.getOracleState(_market, _TWAP_DURATION);

        // If reverts, Call market.increaseObservationsCardinalityNext(cardinalityRequired) and wait
        // for at least the `_TWAP_DURATION` to allow data population.
        // On Ethereum, for twap duration of `1800` seconds, `cardinalityRequired` can be `165`
        require(!_increaseCardinalityRequired, "increaseCardinalityRequired");

        // Ser, wait for at least `_TWAP_DURATION` please
        require(_oldestObservationSatisfied, "!oldestObservationNotSatisfied");

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
        // Cache Pendle token balance before freeing PT
        uint256 _pendleTokenBalanceBefore = balanceOfPendleToken();

        // Free proportional amount of PT
        uint256 _totalAssets = TokenizedStrategy.totalAssets();
        uint256 _totalInvested = _totalAssets - asset.balanceOf(address(this));
        uint256 _toFree = balanceOfPT() * _amount / _totalInvested;

        // PT --> Pendle token
        _toFree = _pendleSwapFrom(address(principalToken), address(PENDLE_TOKEN), _toFree, 0);

        // If asset is different from Pendle token, we need to free the proportional amount of Pendle token too
        if (address(asset) != address(PENDLE_TOKEN)) _toFree += _pendleTokenBalanceBefore * _amount / _totalInvested;

        // Pendle token --> asset
        _convertPendleTokenToAsset(_toFree);
    }

    /// @inheritdoc BaseStrategy
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // Total Pendle token value (balance + PT value)
        uint256 _totalPendleToken = balanceOfPendleToken() + _PTInPendleToken(balanceOfPT());

        // Total assets = asset balance + Pendle token and PT value in asset
        return asset.balanceOf(address(this)) + _pendleTokenInAsset(_totalPendleToken);
    }

    /// @inheritdoc BaseStrategy
    function _tend(
        uint256 _totalIdle
    ) internal virtual override {
        // Update last swap time
        lastSwap = block.timestamp;

        // Asset --> Pendle token
        _convertAssetToPendleToken(_totalIdle);

        // Determine amount of Pendle token to swap to PT
        uint256 _amount = Math.min(balanceOfPendleToken(), maxPendleTokenToSwap);

        // Calculate expected PT out (inverse of _PTInPendleToken)
        uint256 _expectedAmountOut = _amount * _WAD / _PTInPendleToken(_WAD);

        // Calculate minimum acceptable amount out of PT
        uint256 _minAmountOut = _expectedAmountOut * (MAX_BPS - swapSlippageBPS) / MAX_BPS;

        // Pendle token --> PT
        _pendleSwapFrom(address(PENDLE_TOKEN), address(principalToken), _amount, _minAmountOut);
    }

    /// @inheritdoc BaseStrategy
    function _tendTrigger() internal view virtual override returns (bool) {
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

        // Cache Pendle token balance
        uint256 _balanceOfPendleToken = balanceOfPendleToken();

        // Do nothing if not enough Pendle tokens to swap
        if (_balanceOfPendleToken < minAmountToSell) return false;

        // Do nothing if not enough Pendle tokens to trigger
        if (_balanceOfPendleToken < minPendleTokenToTrigger) return false;

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

    /// @notice Price PT in Pendle token
    /// @dev `_price` is always in WAD format
    /// @dev `pendleToken` must be SY's underlying asset for this to work
    /// @param _amount Amount of PT to price
    /// @return Amount of Pendle token equivalent
    function _PTInPendleToken(
        uint256 _amount
    ) internal view returns (uint256) {
        if (_amount == 0) return 0;

        // PT --> Pendle token (directly using SY rates)
        uint256 _price = ORACLE.getPtToAssetRate(markets[address(principalToken)], _TWAP_DURATION);

        return _amount * _price / _WAD;
    }

    /// @notice Price Pendle token in asset
    /// @dev Override if asset is different from pendle token
    /// @param _pendleTokenAmount Amount of Pendle token to price
    /// @return Amount of asset equivalent
    function _pendleTokenInAsset(
        uint256 _pendleTokenAmount
    ) internal view virtual returns (uint256) {
        return _pendleTokenAmount;
    }

}
