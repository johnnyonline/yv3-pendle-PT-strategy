// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {
    IPMarket as IPendleMarket,
    IPPrincipalToken as IPendlePrincipalToken,
    IStandardizedYield as IPendleStandardizedYield
} from "@pendle-core-v2/interfaces/IPMarket.sol";

import {IPPYLpOracle as IPendleOracle} from "@pendle-core-v2/interfaces/IPPYLpOracle.sol";

interface IPendleStaticRouter {

    function swapExactTokenForPtStatic(
        address market,
        address tokenIn,
        uint256 amountTokenIn
    )
        external
        view
        returns (
            uint256 netPtOut,
            uint256 netSyMinted,
            uint256 netSyFee,
            uint256 priceImpact,
            uint256 exchangeRateAfter
        );

    function swapExactPtForTokenStatic(
        address market,
        uint256 exactPtIn,
        address tokenOut
    )
        external
        view
        returns (
            uint256 netTokenOut,
            uint256 netSyToRedeem,
            uint256 netSyFee,
            uint256 priceImpact,
            uint256 exchangeRateAfter
        );

}
