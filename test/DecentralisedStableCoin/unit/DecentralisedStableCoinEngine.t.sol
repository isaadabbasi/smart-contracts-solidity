// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// *** System level packages ***
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// *** Installed libraries/packages ***
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@mock/MockV3Aggregator.sol";

///*** Custom contracts *** */
import {DecentralisedStableCoin} from "@DSC/DecentralisedStableCoin.sol";
import {DecentralisedStableCoinEngine} from "@DSC/DecentralisedStableCoinEngine.sol";
import {DeployDecentralisedStableCoinEngine} from "@DSCScript/DeployDecentralisedStableCoinEngine.s.sol";
import {HelperConfig} from "@DSCScript/HelperConfig.s.sol";

contract DecentralisedStableCoinEngineTest is Test {
    // *** Constants and Immutables *** //
    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ANVIL_CHAINID = 31337;
    uint256 private constant BTC_USD_PRICE = 18000;
    uint256 private constant ETH_USD_PRICE = 2000;
    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant STARTING_ERC20_BALANCE = 100 ether;

    DecentralisedStableCoin private dsc;
    DecentralisedStableCoinEngine private engine;
    HelperConfig private config;
    // HelperConfig private config;

    address ALICE = makeAddr("1");

    address private wEth;
    address private wBTC;
    address private wEthPriceFeed;
    address private wBTCPriceFeed;

    address[] public tokenAddresses;
    address[] public feedAddresses;

    function setUp() external {
        DeployDecentralisedStableCoinEngine deployer = new DeployDecentralisedStableCoinEngine();
        (dsc, engine, config) = deployer.run();
        (wEth, wEthPriceFeed, wBTC, wBTCPriceFeed,) = config.active();

        if (block.chainid == 31337) {
            vm.deal(ALICE, STARTING_ERC20_BALANCE);
        }

        ERC20Mock(wEth).mint(ALICE, STARTING_ERC20_BALANCE);
        ERC20Mock(wBTC).mint(ALICE, STARTING_ERC20_BALANCE);
    }

    modifier onlyAnvil() {
        if (block.chainid == ANVIL_CHAINID) {
            _;
        }
    }

    modifier collateralDeposited() {
        vm.startPrank(ALICE);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        _;
    }

    modifier collateralDepositedAndSomeDSCMinted(uint8 _partial) {
        vm.startPrank(ALICE);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        uint256 tokenValue = engine.getTokenValue(wEth, AMOUNT_COLLATERAL);
        // if partialValue = 2, then its half of tokenValue, if 4 its quarter of tokenValue
        uint256 partialOfTokenValue = tokenValue / _partial;

        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        engine.depositCollateralAndMintDSC(wEth, AMOUNT_COLLATERAL, partialOfTokenValue);
        vm.stopPrank();
        _;
    }

    function test_revertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(wEth);
        feedAddresses.push(wEthPriceFeed);
        feedAddresses.push(wBTCPriceFeed);

        vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__TokensAndPriceFeedLengthMismatch.selector);
        new DecentralisedStableCoinEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function test_ethUSDPrice() public {
        uint256 BTCPrice = engine.getTokenValue(wBTC, 1);
        assertEq(BTCPrice, BTC_USD_PRICE);

        uint256 EthPrice = engine.getTokenValue(wEth, 1);
        assertEq(EthPrice, ETH_USD_PRICE);
    }

    function test_getTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = engine.getTokenAmountFromUSD(wEth, 100 * PRECISION);
        assertEq(amountWeth, expectedWeth);
    }

    function test_revertIfCollateralIsZero() public {
        vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(wEth, 0);
    }

    function test_revertsWithUnapprovedCollateral() public {
        address random = makeAddr("RANDOM");
        vm.startPrank(ALICE);
        vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__CollateralAddressIsNotAllowed.selector);
        engine.depositCollateral(random, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // *** Check Deposit

    function test_canDepositCollateral() public {
        vm.startPrank(ALICE);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
    }

    function test_depositValueAreCorrect() public collateralDeposited {
        vm.prank(ALICE);

        (uint256 dscMinted, uint256 _collateralDeposited) = engine.getAccountInformation(ALICE);

        uint256 collateralValueInUSD = engine.getTokenValue(wEth, AMOUNT_COLLATERAL);
        uint256 collateralValueInWeth = engine.getTokenAmountFromUSD(wEth, _collateralDeposited);
        assertEq(dscMinted, 0); // Cause we haven't minted yet, just deposited collateral
        assertEq(_collateralDeposited, collateralValueInUSD);
        assertEq(AMOUNT_COLLATERAL, collateralValueInWeth);
    }

    // *** Check mint

    function test_canMintWithoutCollateral() public {
        vm.prank(ALICE);
        vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__MintedDSCExceedingThreshold.selector);
        engine.mintDsc(1000);
    }

    function test_canMintSameAmountOfDSCAsCollateral() public {
        vm.startPrank(ALICE);
        uint256 tokenValue = engine.getTokenValue(wEth, AMOUNT_COLLATERAL);

        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__MintedDSCExceedingThreshold.selector);
        engine.depositCollateralAndMintDSC(wEth, AMOUNT_COLLATERAL, tokenValue);
        vm.stopPrank();
    }

    function test_mintsTheTokenWithValidCollateral() public {
        vm.startPrank(ALICE);
        uint256 tokenValue = engine.getTokenValue(wEth, AMOUNT_COLLATERAL);
        uint256 halfOfTokenValue = tokenValue / 2;
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        // vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__MinimumHealthFactorReached.selector);
        engine.depositCollateralAndMintDSC(wEth, AMOUNT_COLLATERAL, halfOfTokenValue);
        uint256 aliceDSCBalance = ERC20Mock(address(dsc)).balanceOf(ALICE);
        assertEq(aliceDSCBalance, halfOfTokenValue);
    }

    // *** Check liquidation

    // *** Check redeem and Burn
    function test_redeemBeforeBurn() public collateralDepositedAndSomeDSCMinted(2) {
        vm.prank(ALICE);
        vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__MintedDSCExceedingThreshold.selector);
        engine.redeemCollateral(wEth, AMOUNT_COLLATERAL);
    }

    function test_burnDSCs() public collateralDepositedAndSomeDSCMinted(2) {
        vm.startPrank(ALICE);
        (uint256 dscMinted,) = engine.getAccountInformation(ALICE);
        
        ERC20Mock(address(dsc)).approve(address(engine), dscMinted);
        engine.burnDSC(dscMinted);
        vm.stopPrank();
    }

    function test_redeemDepositedCollateral() public collateralDepositedAndSomeDSCMinted(2) {
        vm.startPrank(ALICE);

        (uint256 dscMinted,) = engine.getAccountInformation(ALICE);
        
        ERC20Mock(address(dsc)).approve(address(engine), dscMinted);
        engine.burnDSC(dscMinted);

        engine.redeemCollateral(wEth, AMOUNT_COLLATERAL);
    } 

    // *** Check health factors

    function test_healthFactorOnZero() public {
        assertEq(engine.getHealthFactor(ALICE), type(uint256).max);
    }

    function test_healthFactorWithOnlyCollateralDeposited() public collateralDeposited {
        assertEq(engine.getHealthFactor(ALICE), type(uint256).max);
    }

    function test_healthFactorThresholdMintedDSCs() public collateralDepositedAndSomeDSCMinted(2) {
        assertEq(engine.getHealthFactor(ALICE), 1 * PRECISION);
    }

}
