// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

import {IPendleRouter, PendleLimitOrderData, PendleSwapData, PendleTokenInput} from "../interfaces/IPendle.sol";
import {ApproxParams} from "@pendle-core-v2/interfaces/IPAllActionTypeV3.sol";

contract SwapTest is Setup {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(management);
        strategy.allowWithdrawals();
    }

    // Should we (1) TWAP into the PT or (2) mint PT and TWAP YT into more PT?
    function test_swap_vs_mint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        address _swapper = address(420);
        address _minter = address(69);

        // Strategy 1: Swap asset directly for PT via market
        _buyPT(_swapper, _amount); // asset --> PT

        // Strategy 2: Mint PY, sell YT for SY, mint more PY from SY
        _mintPY(_minter, _amount); // asset --> PY
        _sellYT(_minter, ERC20(YT).balanceOf(_minter)); // YT --> SY
        _mintPYFromSY(_minter, ERC20(SY).balanceOf(_minter)); // SY --> PY

        uint256 _swapperPT = ERC20(PT).balanceOf(_swapper);
        uint256 _minterPT = ERC20(PT).balanceOf(_minter);
        console2.log("Swapper PT (direct swap):", _swapperPT / 1e18);
        console2.log("Minter PT (mint + sell YT):", _minterPT / 1e18);

        if (_swapperPT > _minterPT) {
            console2.log("Winner: Direct swap");
            console2.log("Difference:", (_swapperPT - _minterPT) / 1e18);
        } else {
            console2.log("Winner: Mint + sell YT");
            console2.log("Difference:", (_minterPT - _swapperPT) / 1e18);
        }
    }

    // ===============================================================
    // Helpers
    // ===============================================================

    function _mintPY(
        address _caller,
        uint256 _amount
    ) internal returns (uint256 _py) {
        airdrop(asset, _caller, _amount);

        vm.startPrank(_caller);
        asset.approve(ROUTER, _amount);

        // Empty swap data as we're not swapping anything
        PendleSwapData memory _swapData;

        // Asset --> PY
        (_py,) = IPendleRouter(ROUTER)
            .mintPyFromToken(
                _caller, // receiver
                YT, // YT
                0, // minPyOut
                PendleTokenInput({
                    tokenIn: address(asset),
                    netTokenIn: _amount,
                    tokenMintSy: address(asset),
                    pendleSwap: address(0),
                    swapData: _swapData
                })
            );

        vm.stopPrank();
    }

    function _sellYT(
        address _caller,
        uint256 _amount
    ) internal returns (uint256 _sy) {
        vm.startPrank(_caller);
        ERC20(YT).approve(ROUTER, _amount);

        // Empty limit order data
        PendleLimitOrderData memory _limit;

        // YT --> SY
        (_sy,) = IPendleRouter(ROUTER)
            .swapExactYtForSy(
                _caller, // receiver
                LP, // market
                _amount, // exactYtIn
                0, // minSyOut
                _limit
            );

        vm.stopPrank();
    }

    function _buyPT(
        address _caller,
        uint256 _amount
    ) internal returns (uint256 _pt) {
        airdrop(asset, _caller, _amount);

        vm.startPrank(_caller);
        asset.approve(ROUTER, _amount);

        PendleSwapData memory _swapData;
        PendleLimitOrderData memory _limit;
        ApproxParams memory _approx = ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 1e14
        });

        // Asset --> PT
        (_pt,,) = IPendleRouter(ROUTER).swapExactTokenForPt(
            _caller, // receiver
            LP, // market
            0, // minPtOut
            _approx, // guessPtOut
            PendleTokenInput({
                tokenIn: address(asset),
                netTokenIn: _amount,
                tokenMintSy: address(asset),
                pendleSwap: address(0),
                swapData: _swapData
            }),
            _limit
        );

        vm.stopPrank();
    }

    function _mintPYFromSY(
        address _caller,
        uint256 _amount
    ) internal returns (uint256 _py) {
        vm.startPrank(_caller);
        ERC20(SY).approve(ROUTER, _amount);

        // SY --> PY
        _py = IPendleRouter(ROUTER)
            .mintPyFromSy(
                _caller, // receiver
                YT, // YT
                _amount, // netSyIn
                0 // minPyOut
            );

        vm.stopPrank();
    }

}
