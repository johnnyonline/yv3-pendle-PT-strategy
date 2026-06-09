// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMetaExchange} from "./interfaces/IMetaExchange.sol";
import {IMorphoOracle} from "./interfaces/IMorphoOracle.sol";

import {ERC20, PendlePTStrategy} from "./Strategy.sol";

contract MetaExchangeStrategy is PendlePTStrategy {

    using SafeERC20 for ERC20;

    // ===============================================================
    // Storage
    // ===============================================================

    /// @notice Oracle pricing Pendle token in asset terms, Morpho style
    IMorphoOracle public oracle;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice The scale of the Morpho oracle price
    uint256 internal constant _ORACLE_PRICE_SCALE = 1e36;

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
    /// @param _oracle The oracle pricing PENDLE_TOKEN in asset terms
    /// @param _name The name
    constructor(
        address _asset,
        address _pendleToken,
        address _market,
        address _oracle,
        string memory _name
    ) PendlePTStrategy(_asset, _pendleToken, _market, _ORACLE, _SMS, _name) {
        // Set the oracle
        _setOracle(_oracle);

        // Approve the MetaExchange to pull both sides of the swap
        asset.forceApprove(address(META_EXCHANGE), type(uint256).max);
        PENDLE_TOKEN.forceApprove(address(META_EXCHANGE), type(uint256).max);
    }

    // ===============================================================
    // Management functions
    // ===============================================================

    /// @notice Set the oracle used to price Pendle token in asset terms
    /// @param _oracle The new oracle address
    function setOracle(
        address _oracle
    ) external onlyManagement {
        _setOracle(_oracle);
    }

    // ===============================================================
    // Internal mutated functions
    // ===============================================================

    /// @inheritdoc PendlePTStrategy
    function _convertAssetToPendleToken(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;

        // Expected Pendle token out, minus slippage tolerance
        uint256 _minAmountOut = _assetInPendleToken(_amount) * (MAX_BPS - swapSlippageBPS) / MAX_BPS;

        // asset --> Pendle token
        META_EXCHANGE.exchange(address(asset), address(PENDLE_TOKEN), _amount, _minAmountOut);
    }

    /// @inheritdoc PendlePTStrategy
    function _convertPendleTokenToAsset(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;

        // Expected asset out, minus slippage tolerance
        uint256 _minAmountOut = _pendleTokenInAsset(_amount) * (MAX_BPS - swapSlippageBPS) / MAX_BPS;

        // Pendle token --> asset
        META_EXCHANGE.exchange(address(PENDLE_TOKEN), address(asset), _amount, _minAmountOut);
    }

    /// @notice Set the oracle
    /// @param _oracle The new oracle address
    function _setOracle(
        address _oracle
    ) internal {
        require(_oracle != address(0), "!oracle");
        oracle = IMorphoOracle(_oracle);
    }

    // ===============================================================
    // Internal view functions
    // ===============================================================

    /// @inheritdoc PendlePTStrategy
    function _pendleTokenInAsset(
        uint256 _pendleTokenAmount
    ) internal view override returns (uint256) {
        // Pendle token --> asset via the oracle
        return _pendleTokenAmount * _oraclePrice() / _ORACLE_PRICE_SCALE;
    }

    /// @notice Price asset in Pendle token (inverse of `_pendleTokenInAsset`)
    /// @param _assetAmount Amount of asset to price
    /// @return Amount of Pendle token equivalent
    function _assetInPendleToken(
        uint256 _assetAmount
    ) internal view returns (uint256) {
        // asset --> Pendle token via the oracle
        return _assetAmount * _ORACLE_PRICE_SCALE / _oraclePrice();
    }

    /// @notice Get the oracle price of Pendle token in asset terms
    /// @return _price The oracle price, scaled by `_ORACLE_PRICE_SCALE`
    function _oraclePrice() internal view virtual returns (uint256) {
        return oracle.price();
    }

}
