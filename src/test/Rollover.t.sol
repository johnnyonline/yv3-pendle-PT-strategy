// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {
    IPMarket as IPendleMarket,
    IPPrincipalToken as IPendlePrincipalToken
} from "@pendle-core-v2/interfaces/IPMarket.sol";

import {IPPYLpOracle as IPendleOracle} from "@pendle-core-v2/interfaces/IPPYLpOracle.sol";

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface, StrategyFactory} from "./utils/Setup.sol";

contract RolloverTest is Setup {

    // yBOLD Market addresses
    address public constant OLD_MARKET = 0x1BD78377DFbCA2043e38b692D2E0b32396b4772d;
    address public constant NEW_MARKET = 0x83B2C0b470Ff5f2a60D2BF2AE109766E8bb3E862;

    address public oldPT;

    function setUp() public override {
        // Block where new market is already deployed and old market is expired
        uint256 _blockNumber = 24049143; // Caching for faster tests
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _blockNumber));

        _setTokenAddrs();

        asset = ERC20(tokenAddrs["yBOLD"]);

        // Get old PT address
        (, IPendlePrincipalToken _oldPT,) = IPendleMarket(OLD_MARKET).readTokens();
        oldPT = address(_oldPT);

        // Mock isExpired to return false so we can deploy
        vm.mockCall(OLD_MARKET, abi.encodeWithSelector(IPendleMarket.isExpired.selector), abi.encode(false));

        // Mock oracle state to be ready
        vm.mockCall(ORACLE, abi.encodeWithSelector(IPendleOracle.getOracleState.selector), abi.encode(false, 165, true));

        strategyFactory = new StrategyFactory(management, performanceFeeRecipient, keeper, emergencyAdmin);

        strategy = IStrategyInterface(_setUpStrategy());

        factory = strategy.FACTORY();

        // Initialize the oracle observations cardinality for the market used in tests
        IPendleMarket(NEW_MARKET).increaseObservationsCardinalityNext(165);

        vm.prank(management);
        strategy.allowWithdrawals();
    }

    function _setUpStrategy() internal returns (address) {
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                strategyFactory.newStrategy(address(asset), address(asset), OLD_MARKET, ORACLE, "Tokenized Strategy")
            )
        );

        // Invalid pendleToken (not valid for SY)
        vm.expectRevert("!pendleToken");
        strategyFactory.newStrategy(address(asset), tokenAddrs["BOLD"], OLD_MARKET, ORACLE, "Tokenized Strategy");

        vm.startPrank(management);
        _strategy.acceptManagement();
        _strategy.setAllowed(user);
        vm.stopPrank();

        return address(_strategy);
    }

    function test_rollover(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Airdrop old PTs to strategy
        airdrop(ERC20(oldPT), address(strategy), _amount);

        uint256 ptBefore = strategy.balanceOfPT();
        assertGt(ptBefore, 0, "!ptBefore");

        // Clear mock to allow real expiry check
        vm.clearMockedCalls();

        // Rollover to new market
        vm.prank(management);
        strategy.rollover(NEW_MARKET);

        // PT should be converted to pendleToken
        assertEq(strategy.balanceOfPT(), 0, "!ptAfter");
        assertGt(strategy.balanceOfPendleToken(), 0, "!pendleToken");

        // New market should be set
        address newPT = strategy.principalToken();
        assertEq(strategy.markets(newPT), NEW_MARKET, "!newMarket");

        // Tend to buy new PT
        vm.prank(keeper);
        strategy.tend();

        // Should have new PT now
        assertGt(strategy.balanceOfPT(), 0, "!newPT");
    }

    function test_rollover_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.rollover(NEW_MARKET);
    }

    function test_rollover_emergencyWithdraw(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Airdrop old PTs to strategy
        airdrop(ERC20(oldPT), address(strategy), _amount);

        // Clear mock to allow real expiry check
        vm.clearMockedCalls();

        // Rollover to new market (assets now in pendle token, not PT)
        vm.prank(management);
        strategy.rollover(NEW_MARKET);

        assertEq(strategy.balanceOfPT(), 0, "!ptAfter");
        assertGt(strategy.balanceOfPendleToken(), 0, "!pendleToken");

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Emergency withdraw while assets are in pendle token
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // All tokens should be in asset
        assertEq(strategy.balanceOfPT(), 0, "!ptFinal");
        // assertEq(strategy.balanceOfPendleToken(), 0, "!pendleTokenFinal"); // IGNORED bc pendleToken is the same as asset
        assertGt(asset.balanceOf(address(strategy)), 0, "!assetFinal");
    }

    function test_rollover_wrongSY() public {
        // Try to rollover to a market with different SY (cUSD market)
        address wrongMarket = 0x307c15f808914Df5a5DbE17E5608f84953fFa023;

        vm.prank(management);
        vm.expectRevert("!newSY");
        strategy.rollover(wrongMarket);
    }

}
