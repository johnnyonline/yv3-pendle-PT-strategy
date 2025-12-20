// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface, IPendleMarket} from "./utils/Setup.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";

contract MockStrategyTest is Setup {

    // yBOLD market (asset = ysyBOLD, pendle token = yBOLD)
    address public constant YBOLD_MARKET = 0x83B2C0b470Ff5f2a60D2BF2AE109766E8bb3E862;

    ERC20 public pendleToken;

    function setUp() public override {
        uint256 _blockNumber = 24_049_143;
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _blockNumber));

        _setTokenAddrs();

        asset = ERC20(tokenAddrs["ysyBOLD"]);
        pendleToken = ERC20(tokenAddrs["yBOLD"]);

        // Initialize oracle for the market
        IPendleMarket(YBOLD_MARKET).increaseObservationsCardinalityNext(165);

        // Deploy mock strategy
        MockStrategy _strategy =
            new MockStrategy(address(asset), address(pendleToken), YBOLD_MARKET, ORACLE, "Tokenized Strategy");

        strategy = IStrategyInterface(address(_strategy));

        strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        strategy.setKeeper(keeper);
        strategy.setPendingManagement(management);
        strategy.setEmergencyAdmin(emergencyAdmin);

        vm.startPrank(management);
        strategy.acceptManagement();
        strategy.setAllowed(user);
        strategy.allowWithdrawals();
        vm.stopPrank();
    }

    function test_setupMockStrategyOK() public view {
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.PENDLE_TOKEN(), address(pendleToken));
        assertTrue(strategy.PENDLE_TOKEN() != strategy.asset());
    }

    function test_operation_differentPendleToken(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Zero out performance fee
        vm.prank(management);
        strategy.setPerformanceFee(0);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        vm.prank(keeper);
        strategy.tend();

        assertGt(strategy.balanceOfPT(), 0, "!balanceOfPT");

        skip(10 days);

        vm.prank(keeper);
        strategy.report();

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");

        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_freeFunds_withPendleTokenBalance(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Zero out min amount to sell
        vm.prank(management);
        strategy.setMinAmountToSell(0);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        vm.prank(management);
        strategy.setMaxPendleTokenToSwap(_amount / 2);

        vm.prank(keeper);
        strategy.tend();

        assertGt(strategy.balanceOfPT(), 0, "!balanceOfPT");
        assertGt(strategy.balanceOfPendleToken(), 0, "!balanceOfPendleToken");

        uint256 balanceBefore = asset.balanceOf(user);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, MAX_LOSS, "!final balance");

        checkStrategyTotals(strategy, 0, 0, 0);
    }

}
