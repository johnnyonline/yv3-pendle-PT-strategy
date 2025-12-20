// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IPPYLpOracle as IPendleOracle} from "@pendle-core-v2/interfaces/IPPYLpOracle.sol";

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

contract OperationTest is Setup {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(management);
        strategy.allowWithdrawals();
    }

    function test_setupStrategyOK() public view {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertFalse(strategy.allowed(address(0)));
        assertTrue(strategy.allowed(user));
        assertTrue(strategy.openWithdrawals()); // Open on setUp
        assertTrue(strategy.auction() == address(0));
        assertEq(strategy.maxPendleTokenToSwap(), type(uint256).max);
        assertEq(strategy.minSwapInterval(), type(uint256).max);
        assertEq(strategy.lastSwap(), 0);
        assertEq(strategy.markets(address(PT)), LP);
        assertEq(strategy.principalToken(), PT);
        assertEq(strategy.SY(), SY);
        assertEq(strategy.PENDLE_TOKEN(), address(asset));
        assertEq(strategy.balanceOfPT(), 0);
        assertEq(strategy.balanceOfPendleToken(), 0);
    }

    function test_invalidDeployment() public {
        // Invalid pendleToken (not supported)
        vm.expectRevert("!tokenOut");
        strategyFactory.newStrategy(address(asset), tokenAddrs["YFI"], LP, ORACLE, "Tokenized Strategy");

        // Wrong market (different SY)
        address wrongMarket = 0x307c15f808914Df5a5DbE17E5608f84953fFa023; // cUSD market
        vm.expectRevert("!tokenOut");
        strategyFactory.newStrategy(address(asset), address(asset), wrongMarket, ORACLE, "Tokenized Strategy");

        // Expire market
        _simulateMarketExpiration();

        vm.expectRevert("expired");
        strategyFactory.newStrategy(address(asset), address(asset), LP, ORACLE, "Tokenized Strategy");
    }

    function test_invalidDeployment_oracleNotReady() public {
        // Mock oracle: increaseCardinalityRequired = true
        vm.mockCall(ORACLE, abi.encodeWithSelector(IPendleOracle.getOracleState.selector), abi.encode(true, 165, true));

        vm.expectRevert("increaseCardinalityRequired");
        strategyFactory.newStrategy(address(asset), address(asset), LP, ORACLE, "Tokenized Strategy");

        vm.clearMockedCalls();

        // Mock oracle: oldestObservationSatisfied = false
        vm.mockCall(
            ORACLE, abi.encodeWithSelector(IPendleOracle.getOracleState.selector), abi.encode(false, 165, false)
        );

        vm.expectRevert("!oldestObservationNotSatisfied");
        strategyFactory.newStrategy(address(asset), address(asset), LP, ORACLE, "Tokenized Strategy");
    }

    function test_operation(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Tend to buy PT
        vm.prank(keeper);
        strategy.tend();

        // Skip 10 days to accrue yield
        skip(10 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Make sure user did not lose more than max
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");
    }

    function test_operation_withdrawAfterExpiry(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Tend to buy PT
        vm.prank(keeper);
        strategy.tend();

        // Skip 10 days to accrue yield
        skip(10 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 totalAssetsAfterProfit = strategy.totalAssets();
        assertGe(totalAssetsAfterProfit, _amount, "!totalAssets");

        // Expire market
        _simulateMarketExpiration();

        // Report doesn't change anything
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_tend_noSwapWhenDisabled(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Disable swapping
        vm.prank(management);
        strategy.setMaxPendleTokenToSwap(0);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.balanceOfPT(), 0, "!balanceOfPT");
        assertEq(strategy.balanceOfPendleToken(), _amount, "!balanceOfPendleToken");

        // Tend does nothing other than updating lastSwap
        vm.prank(keeper);
        strategy.tend();

        // No PT acquired
        assertEq(strategy.balanceOfPT(), 0, "!balanceOfPT");
        assertEq(strategy.balanceOfPendleToken(), _amount, "!balanceOfPendleToken");

        // Check lastSwap updated
        assertEq(strategy.lastSwap(), block.timestamp, "!lastSwap");
    }

    function test_tend_noSwapAfterExpiry(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Expire market
        _simulateMarketExpiration();

        // Tend reverts after expiry
        vm.prank(keeper);
        vm.expectRevert();
        strategy.tend();
    }

    function test_operation_freeProportionalShare(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        address patientUser = address(42069);

        // Allow patientUser to deposit
        vm.prank(management);
        strategy.setAllowed(patientUser);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Deposit into strategy for patientUser
        mintAndDepositIntoStrategy(strategy, patientUser, _amount);

        assertEq(strategy.totalAssets(), _amount * 2, "!totalAssets");

        // Tend to buy PT
        vm.prank(keeper);
        strategy.tend();

        // Skip 10 days to accrue yield
        skip(10 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Make sure user did not lose more than max
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");

        // Expire market
        _simulateMarketExpiration();

        balanceBefore = asset.balanceOf(patientUser);

        // Withdraw all funds
        vm.prank(patientUser);
        strategy.redeem(_amount, patientUser, patientUser);

        assertGt(asset.balanceOf(patientUser), balanceBefore + _amount, "!final balance patientUser");
    }

    function test_profitableReport(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Tend to buy PT
        vm.prank(keeper);
        strategy.tend();

        // Skip 10 days to accrue yield
        skip(10 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Make sure user did not lose more than max
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");
    }

    function test_profitableReport_withFees(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Tend to buy PT
        vm.prank(keeper);
        strategy.tend();

        // Skip 10 days to accrue yield
        skip(10 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Make sure user did not lose more than max
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

        checkStrategyTotals(strategy, 0, 0, 0);

        // Make sure fee recipient did not lose more than max
        assertApproxEqRel(
            asset.balanceOf(performanceFeeRecipient), balanceBefore + expectedShares, MAX_LOSS, "!perf fee out"
        );
    }

    function test_tendTrigger_returnsFalse_whenShutdown(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup: enable tend trigger
        vm.startPrank(management);
        strategy.setMinSwapInterval(0);
        vm.stopPrank();

        // Deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Verify trigger is true before shutdown
        (bool trigger,) = strategy.tendTrigger();
        assertTrue(trigger);

        // Shutdown
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Trigger should be false
        (trigger,) = strategy.tendTrigger();
        assertFalse(trigger);
    }

    function test_tendTrigger_returnsFalse_whenExpired(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup: enable tend trigger
        vm.prank(management);
        strategy.setMinSwapInterval(0);

        // Deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Verify trigger is true before expiry
        (bool trigger,) = strategy.tendTrigger();
        assertTrue(trigger);

        // Expire market
        _simulateMarketExpiration();

        // Trigger should be false
        (trigger,) = strategy.tendTrigger();
        assertFalse(trigger);
    }

    function test_tendTrigger_returnsFalse_whenSwapDisabled(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup: enable tend trigger but disable swap
        vm.startPrank(management);
        strategy.setMinSwapInterval(0);
        strategy.setMaxPendleTokenToSwap(0);
        vm.stopPrank();

        // Deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Trigger should be false
        (bool trigger,) = strategy.tendTrigger();
        assertFalse(trigger);
    }

    function test_tendTrigger_returnsFalse_whenIntervalNotPassed(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup: enable tend trigger with interval
        vm.prank(management);
        strategy.setMinSwapInterval(1 days);

        // Deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Trigger should be true (lastSwap is 0)
        (bool trigger,) = strategy.tendTrigger();
        assertTrue(trigger);

        // Tend to update lastSwap
        vm.prank(keeper);
        strategy.tend();

        // Trigger should be false (interval not passed)
        (trigger,) = strategy.tendTrigger();
        assertFalse(trigger);

        // Skip half the interval
        skip(12 hours);
        (trigger,) = strategy.tendTrigger();
        assertFalse(trigger);

        // Skip past interval
        skip(13 hours);
        (trigger,) = strategy.tendTrigger();
        assertTrue(trigger);
    }

    function test_tendTrigger_returnsFalse_whenNoFunds() public {
        // Setup: enable tend trigger
        vm.prank(management);
        strategy.setMinSwapInterval(0);

        // No deposit, no funds
        (bool trigger,) = strategy.tendTrigger();
        assertFalse(trigger);
    }

    function test_tendTrigger_returnsTrue_whenAllConditionsMet(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup: enable tend trigger
        vm.prank(management);
        strategy.setMinSwapInterval(0);

        // Deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // All conditions met
        (bool trigger,) = strategy.tendTrigger();
        assertTrue(trigger);
    }

    function test_tendTrigger_returnsFalse_whenBelowMinAmountToSell(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Setup: enable tend trigger
        vm.prank(management);
        strategy.setMinSwapInterval(0);

        // Set minAmountToSell to be greater than deposit amount
        vm.prank(management);
        strategy.setMinAmountToSell(_amount + 1);

        // Deposit amount (below minAmountToSell)
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Trigger should be false (below minAmountToSell)
        (bool trigger,) = strategy.tendTrigger();
        assertFalse(trigger);
    }

}
