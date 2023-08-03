// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import { Script } from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';
import { DecentralisedStableCoin } from '@DSC/DecentralisedStableCoin.sol';
import { DecentralisedStableCoinEngine } from '@DSC/DecentralisedStableCoinEngine.sol';
 
contract DeployDecentralisedStableCoin is Script {
  function run() external returns (DecentralisedStableCoin, DecentralisedStableCoinEngine) {
    console.log('Deploying DecentralisedStableCoin...');

    vm.startBroadcast();
    DecentralisedStableCoin dsc = new DecentralisedStableCoin();
    DecentralisedStableCoinEngine engine = new DecentralisedStableCoinEngine(
      new address[](0),
      new address[](0),
      address(dsc)
    );
    vm.stopBroadcast();

    return (dsc, engine);
  }
}