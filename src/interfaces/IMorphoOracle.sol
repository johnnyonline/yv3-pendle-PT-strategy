// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

interface IMorphoOracle {

    /// @notice Price of 1 unit of collateral token quoted in loan token, scaled by `1e36`
    function price() external view returns (uint256);

}
