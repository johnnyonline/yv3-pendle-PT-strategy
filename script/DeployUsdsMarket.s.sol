// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {StrategyFactory} from "../src/StrategyFactory.sol";
import {IMorphoChainlinkOracleV2Factory} from "../src/interfaces/IMorphoChainlinkOracleV2Factory.sol";
import {IPendleMarket} from "../src/interfaces/IPendle.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployUsdsMarket.s.sol:DeployUsdsMarket --verify -g 150 --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract DeployUsdsMarket is Script {

    address private constant DEPLOYER = 0x420ACF637D662b80cca8bEfb327AA24039E7e0Fa; // johnnyonline.eth

    address private constant FACTORY = address(0x57ACE4ca25EE51901380b61a196870BbDDA9b816);

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // SUSDS-MAINNET-NOV2026
    address private constant LP = 0x9C560eBaF78e596cbcC27411d633a74D628dd7dC;

    // Morpho oracle deployment (base = collateral = USDS, quote = loan = USDC)
    address private constant MORPHO_ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    address private constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private constant USDS_USD_FEED = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;

    function run() external {
        uint256 _privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_privateKey);
        require(_deployer == DEPLOYER, "!deployer");
        require(FACTORY != address(0), "!factory");

        vm.startBroadcast(_privateKey);

        // Bump the Pendle oracle cardinality
        IPendleMarket(LP).increaseObservationsCardinalityNext(165);

        // Deploy the Morpho oracle pricing USDS (collateral) in USDC (loan) terms
        address _oracle = IMorphoChainlinkOracleV2Factory(MORPHO_ORACLE_FACTORY).createMorphoChainlinkOracleV2(
            address(0), // baseVault
            1, // baseVaultConversionSample
            USDS_USD_FEED, // baseFeed1
            address(0), // baseFeed2
            18, // baseTokenDecimals (USDS)
            address(0), // quoteVault
            1, // quoteVaultConversionSample
            USDC_USD_FEED, // quoteFeed1
            address(0), // quoteFeed2
            6, // quoteTokenDecimals (USDC)
            bytes32(0) // salt
        );

        // Deploy the strategy through the factory
        address _strategy = StrategyFactory(FACTORY).newStrategy(
            USDC, // asset
            USDS, // pendleToken
            LP, // market
            _oracle, // oracle
            "sUSDS Pendle PT Maxi" // name
        );

        vm.stopBroadcast();

        console.log("-----------------------------");
        console.log("Morpho oracle deployed at: ", _oracle);
        console.log("Strategy deployed at: ", _strategy);
        console.log("-----------------------------");
    }

}
