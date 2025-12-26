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

    function set_protocol_fee_bps(
        uint16
    ) external;

    function set_protocol_fee_recipient(
        address
    ) external;

}

contract Setup is Test, IEvents {

    // Contract addresses.
    address public constant ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address public constant ORACLE = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2; // pyYtLpOracle mainnet

    // USDE-MAINNET-FAB2026 ($2.63M LP TVL @ `24_011_022` block)
    address public constant LP = 0xAADBC004DAcF10e1fdbd87ca1a40ecAF77CC5B02;
    address public constant SY = 0x925a15bD6A1582fa7c0EbbFc3Dbd29c34f58340e;
    address public constant YT = 0x5a62AE8118536CF2De315E2c42f9Af035d8129f2;
    address public constant PT = 0x1F84a51296691320478c98b8d77f2Bbd17D34350;
    uint256 public constant EXPIRY = 1770249600;

    // // USD3-MAINNET-JAN2026
    // address public constant LP = 0xeaaC9B0B4F25cc63255198a3920FcF7752509586;
    // address public constant SY = 0xA22d3605f843F34FC70cd91Fb0AF600a7359270a;
    // address public constant YT = 0x8751E87931f084e5E83725110329cf7b27170f89;
    // address public constant PT = 0xe39d1D3CAcEA800fD5aFB87dD98A42a8a364da08;
    // uint256 public constant EXPIRY = 1769644800;

    // // USDE-MAINNET-SEP2025
    // address public constant LP = 0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4;
    // address public constant SY = 0xf3DbdE762E5B67FaD09d88da3dfD38A83f753FFe;
    // address public constant YT = 0x48bbbEdc4d2491cc08915D7a5c7cc8A8EdF165da;
    // address public constant PT = 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a;
    // uint256 public constant EXPIRY = 1758758400;

    // // USDAF-MAINNET-NOV2025
    // address public constant LP = 0x8Bf03ACbF1C2aC2e487c80678De7873C954525D2;
    // address public constant SY = 0x6FC5b9eEBf6f19556DB8C8Fdcc8D4a52E6Dc106D;
    // address public constant YT = 0xfAC0A88f74570478367Ba1a52b4a30cfeC6eC431;
    // address public constant PT = 0x9B02ca5685E9C332b158c01459562a161c8e8ADf;
    // uint256 public constant EXPIRY = 1762992000;

    // // SUSDAF-MAINNET-NOV2025
    // address public constant LP = 0x233f5adf236CAB22C5DbDD3333a7EfD8267d7AEE;
    // address public constant SY = 0xb81a3526793A6f7D0201e00F40f4e58Cc9CD9025;
    // address public constant YT = 0x4E99312E0beba4d73D8E8E9368FD24F4670624D9;
    // address public constant PT = 0xA3CA92a69c6809607837bc3BD6B13e4c1E1e8aE9;
    // uint256 public constant EXPIRY = 1762992000;

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
    address public gov = address(6);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.001 of 1e18 stable coins up to 10 million of a 1e18 coin
    // uint256 public maxFuzzAmount = 10_000_000 * 1e18;
    uint256 public maxFuzzAmount = 1000 * 1e18;
    uint256 public minFuzzAmount = 0.001 * 1e18;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // Default accepted loss
    uint256 public constant MAX_LOSS = 1e16; // 1%

    function setUp() public virtual {
        uint256 _blockNumber = 24_011_022; // Caching for faster tests
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _blockNumber));

        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["USDe"]);

        // Set decimals
        decimals = asset.decimals();

        strategyFactory = new StrategyFactory(management, performanceFeeRecipient, keeper, emergencyAdmin, gov);

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();

        // Initialize the oracle observations cardinality for the market used in tests
        IPendleMarket(LP).increaseObservationsCardinalityNext(165);

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
            address(strategyFactory.newStrategy(address(asset), address(asset), LP, ORACLE, "Tokenized Strategy"))
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
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(
        ERC20 _asset,
        address _to,
        uint256 _amount
    ) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(
        uint16 _protocolFee,
        uint16 _performanceFee
    ) public {
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
        tokenAddrs["USDaf"] = 0x9Cf12ccd6020b6888e4D4C4e4c7AcA33c1eB91f8;
        tokenAddrs["BOLD"] = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
        tokenAddrs["yBOLD"] = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
        tokenAddrs["ysyBOLD"] = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
        tokenAddrs["USD3"] = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    }

}
