// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {PendlePTStrategy as Strategy, IPendleMarket, ERC20} from "../../Strategy.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is Test, IEvents {

    // Contract addresses.
    address public constant ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    // USDE-MAINNET-SEP2025
    address public constant LP = 0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4;
    address public constant SY = 0xf3DbdE762E5B67FaD09d88da3dfD38A83f753FFe;
    address public constant YT = 0x48bbbEdc4d2491cc08915D7a5c7cc8A8EdF165da;
    address public constant PT = 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a;
    uint256 public constant EXPIRY = 1758758400;

    // // SUSDE-MAINNET-NOV2025 // @todo
    // address public constant LP = 0xA36b60A14A1A5247912584768C6e53E1a269a9F7;
    // address public constant SY = 0xC01cde799245a25e6EabC550b36A47F6F83cc0f1;
    // address public constant YT = 0x029d6247ADb0A57138c62E3019C92d3dfC9c1840;
    // address public constant PT = 0x9F56094C450763769BA0EA9Fe2876070c0fD5F77;
    // uint256 public constant EXPIRY = 1758758400;

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    StrategyFactory public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.001 of 1e18 stable coins up to 10 million of a 1e18 coin
    uint256 public maxFuzzAmount = 10_000_000 * 1e18;
    uint256 public minFuzzAmount = 0.001 * 1e18;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // Default accepted loss
    uint256 public constant MAX_LOSS = 8e15; // 0.8%

    function setUp() public virtual {
        uint256 _blockNumber = 23_320_905; // Caching for faster tests
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _blockNumber));

        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["USDe"]);

        // Set decimals
        decimals = asset.decimals();

        strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                strategyFactory.newStrategy(
                    address(asset),
                    LP,
                    "Tokenized Strategy"
                )
            )
        );

        vm.startPrank(management);
        _strategy.acceptManagement();
        _strategy.setAllowed(user);
        vm.stopPrank();

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _simulateMarketExpiration() internal {
        require(!IPendleMarket(LP).isExpired(), "Market already expired");
        skip(EXPIRY - block.timestamp);
        require(IPendleMarket(LP).isExpired(), "Market did not expire");
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["USDe"] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokenAddrs["sUSDe"] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    }
}
