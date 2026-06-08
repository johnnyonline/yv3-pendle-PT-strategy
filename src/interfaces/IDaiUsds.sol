// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

/// @notice Sky DAI <-> USDS converter (1:1) interface
interface IDaiUsds {

    function daiToUsds(
        address usr,
        uint256 wad
    ) external;

    function usdsToDai(
        address usr,
        uint256 wad
    ) external;

}
