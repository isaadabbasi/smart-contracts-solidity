// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import { Script } from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { DecentralisedStableCoin } from '@DSC/DecentralisedStableCoin.sol';
import { DecentralisedStableCoinEngine } from '@DSC/DecentralisedStableCoinEngine.sol';
import { HelperConfig } from '@DSCScript/HelperConfig.s.sol';
 
contract DeployDecentralisedStableCoinEngine is Script {

  address[] priceFeeds;
  address[] tokens;

  function run() external returns (DecentralisedStableCoin, DecentralisedStableCoinEngine, HelperConfig) {
    console.log('Deploying DecentralisedStableCoin...');

    HelperConfig hc = new HelperConfig();
    (
      address wEth,
      address wEthPriceFeed,
      address wBTC,
      address wBTCPriceFeed,
      uint256 deployerKey
    )
      = hc.active();

    vm.startBroadcast(deployerKey);
    DecentralisedStableCoin dsc = new DecentralisedStableCoin();

    priceFeeds = [wEthPriceFeed, wBTCPriceFeed];
    tokens = [wEth, wBTC];

    DecentralisedStableCoinEngine engine = new DecentralisedStableCoinEngine(
      tokens,
      priceFeeds,
      address(dsc)
    );
    dsc.transferOwnership(address(engine));
    vm.stopBroadcast(); 

    return (dsc, engine, hc);
  }
}