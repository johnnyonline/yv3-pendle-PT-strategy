// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMetaExchange} from "./interfaces/IMetaExchange.sol";

import {ERC20, PendlePTStrategy} from "./Strategy.sol";

contract MetaExchangeStrategy is PendlePTStrategy {

    using SafeERC20 for ERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice 10 ** asset.decimals()
    uint256 internal immutable _ASSET_SCALE;

    /// @notice 10 ** PENDLE_TOKEN.decimals()
    uint256 internal immutable _PENDLE_TOKEN_SCALE;

    /// @notice Pendle's "pyYtLpOracle" Oracle on mainnet
    address private constant _ORACLE = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2;

    /// @notice SMS address
    /// @dev Used as the `GOV` address (only address that can call `rollover()`)
    address private constant _SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    /// @notice The Meta Exchange contract
    IMetaExchange public constant META_EXCHANGE = IMetaExchange(0x3E7A91F87c1b6C9D8FA806235fd69Aa0D7577caA);

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
    ) PendlePTStrategy(_asset, _pendleToken, _market, _ORACLE, _SMS, _name) {
        // Cache decimal scales for 1:1 decimal-adjusted pricing
        _ASSET_SCALE = 10 ** asset.decimals();
        _PENDLE_TOKEN_SCALE = 10 ** PENDLE_TOKEN.decimals();

        // Approve the MetaExchange to pull both sides of the swap
        asset.forceApprove(address(META_EXCHANGE), type(uint256).max);
        PENDLE_TOKEN.forceApprove(address(META_EXCHANGE), type(uint256).max);
    }

    // ===============================================================
    // Internal mutated functions
    // ===============================================================

    /// @inheritdoc PendlePTStrategy
    function _convertAssetToPendleToken(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;

        // asset --> Pendle token
        META_EXCHANGE.exchange(address(asset), address(PENDLE_TOKEN), _amount, 0);
    }

    /// @inheritdoc PendlePTStrategy
    function _convertPendleTokenToAsset(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;

        // Pendle token --> asset
        META_EXCHANGE.exchange(address(PENDLE_TOKEN), address(asset), _amount, 0);
    }

    // ===============================================================
    // Internal view functions
    // ===============================================================

    /// @inheritdoc PendlePTStrategy
    function _pendleTokenInAsset(
        uint256 _pendleTokenAmount
    ) internal view override returns (uint256) {
        // 1:1 value, adjusted for decimals
        return _pendleTokenAmount * _ASSET_SCALE / _PENDLE_TOKEN_SCALE;
    }

}
