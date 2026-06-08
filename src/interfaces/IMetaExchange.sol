// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

interface IMetaExchange {

    /// @notice Swap `amountIn` of `from` for at least `amountOutMin` of `to`
    /// @param from The token to swap from
    /// @param to The token to swap to
    /// @param amountIn The amount of `from` to swap
    /// @param amountOutMin The minimum acceptable amount of `to` out
    /// @return amountOut The amount of `to` received
    function exchange(
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut);

}
