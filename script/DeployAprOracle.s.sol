// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {PendlePTStrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployAprOracle.s.sol:DeployAprOracle --verify -g 150 --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

// verify:
// --constructor-args $(cast abi-encode "constructor(address,string,address,address,address)" 0x29219dd400f2Bf60E5a23d13Be72B486D4038894 "Silo Lender S/USDC (8)" 0x4E216C15697C1392fE59e1014B009505E05810Df 0x0dd368Cd6D8869F2b21BA3Cb4fd7bA107a2e3752 0x71ccF86Cf63A5d55B12AA7E7079C22f39112Dd7D)
// forge verify-contract --etherscan-api-key $KEY --watch --chain-id 42161 --compiler-version v0.8.18+commit.87f61d96 --verifier-url https://api.arbiscan.io/api 0x9a5eca1b228e47a15BD9fab07716a9FcE9Eebfb5 src/ERC404/BaseERC404.sol:BaseERC404

contract DeployAprOracle is Script {

    address private constant DEPLOYER = 0x285E3b1E82f74A99D07D2aD25e159E75382bB43B; // johnnyonline.eth

    function run() external {
        uint256 _privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_privateKey);
        require(_deployer == DEPLOYER, "!deployer");

        vm.startBroadcast(_privateKey);

        address _oracle = address(new PendlePTStrategyAprOracle());

        vm.stopBroadcast();

        console.log("-----------------------------");
        console.log("APR Oracle deployed at: ", _oracle);
        console.log("-----------------------------");
    }

}

// APR Oracle deployed at:  0x7caD38C514eB1369AB5373F16D2fb469E1Fd544f