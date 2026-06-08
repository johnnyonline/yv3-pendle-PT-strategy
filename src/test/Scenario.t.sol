// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IPendleStandardizedYield} from "../interfaces/IPendle.sol";

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

contract ScenarioTest is Setup {

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    // IStrategyInterface public deployedStrategy = IStrategyInterface(0x4C0e4d3cB62B91afBbf1Fe8e830f98A513c7234b);

    function setUp() public virtual override {
        uint256 _blockNumber = 24_486_708; // Caching for faster tests
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _blockNumber));
    }

    function test_scenario() public view {
        // address _newMarket = 0x11AA6742bC3AFD713e7Fd3f0d3B1f7507Cf2aD12;
        // deployedStrategy.rollover(_newMarket);

        // function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals);
        IPendleStandardizedYield sy = IPendleStandardizedYield(0x9F30507C264Cc6EB5bE35b18ff9AD7B4539Aa920);
        (IPendleStandardizedYield.AssetType assetType, address assetAddress, uint8 assetDecimals) = sy.assetInfo();
        // console2.log("assetType", uint256(assetType));
        console2.log("assetAddress", assetAddress);
        // console2.log("assetDecimals", uint256(assetDecimals));
    }

}
