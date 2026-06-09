// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {StrategyFactory} from "../src/StrategyFactory.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployFactory.s.sol:DeployFactory --verify -g 150 --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract DeployFactory is Script {

    address private constant DEPLOYER = 0x420ACF637D662b80cca8bEfb327AA24039E7e0Fa; // johnnyonline.eth
    address private constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7; // sms mainnet
    address private constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E; // yHaaS mainnet
    address private constant EMERGENCY_ADMIN = SMS;
    address private constant PERFORMANCE_FEE_RECIPIENT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69; // Accountant mainnet
    address private constant CHAD = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52; // Chad mainnet
    address private constant MANAGEMENT = SMS;

    function run() external {
        uint256 _privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_privateKey);
        require(_deployer == DEPLOYER, "!deployer");

        vm.startBroadcast(_privateKey);

        address _factory = address(
            new StrategyFactory(
                DEPLOYER, // management
                PERFORMANCE_FEE_RECIPIENT, // performanceFeeRecipient
                KEEPER, // keeper
                EMERGENCY_ADMIN, // emergencyAdmin
                CHAD // gov
            )
        );

        vm.stopBroadcast();

        console.log("-----------------------------");
        console.log("StrategyFactory deployed at: ", _factory);
        console.log("-----------------------------");
    }

}
