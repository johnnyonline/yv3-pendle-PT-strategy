// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IPendleMarket} from "../src/interfaces/IPendle.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

import {PendlePTStrategy as Strategy} from "../src/Strategy.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/Deploy.s.sol:Deploy --verify -g 150 --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

// verify:
// --constructor-args $(cast abi-encode "constructor(address,string,address,address,address)" 0x29219dd400f2Bf60E5a23d13Be72B486D4038894 "Silo Lender S/USDC (8)" 0x4E216C15697C1392fE59e1014B009505E05810Df 0x0dd368Cd6D8869F2b21BA3Cb4fd7bA107a2e3752 0x71ccF86Cf63A5d55B12AA7E7079C22f39112Dd7D)
// forge verify-contract --etherscan-api-key $KEY --watch --chain-id 42161 --compiler-version v0.8.18+commit.87f61d96 --verifier-url https://api.arbiscan.io/api 0x9a5eca1b228e47a15BD9fab07716a9FcE9Eebfb5 src/ERC404/BaseERC404.sol:BaseERC404

contract Deploy is Script {

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DEPLOYER = 0x420ACF637D662b80cca8bEfb327AA24039E7e0Fa; // johnnyonline.eth
    address private constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7; // sms mainnet
    address private constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E; // yHaaS mainnet
    address private constant EMERGENCY_ADMIN = SMS;
    address private constant PERFORMANCE_FEE_RECIPIENT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69; // Accountant mainnet
    address private constant CHAD = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52; // Chad mainnet
    address private constant YVUSD = 0x696d02Db93291651ED510704c9b286841d506987;

    // USD3-MAINNET-DEC2026
    address public constant LP = 0x4A5067C3fF1abb7449244025B0e37fEAF77D8E3e;
    address private constant ORACLE = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2; // pyYtLpOracle mainnet

    function run() external {
        uint256 _privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_privateKey);
        require(_deployer == DEPLOYER, "!deployer");

        vm.startBroadcast(_privateKey);

        // Bump the Pendle oracle cardinality
        IPendleMarket(LP).increaseObservationsCardinalityNext(165);

        address _strategy = address(
            new Strategy(
                USDC, // asset
                USDC, // pendleToken
                LP, // market
                ORACLE, // oracle
                CHAD, // gov
                "USD3 Pendle PT Maxi" // name
            )
        );

        IStrategyInterface strategy = IStrategyInterface(_strategy);
        strategy.setMinTendInterval(1 days);
        strategy.setAllowed(_deployer);
        strategy.setAllowed(YVUSD);
        strategy.setKeeper(KEEPER);
        strategy.setPerformanceFeeRecipient(PERFORMANCE_FEE_RECIPIENT);
        strategy.setEmergencyAdmin(EMERGENCY_ADMIN);
        strategy.setPendingManagement(SMS);

        vm.stopBroadcast();

        console.log("-----------------------------");
        console.log("Strategy deployed at: ", _strategy);
        console.log("-----------------------------");
    }

}

// USD3-MAINNET-MAR2026
// Strategy deployed at:  0x4C0e4d3cB62B91afBbf1Fe8e830f98A513c7234b

// USD3-MAINNET-DEC2026
// Strategy deployed at:  0x62ebE2ca290DB3B649c390847f8204196771B438
