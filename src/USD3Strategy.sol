// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

import {ERC20, Math, PendlePTStrategy} from "./Strategy.sol";

contract USD3Strategy is PendlePTStrategy {

    // ===============================================================
    // Constant
    // ===============================================================

    /// @notice Strategy name
    string private constant _NAME = "USD3 Pendle PT Maxi";

    /// @notice Pendle's "pyYtLpOracle" Oracle on mainnet
    address private constant _ORACLE = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2;

    /// @notice SMS address
    /// @dev Used as the `GOV` address (only address that can call `rollover()`)
    address private constant _SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    /// @notice USDC token address
    /// @dev The strategy's underlying asset
    ERC20 private constant _USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /// @notice USD3 token address
    /// @dev The strategy's "Pendle token"
    IStrategy private constant _USD3 = IStrategy(0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc);

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @param _market The market address
    constructor(
        address _market
    ) PendlePTStrategy(address(_USDC), address(_USD3), _market, _ORACLE, _SMS, _NAME) {
        require(asset == _USDC, "!asset");
        require(address(PENDLE_TOKEN) == address(_USD3), "!PENDLE_TOKEN");
    }

    // ===============================================================
    // Internal mutated functions
    // ===============================================================

    /// @inheritdoc PendlePTStrategy
    function _convertAssetToPendleToken(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;

        // Cap amount to the available deposit limit of USD3
        _amount = Math.min(_amount, _USD3.availableDepositLimit(address(this)));
        if (_amount == 0) return;

        // USDC --> USD3
        _USD3.deposit(_amount, address(this));
    }

    /// @inheritdoc PendlePTStrategy
    function _convertPendleTokenToAsset(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;

        // Get the available withdraw amount of USDC from USD3
        uint256 _availableUSDCToWithdraw = _USD3.availableWithdrawLimit(address(this));

        // Convert to USD3 shares
        uint256 _availableUSD3ToRedeem = _USD3.convertToShares(_availableUSDCToWithdraw);

        // Cap amount to available withdraw limit of USD3
        _amount = Math.min(_amount, _availableUSD3ToRedeem);
        if (_amount == 0) return;

        // USD3 --> USDC
        _USD3.redeem(_amount, address(this), address(this));
    }

    // ===============================================================
    // Internal view functions
    // ===============================================================

    /// @inheritdoc PendlePTStrategy
    function _pendleTokenInAsset(
        uint256 _pendleTokenAmount
    ) internal view override returns (uint256) {
        // USD3 --> USDC
        return _USD3.convertToAssets(_pendleTokenAmount);
    }

}
