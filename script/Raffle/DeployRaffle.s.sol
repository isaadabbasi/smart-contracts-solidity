// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Script } from 'forge-std/Script.sol';

import { Raffle } from 'src/Raffle/Raffle.sol';
import { HelperConfig } from './HelperConfig.s.sol';
import { 
  AddConsumer,
  CreateSubscription,
  FundSubscription
} from './interactions/Interactions.s.sol';

contract DeployRaffle is Script {

  function run() external  returns (Raffle, HelperConfig) {
    HelperConfig hc = new HelperConfig();
    AddConsumer ac = new AddConsumer();

    (
      address link,
      address vrfCoordinator,
      bytes32 gasLane,
      uint entranceFees,
      uint withdrawInterval,
      uint32 callbackGasLimit,
      uint64 subscriptionId,
      uint256 deployerKey
    ) = hc.activeNetworkConfig();

    if (subscriptionId == 0) { 
      // if local/mock env, then there might be no subscriber. we will have to add and fund it
      CreateSubscription cs = new CreateSubscription();
      subscriptionId = cs.createSubscription(vrfCoordinator, deployerKey);

      FundSubscription fs = new FundSubscription();
      fs.fundSubscription(
        link,
        vrfCoordinator,
        subscriptionId,
        deployerKey
      );
    }

    vm.startBroadcast();
    Raffle raffle = new Raffle(
      vrfCoordinator,
      gasLane,
      entranceFees,
      withdrawInterval,
      callbackGasLimit,
      subscriptionId
    );
    vm.stopBroadcast();

    ac.addConsumer(
      address(raffle),
      vrfCoordinator,
      subscriptionId,
      deployerKey
    );

    return (raffle, hc);
  }
}