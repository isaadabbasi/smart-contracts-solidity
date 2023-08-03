// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { console } from "forge-std/Console.sol";
import { Test } from "forge-std/Test.sol";

import { DecentralisedStableCoin } from "@DSC/DecentralisedStableCoin.sol";
import { DecentralisedStableCoinEngine } from "@DSC/DecentralisedStableCoinEngine.sol";
import { DeployDecentralisedStableCoin } from "@DSCScript/DeployDecentralisedStableCoin.s.sol";
import { HelperConfig } from "@DSCScript/HelperConfig.s.sol";

contract DecentralisedStableCoinEngineTest is Test {
  
  // *** Constants and Immutables *** //
  uint private constant DECIMAL_PRECISION = 10e18;
  uint private constant ANVIL_CHAINID = 31337;
  uint private constant BTC_USD_PRICE = 18000;
  uint private constant ETH_USD_PRICE = 2000;
  uint private constant AMOUNT_COLLATERAL = 10 ether;
  uint private constant STARTING_ERC20_BALANCE = 10 ether;


  DecentralisedStableCoin private dsc;
  DecentralisedStableCoinEngine private engine;
  HelperConfig private config;
  // HelperConfig private config;

  address ALICE = makeAddr("1");

  address private wEth;
  address private wBTC;
  address private wEthPriceFeed;
  address private wBTCPriceFeed;
  
  function setUp() external {
    DeployDecentralisedStableCoin deployer = new DeployDecentralisedStableCoin();
    (dsc, engine, config) = deployer.run();
    (
      wEth,
      wEthPriceFeed,
      wBTC,
      wBTCPriceFeed,
    ) = config.active();
  }

  modifier onlyAnvil() {
    if (block.chainid == ANVIL_CHAINID) {
      _;
    }
  }


  function test_EthUSDPrice() public {
    uint256 BTCPrice = engine.getTokenValue(wBTC, 1);
    assertEq(BTCPrice,  BTC_USD_PRICE);

    uint256 EthPrice = engine.getTokenValue(wEth, 1);
    assertEq(EthPrice, ETH_USD_PRICE);  
  }

  function test_revertIfCollateralIsZero() public {
    vm.expectRevert(DecentralisedStableCoinEngine.DSCEngine__NeedsMoreThanZero.selector);
    engine.depositCollateral(wEth, 0);
  }
}
