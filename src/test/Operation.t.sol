// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

contract OperationTest is Setup {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(management);
        strategy.allowWithdrawals();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertFalse(strategy.openDeposits());
        assertTrue(strategy.openWithdrawals()); // Open on setUp
        assertFalse(strategy.shouldClaimYT());
        assertTrue(strategy.auction() == address(0));
        assertEq(strategy.maxYTToSell(), 0);
        assertEq(strategy.LP(), LP);
        assertEq(strategy.YT(), YT);
        assertEq(strategy.PT(), PT);
        assertEq(strategy.SY(), SY);
        assertEq(strategy.ROUTER(), ROUTER);
        assertEq(strategy.DUST_THRESHOLD(), 10_000);
        assertEq(strategy.balanceOfPT(), 0);
    }

    function test_invalidDeployment() public {
        vm.expectRevert("!valid");
        strategyFactory.newStrategy(tokenAddrs["YFI"], LP, "Tokenized Strategy");

        address wrongMarket = 0x83B2C0b470Ff5f2a60D2BF2AE109766E8bb3E862; // ysyBOLD market

        vm.expectRevert("!valid");
        strategyFactory.newStrategy(address(asset), wrongMarket, "Tokenized Strategy");

        // Expire market
        _simulateMarketExpiration();

        vm.expectRevert("expired");
        strategyFactory.newStrategy(address(asset), LP, "Tokenized Strategy");
    }

    function test_operation(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

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

    function test_operation_withdrawAfterExpiry_noLoss(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

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
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        assertEq(strategy.totalAssets(), totalAssetsAfterProfit, "!totalAssets");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_operation_noSwapOnLowYT(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Make sure we sell the YTs
        vm.prank(management);
        strategy.setMaxYTToSell(type(uint256).max);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Get rid of some YT such that we're below dust threshold
        vm.startPrank(address(strategy));
        ERC20(YT).transfer(address(420), ERC20(YT).balanceOf(address(strategy)) - strategy.DUST_THRESHOLD());
        vm.stopPrank();

        assertEq(ERC20(YT).balanceOf(address(strategy)), strategy.DUST_THRESHOLD());
        assertEq(ERC20(SY).balanceOf(address(strategy)), 0);

        // Report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        assertEq(ERC20(YT).balanceOf(address(strategy)), strategy.DUST_THRESHOLD());
        assertEq(ERC20(SY).balanceOf(address(strategy)), 0);
    }

    function test_operation_sellYT(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Make sure we sell the YTs
        vm.prank(management);
        strategy.setMaxYTToSell(type(uint256).max);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        uint256 ytBefore = ERC20(YT).balanceOf(address(strategy));
        assertGt(ytBefore, strategy.DUST_THRESHOLD());

        // Report to sell YT
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        assertLt(ERC20(YT).balanceOf(address(strategy)), ytBefore);
        assertGt(ERC20(YT).balanceOf(address(strategy)), 0); // We still have some YT bc of redeploying SY profits
        assertEq(ERC20(SY).balanceOf(address(strategy)), 0);
    }

    function test_operation_noSwapAfterExpiry(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Make sure we sell the YTs
        vm.prank(management);
        strategy.setMaxYTToSell(type(uint256).max);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        uint256 ytBefore = ERC20(YT).balanceOf(address(strategy));
        assertGt(ytBefore, strategy.DUST_THRESHOLD());

        // Expire market
        _simulateMarketExpiration();

        // Report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        assertEq(ERC20(YT).balanceOf(address(strategy)), ytBefore);
    }

    function test_operation_noDeployAfterExpiry(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Make sure we sell the YTs
        vm.prank(management);
        strategy.setMaxYTToSell(type(uint256).max);

        // Remove performance fee
        setFees(0, 0);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // Expire market
        _simulateMarketExpiration();

        // Airdrop SY, simulates claiming yield after expiry
        airdrop(ERC20(SY), address(strategy), 100_000);

        // Report profit from the SY airdrop
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // Make sure all funds were distributed
        assertEq(ERC20(SY).balanceOf(address(strategy)), 0);
        assertEq(ERC20(LP).balanceOf(address(strategy)), 0);
        assertEq(ERC20(PT).balanceOf(address(strategy)), 0);
        assertGt(ERC20(YT).balanceOf(address(strategy)), 0); // We do have some worthless YT
        assertEq(strategy.totalSupply(), 0);
        assertEq(strategy.totalAssets(), 0);
        assertEq(asset.balanceOf(address(strategy)), 0);
    }

    function test_operation_noDeployOnLowSY(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        assertEq(ERC20(SY).balanceOf(address(strategy)), 0);

        // Get rid of all YT
        vm.startPrank(address(strategy));
        ERC20(YT).transfer(address(420), ERC20(YT).balanceOf(address(strategy)));
        vm.stopPrank();

        // Airdrop SY dust
        airdrop(ERC20(SY), address(strategy), strategy.DUST_THRESHOLD());

        // Report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        assertEq(ERC20(SY).balanceOf(address(strategy)), strategy.DUST_THRESHOLD());
    }

    function test_operation_claimYT(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Set claim YT to true
        vm.prank(management);
        strategy.setShouldClaimYT(true);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);
        vm.roll(block.number + 1); // Roll so PY index can update

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

    function test_operation_depositAfterExpiry(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Expire market
        _simulateMarketExpiration();

        // Airdrop some asset to user
        airdrop(asset, user, _amount);

        vm.prank(user);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(_amount, user);
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

        // Earn Interest
        skip(1 days);

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

        assertEq(asset.balanceOf(patientUser), balanceBefore + _amount, "!final balance patientUser");
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Make sure we sell YT to earn the profit
        vm.prank(management);
        strategy.setMaxYTToSell(type(uint256).max);

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

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Make sure we sell YT to earn the profit
        vm.prank(management);
        strategy.setMaxYTToSell(type(uint256).max);

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

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(performanceFeeRecipient), expectedShares, "!perf fee out");
    }

    function test_tendTrigger(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

}
