pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(management);
        strategy.allowWithdrawals();
    }

    function test_shutdownCanWithdraw(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Tend to swap into PT
        vm.prank(keeper);
        strategy.tend();

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Make sure user did not lose more than max
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");
    }

    function test_emergencyWithdraw_maxUint(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Tend to swap into PT
        vm.prank(keeper);
        strategy.tend();

        assertGt(strategy.balanceOfPT(), 0, "!balanceOfPT");

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Emergency withdraw all PT
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // PT should be converted back to asset
        assertEq(strategy.balanceOfPT(), 0, "!balanceOfPT");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Make sure user did not lose more than max
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");
    }

}
