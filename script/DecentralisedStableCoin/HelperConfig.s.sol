// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/Console.sol";

import { MockV3Aggregator } from '@mock/MockV3Aggregator.sol';
import { ERC20Mock } from '@mock/ERC20Mock.sol';

contract HelperConfig is Script {
  // *** Type Declerations *** //
  struct NetworkConfig {
    address wEth;
    address wEthPriceFeed;
    address wBTC;
    address wBTCPriceFeed;
    uint256 deployerKey;
  }

  // *** Constants *** // 
  uint private constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
  uint private constant ANVIL_CHAINID = 31337;
  uint private constant SEPOLIA_CHAINID = 11155111;
  uint private constant GOERLI_CHAINID = 5;
  uint private constant ETH_CHAINID = 1;

  uint8 private constant DECIMAL = 8;
  int256 private constant BTC_USD_PRICE = 18000 * 1e8;
  int256 private constant ETH_USD_PRICE = 2000 * 1e8;

  // *** State Variables *** // 
  NetworkConfig public active;
  
  constructor() {
    if (block.chainid == GOERLI_CHAINID) {
      active = getGoerliNetworkConfig();
    } else if (block.chainid == SEPOLIA_CHAINID) {
      active = getSepoliaNetworkConfig();
    } else if (block.chainid == ETH_CHAINID) {
      active = getEthNetworkConfig();
    } else {
      active = getAnvilNetworkConfig();
    }
  }

  function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
    return active;
  }

  function getEthNetworkConfig() private view returns (NetworkConfig memory) {
    return NetworkConfig({
      wEth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
      wEthPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
      wBTC: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
      wBTCPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
      deployerKey: vm.envUint("DEPLOYER_KEY")
    });
  }

  function getSepoliaNetworkConfig() private view returns (NetworkConfig memory) {
    return NetworkConfig({
      wEth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
      wEthPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
      wBTC: address(0), // TODO - Deploy wBTC to Sepolia
      wBTCPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
      deployerKey: vm.envUint("DEPLOYER_KEY")
    });
  }

  function getGoerliNetworkConfig() private view returns (NetworkConfig memory) {
    return NetworkConfig({
      wEth: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
      wEthPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
      wBTC: 0xC04B0d3107736C32e19F1c62b2aF67BE61d63a05,
      wBTCPriceFeed: 0xA39434A63A52E749F02807ae27335515BA4b07F7,
      deployerKey: vm.envUint("DEPLOYER_KEY")
    });
  }

  function getAnvilNetworkConfig() private returns (NetworkConfig memory) {
    // TODO - will have to probably deploy all of them.
    vm.startBroadcast();
    MockV3Aggregator wEthPriceFeed = new MockV3Aggregator(DECIMAL, ETH_USD_PRICE);
    ERC20Mock wEth = new ERC20Mock("WETH", "WETH");

    MockV3Aggregator wBTCPriceFeed = new MockV3Aggregator(DECIMAL, BTC_USD_PRICE);
    ERC20Mock wBTC = new ERC20Mock("WBTC", "WBTC");
    vm.stopBroadcast();
    
    return NetworkConfig({
      wEth: address(wEth),
      wEthPriceFeed: address(wEthPriceFeed),
      wBTC: address(wBTC),
      wBTCPriceFeed: address(wBTCPriceFeed),
      deployerKey: ANVIL_DEPLOYER_KEY
    });
  }
}