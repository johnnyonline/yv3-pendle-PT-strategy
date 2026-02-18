// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IPendleOracle, IPendleMarket, IPendleStaticRouter} from "../interfaces/IPendle.sol";

contract PendlePTStrategyAprOracle is AprOracleBase {

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice Duration for TWAP calculations in the Pendle oracle
    uint32 private constant _TWAP_DURATION = 1800; // 30 minutes

    /// @notice WAD
    uint256 private constant _WAD = 1e18;

    /// @notice Seconds in a year
    uint256 private constant _SECONDS_PER_YEAR = 365 days;

    /// @notice Pendle's Static Router for getting swap quotes without executing transactions
    IPendleStaticRouter private constant _STATIC_ROUTER =
        IPendleStaticRouter(0x263833d47eA3fA4a30f269323aba6a107f9eB14C);

    // ===============================================================
    // Constructor
    // ===============================================================

    constructor() AprOracleBase("Pendle PT Maxi Apr Oracle", address(0)) {}

    // ===============================================================
    // APR Oracle
    // ===============================================================

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev This implementation assumes that `asset == PENDLE_TOKEN`
     * @dev This implementation is for Ethereum mainnet and may not work correctly on other chains
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256) {
        // Cast the strategy into its interface
        IStrategyInterface _s = IStrategyInterface(_strategy);

        // Get the Pendle Market
        IPendleMarket _lp = IPendleMarket(_s.markets(_s.principalToken()));

        // If the Market is expired, return 0
        if (_lp.isExpired()) return 0;

        // Get the Pendle Oracle
        IPendleOracle _oracle = IPendleOracle(_s.ORACLE());

        // Price the PT in terms of Asset (price is always in WAD)
        uint256 _ptPerAsset = (_WAD * _WAD) / _oracle.getPtToAssetRate(address(_lp), _TWAP_DURATION);

        // If delta > 0 (deposit), simulate buying PT with the new assets to get the actual
        // PT/Asset rate after price impact. If delta < 0 (withdrawal), simulate selling the
        // equivalent PT amount back to assets to capture the price impact of the exit.
        // If delta == 0, use the oracle's TWAP rate as-is
        if (_delta > 0) {
            // Cache the amount in
            uint256 _amountIn = uint256(_delta);

            // Asset --> PT
            (uint256 _ptOut,,,,) = _STATIC_ROUTER.swapExactTokenForPtStatic(address(_lp), _s.PENDLE_TOKEN(), _amountIn);

            // Just in case, so we don't revert
            if (_ptOut == 0) return 0;

            // PT per Asset after price impact
            _ptPerAsset = (_ptOut * _WAD) / _amountIn;
        } else if (_delta < 0) {
            // Cache the Asset amount
            uint256 _assetAmount = uint256(-_delta);

            // Asset --> PT
            uint256 _ptIn = (_assetAmount * _ptPerAsset) / _WAD;

            // Just in case, so we don't revert
            if (_ptIn == 0) return 0;

            // PT --> Asset
            (uint256 _assetOut,,,,) = _STATIC_ROUTER.swapExactPtForTokenStatic(address(_lp), _ptIn, _s.PENDLE_TOKEN());

            // Just in case, so we don't revert
            if (_assetOut == 0) return 0;

            // PT per Asset after price impact
            _ptPerAsset = (_ptIn * _WAD) / _assetOut;
        }

        // Fixed return until maturity = rate - 1
        if (_ptPerAsset <= _WAD) return 0;

        // Calculate the time to expiry
        uint256 _timeToExpiry = _lp.expiry() - block.timestamp;

        // APR = (rate - 1) * YEAR / timeToMaturity
        return (_ptPerAsset - _WAD) * _SECONDS_PER_YEAR / _timeToExpiry;
    }

}
