// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILitePSM} from "../interfaces/ILitePSM.sol";
import {IDaiUsds} from "../interfaces/IDaiUsds.sol";

contract UsdsExchange {

    using SafeERC20 for ERC20;

    /// @notice USDC (6 decimals) -> DAI/USDS (18 decimals) scaler
    uint256 public constant SCALER = 1e12;

    ERC20 public constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant USDS = ERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    /// @notice Sky LITE-PSM (USDC <-> DAI)
    ILitePSM public constant PSM = ILitePSM(0xf6e72Db5454dd049d0788e411b06CfAF16853042);

    /// @notice Sky DAI <-> USDS converter
    IDaiUsds public constant DAI_USDS_EXCHANGER = IDaiUsds(0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A);

    constructor() {
        // Approve the venues to pull each leg of both directions
        USDC.forceApprove(address(PSM), type(uint256).max); // sellGem pulls USDC
        DAI.forceApprove(address(DAI_USDS_EXCHANGER), type(uint256).max); // daiToUsds pulls DAI
        USDS.forceApprove(address(DAI_USDS_EXCHANGER), type(uint256).max); // usdsToDai pulls USDS
        DAI.forceApprove(address(PSM), type(uint256).max); // buyGem pulls DAI
    }

    function name() external pure returns (string memory) {
        return "UsdsExchange";
    }

    /// @notice Convert `_amountIn` of `_from` into `_to` (USDC <-> USDS only)
    /// @param _from The token to swap from (USDC or USDS)
    /// @param _to The token to swap to (USDS or USDC)
    /// @param _amountIn The amount of `_from` to swap
    /// @param _amountOutMin The minimum acceptable amount of `_to` out
    /// @return _amountOut The amount of `_to` sent back to the caller
    function exchange(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) external returns (uint256 _amountOut) {
        if (_amountIn == 0) return 0;

        // Pull `_from` from the caller (the MetaExchange approved us)
        ERC20(_from).safeTransferFrom(msg.sender, address(this), _amountIn);

        if (_from == address(USDC) && _to == address(USDS)) {
            // USDC --1:1--> DAI through the LitePSM, then DAI --1:1--> USDS
            uint256 _daiOut = PSM.sellGem(address(this), _amountIn);
            DAI_USDS_EXCHANGER.daiToUsds(address(this), _daiOut);
            _amountOut = _daiOut;
        } else if (_from == address(USDS) && _to == address(USDC)) {
            // USDS --1:1--> DAI, then DAI --1:1--> USDC through the LitePSM
            DAI_USDS_EXCHANGER.usdsToDai(address(this), _amountIn);
            uint256 _gemAmount = _amountIn / SCALER;
            require(_gemAmount != 0, "!amountOut");

            uint256 _balanceBefore = USDC.balanceOf(address(this));
            PSM.buyGem(address(this), _gemAmount);
            _amountOut = USDC.balanceOf(address(this)) - _balanceBefore;
        } else {
            revert("!pair");
        }

        require(_amountOut >= _amountOutMin, "!amountOut");

        // Send `_to` back to the caller
        ERC20(_to).safeTransfer(msg.sender, _amountOut);
    }

}
