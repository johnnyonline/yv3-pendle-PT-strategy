// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {

    function markets(
        address
    ) external view returns (address);
    function openWithdrawals() external view returns (bool);
    function principalToken() external view returns (address);
    function auction() external view returns (address);
    function maxPendleTokenToSwap() external view returns (uint256);
    function minSwapInterval() external view returns (uint256);
    function minAmountToSell() external view returns (uint256);
    function lastSwap() external view returns (uint256);
    function swapSlippageBPS() external view returns (uint256);
    function allowed(
        address
    ) external view returns (bool);

    // ===============================================================
    // Constants
    // ===============================================================

    function PENDLE_TOKEN() external view returns (address);
    function SY() external view returns (address);

    // ===============================================================
    // View functions
    // ===============================================================

    function balanceOfPT() external view returns (uint256);
    function balanceOfPendleToken() external view returns (uint256);

    // ===============================================================
    // Keeper functions
    // ===============================================================

    function kickAuction(
        address _token
    ) external returns (uint256);

    // ===============================================================
    // Management functions
    // ===============================================================

    function allowWithdrawals() external;
    function setAllowed(
        address _address
    ) external;
    function setMaxPendleTokenToSwap(
        uint256 _maxPendleTokenToSwap
    ) external;
    function setMinSwapInterval(
        uint256 _minSwapInterval
    ) external;
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external;
    function setSwapSlippageBPS(
        uint256 _swapSlippageBPS
    ) external;
    function setAuction(
        address _auction
    ) external;
    function rollover(
        address _newMarket
    ) external;

}
