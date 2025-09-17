// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function openDeposits() external view returns (bool);
    function openWithdrawals() external view returns (bool);
    function shouldClaimYT() external view returns (bool);
    function auction() external view returns (address);
    function maxYTToSell() external view returns (uint256);
    function allowed(address _address) external view returns (bool);
    function LP() external view returns (address);
    function YT() external view returns (address);
    function PT() external view returns (address);
    function SY() external view returns (address);
    function ROUTER() external view returns (address);
    function DUST_THRESHOLD() external view returns (uint256);
    function balanceOfPT() external view returns (uint256);
    function kickAuction(address _token) external returns (uint256);
    function allowDeposits() external;
    function allowWithdrawals() external;
    function setAllowed(address _address) external;
    function setShouldClaimYT(bool _shouldClaimYT) external;
    function setMaxYTToSell(uint256 _maxYTToSell) external;
    function setAuction(address _auction) external;
}
