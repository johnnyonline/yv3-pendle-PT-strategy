// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

interface IMorphoChainlinkOracleV2Factory {

    /// @notice Deploy a new MorphoChainlinkOracleV2
    /// @dev The base asset is the collateral token and the quote asset the loan token
    /// @param baseVault Base ERC4626 vault (address zero to omit)
    /// @param baseVaultConversionSample Sample of base vault shares to convert (1 if not a vault)
    /// @param baseFeed1 First base feed (address zero if price = 1)
    /// @param baseFeed2 Second base feed (address zero if price = 1)
    /// @param baseTokenDecimals Base token decimals
    /// @param quoteVault Quote ERC4626 vault (address zero to omit)
    /// @param quoteVaultConversionSample Sample of quote vault shares to convert (1 if not a vault)
    /// @param quoteFeed1 First quote feed (address zero if price = 1)
    /// @param quoteFeed2 Second quote feed (address zero if price = 1)
    /// @param quoteTokenDecimals Quote token decimals
    /// @param salt The salt used for CREATE2
    /// @return oracle The deployed oracle
    function createMorphoChainlinkOracleV2(
        address baseVault,
        uint256 baseVaultConversionSample,
        address baseFeed1,
        address baseFeed2,
        uint256 baseTokenDecimals,
        address quoteVault,
        uint256 quoteVaultConversionSample,
        address quoteFeed1,
        address quoteFeed2,
        uint256 quoteTokenDecimals,
        bytes32 salt
    ) external returns (address oracle);

}
