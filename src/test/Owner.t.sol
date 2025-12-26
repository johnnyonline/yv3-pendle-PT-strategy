// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";

interface IAuctionFactory {

    function createNewAuction(
        address _want,
        address _receiver
    ) external returns (address);

}

interface IAuction {

    function enable(
        address _from
    ) external;
    function governance() external view returns (address);

}

contract OwnerTest is Setup {

    IAuctionFactory public auctionFactory = IAuctionFactory(0xd8e03D6D24d43c46c0f7f61327E391316E4f3c15);

    function setUp() public override {
        super.setUp();
    }

    // ===============================================================
    // allowWithdrawals
    // ===============================================================

    function test_allowWithdrawals() public {
        assertFalse(strategy.openWithdrawals());

        vm.prank(management);
        strategy.allowWithdrawals();

        assertTrue(strategy.openWithdrawals());
    }

    function test_allowWithdrawals_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.allowWithdrawals();
    }

    // ===============================================================
    // setAllowed
    // ===============================================================

    function test_setAllowed(
        address _address
    ) public {
        vm.assume(_address != user);

        assertFalse(strategy.allowed(_address));

        vm.prank(management);
        strategy.setAllowed(_address);

        assertTrue(strategy.allowed(_address));
    }

    function test_setAllowed_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.setAllowed(_wrongCaller);
    }

    // ===============================================================
    // setMaxPendleTokenToSwap
    // ===============================================================

    function test_setMaxPendleTokenToSwap(
        uint256 _maxPendleTokenToSwap
    ) public {
        vm.prank(management);
        strategy.setMaxPendleTokenToSwap(_maxPendleTokenToSwap);

        assertEq(strategy.maxPendleTokenToSwap(), _maxPendleTokenToSwap);
    }

    function test_setMaxPendleTokenToSwap_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.setMaxPendleTokenToSwap(0);
    }

    // ===============================================================
    // setMinSwapInterval
    // ===============================================================

    function test_setMinSwapInterval(
        uint256 _minSwapInterval
    ) public {
        vm.prank(management);
        strategy.setMinSwapInterval(_minSwapInterval);

        assertEq(strategy.minSwapInterval(), _minSwapInterval);
    }

    function test_setMinSwapInterval_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.setMinSwapInterval(0);
    }

    // ===============================================================
    // setMinAmountToSell
    // ===============================================================

    function test_setMinAmountToSell(
        uint256 _minAmountToSell
    ) public {
        vm.prank(management);
        strategy.setMinAmountToSell(_minAmountToSell);

        assertEq(strategy.minAmountToSell(), _minAmountToSell);
    }

    function test_setMinAmountToSell_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.setMinAmountToSell(0);
    }

    // ===============================================================
    // setSwapSlippageBPS
    // ===============================================================

    function test_setSwapSlippageBPS(
        uint256 _swapSlippageBPS
    ) public {
        vm.assume(_swapSlippageBPS <= MAX_BPS);

        vm.prank(management);
        strategy.setSwapSlippageBPS(_swapSlippageBPS);

        assertEq(strategy.swapSlippageBPS(), _swapSlippageBPS);
    }

    function test_setSwapSlippageBPS_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.setSwapSlippageBPS(0);
    }

    function test_setSwapSlippageBPS_tooHigh(
        uint256 _swapSlippageBPS
    ) public {
        vm.assume(_swapSlippageBPS > MAX_BPS);

        vm.prank(management);
        vm.expectRevert("!swapSlippageBPS");
        strategy.setSwapSlippageBPS(_swapSlippageBPS);
    }

    // ===============================================================
    // setAuction
    // ===============================================================

    function test_setAuction() public returns (address _auction) {
        assertEq(address(0), strategy.auction());

        _auction = auctionFactory.createNewAuction(strategy.asset(), address(strategy));

        vm.prank(management);
        strategy.setAuction(_auction);

        assertEq(_auction, strategy.auction());
    }

    function test_setAuction_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!management");
        strategy.setAuction(address(0));
    }

    function test_setAuction_wrongWant() public {
        address _auction = auctionFactory.createNewAuction(tokenAddrs["YFI"], address(strategy));

        vm.prank(management);
        vm.expectRevert("!want");
        strategy.setAuction(_auction);
    }

    function test_setAuction_wrongReceiver(
        address _wrongReceiver
    ) public {
        vm.assume(_wrongReceiver != address(0) && _wrongReceiver != address(strategy));

        address _auction = auctionFactory.createNewAuction(strategy.asset(), _wrongReceiver);

        vm.prank(management);
        vm.expectRevert("!receiver");
        strategy.setAuction(_auction);
    }

    // ===============================================================
    // availableDepositLimit
    // ===============================================================

    function test_availableDepositLimit_setAllowed(
        address _owner
    ) public {
        vm.assume(_owner != user);

        assertEq(strategy.availableDepositLimit(_owner), 0);

        vm.prank(management);
        strategy.setAllowed(_owner);

        assertEq(strategy.availableDepositLimit(_owner), type(uint256).max);
    }

    function test_availableDepositLimit_afterExpiry(
        address _owner
    ) public {
        vm.prank(management);
        strategy.setAllowed(_owner);

        assertEq(strategy.availableDepositLimit(_owner), type(uint256).max);

        // Expire market
        _simulateMarketExpiration();

        assertEq(strategy.availableDepositLimit(_owner), 0);
    }

    // ===============================================================
    // availableWithdrawLimit
    // ===============================================================

    function test_availableWithdrawLimit_openWithdrawals(
        address _owner
    ) public {
        assertEq(strategy.availableWithdrawLimit(_owner), 0);

        vm.prank(management);
        strategy.allowWithdrawals();

        assertEq(strategy.availableWithdrawLimit(_owner), type(uint256).max);
    }

    function test_availableWithdrawLimit_afterExpiry(
        address _owner
    ) public {
        assertEq(strategy.availableWithdrawLimit(_owner), 0);

        // Expire market
        _simulateMarketExpiration();

        assertEq(strategy.availableWithdrawLimit(_owner), type(uint256).max);
    }

    // ===============================================================
    // kickAuction
    // ===============================================================

    function test_kickAuction(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Set auction
        address auction = test_setAuction();

        // Enable token
        address token = tokenAddrs["YFI"];
        vm.prank(IAuction(auction).governance());
        IAuction(auction).enable(token);

        // Airdrop tokens to the strategy
        airdrop(ERC20(token), address(strategy), _amount);

        // Kick the auction
        vm.prank(keeper);
        uint256 available = strategy.kickAuction(token);

        assertEq(available, _amount);
        assertEq(ERC20(token).balanceOf(address(strategy)), 0);
    }

    function test_kickAuction_zeroAmount() public {
        // Set auction
        address auction = test_setAuction();

        // Enable token
        address token = tokenAddrs["YFI"];
        vm.prank(IAuction(auction).governance());
        IAuction(auction).enable(token);

        // Kick the auction
        vm.prank(keeper);
        vm.expectRevert("nothing to kick");
        strategy.kickAuction(token);
    }

    function test_kickAuction_noAuction() public {
        vm.prank(keeper);
        vm.expectRevert();
        strategy.kickAuction(address(0));
    }

    function test_kickAuction_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != keeper && _wrongCaller != management);

        vm.prank(_wrongCaller);
        vm.expectRevert("!keeper");
        strategy.kickAuction(address(0));
    }

    function test_kickAuction_wrongToken() public {
        vm.startPrank(keeper);

        vm.expectRevert("!token");
        strategy.kickAuction(LP);

        vm.expectRevert("!token");
        strategy.kickAuction(SY);

        vm.expectRevert("!token");
        strategy.kickAuction(PT);

        vm.expectRevert("!token");
        strategy.kickAuction(address(asset));

        vm.stopPrank();
    }

}
