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
    function minPendleTokenToTrigger() external view returns (uint256);
    function maxPendleTokenToSwap() external view returns (uint256);
    function minTendInterval() external view returns (uint256);
    function minAmountToSell() external view returns (uint256);
    function lastTend() external view returns (uint256);
    function swapSlippageBPS() external view returns (uint256);
    function pendleTokenDiscountBPS() external view returns (uint256);
    function oracle() external view returns (address);
    function allowed(
        address
    ) external view returns (bool);

    // ===============================================================
    // Constants
    // ===============================================================

    function GOV() external view returns (address);
    function PENDLE_TOKEN() external view returns (address);
    function SY() external view returns (address);
    function ORACLE() external view returns (address);

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

    function setDoHealthCheck(
        bool _doHealthCheck
    ) external;
    function allowWithdrawals(
        bool _allowWithdrawals
    ) external;
    function setAllowed(
        address _address
    ) external;
    function setMinPendleTokenToTrigger(
        uint256 _minPendleTokenToTrigger
    ) external;
    function setMaxPendleTokenToSwap(
        uint256 _maxPendleTokenToSwap
    ) external;
    function setMinTendInterval(
        uint256 _minTendInterval
    ) external;
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external;
    function setSwapSlippageBPS(
        uint256 _swapSlippageBPS
    ) external;
    function setPendleTokenDiscountBPS(
        uint256 _pendleTokenDiscountBPS
    ) external;
    function setAuction(
        address _auction
    ) external;
    function setOracle(
        address _oracle
    ) external;
    function rollover(
        address _newMarket
    ) external;

}
