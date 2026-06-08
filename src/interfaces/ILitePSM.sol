// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

/// @notice Sky LitePSM (USDC <-> DAI, 1:1, no fee) interface
interface ILitePSM {

    function sellGem(
        address usr,
        uint256 gemAmt
    ) external returns (uint256 daiOutWad);

    function buyGem(
        address usr,
        uint256 gemAmt
    ) external returns (uint256 daiInWad);

}
