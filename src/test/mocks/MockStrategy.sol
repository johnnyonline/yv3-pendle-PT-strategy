// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {PendlePTStrategy, ERC20} from "../../Strategy.sol";

interface IERC4626 {

    function convertToShares(
        uint256 assets
    ) external view returns (uint256);
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256);
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);

}

/// @notice Mock strategy that uses yBOLD as the pendle token and ysyBOLD as the asset
contract MockStrategy is PendlePTStrategy {

    constructor(
        address _asset,
        address _pendleToken,
        address _market,
        address _oracle,
        address _gov,
        string memory _name
    ) PendlePTStrategy(_asset, _pendleToken, _market, _oracle, _gov, _name) {}

    /// @notice Convert ysyBOLD to yBOLD
    function _convertAssetToPendleToken(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;
        IERC4626(address(asset)).redeem(_amount, address(this), address(this));
    }

    /// @notice Convert yBOLD to ysyBOLD
    function _convertPendleTokenToAsset(
        uint256 _amount
    ) internal override {
        if (_amount == 0) return;
        PENDLE_TOKEN.approve(address(asset), _amount);
        IERC4626(address(asset)).deposit(_amount, address(this));
    }

    /// @notice Price yBOLD in ysyBOLD
    function _pendleTokenInAsset(
        uint256 _pendleTokenAmount
    ) internal view override returns (uint256) {
        return IERC4626(address(asset)).convertToShares(_pendleTokenAmount);
    }

}
