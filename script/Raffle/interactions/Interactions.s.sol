// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { console } from 'forge-std/Test.sol';
import { VRFCoordinatorV2Mock } from '@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol';
import { DevOpsTools } from '@devops/src/DevOpstools.sol';
import { LinkToken } from 'test/mock/LinkToken.sol';
import { Script } from 'forge-std/Script.sol';
import { HelperConfig } from '../HelperConfig.s.sol';

contract CreateSubscription is Script {

  function run() public returns (uint64) {
    return createSubscriptionUsingConfig();
  }

  function createSubscriptionUsingConfig() public returns (uint64) {
    HelperConfig hc = new HelperConfig();
    (,address vrfCoordinator,,,,,, uint256 deployerKey) = hc.activeNetworkConfig();
    return createSubscription(vrfCoordinator, deployerKey);
  }

  function createSubscription(
    address vrfCoordinator,
    uint256 deployerKey
  ) public returns (uint64) {
    vm.startBroadcast(deployerKey);
    uint64 subscriptionId = VRFCoordinatorV2Mock(vrfCoordinator).createSubscription();
    vm.stopBroadcast();
    console.log("Your subscription ID is: ", subscriptionId);
    return subscriptionId;
  }

}

contract FundSubscription is Script {

  uint96 public constant FUND_AMOUNT = 3 ether;
  
  function run() public {
    return createFundingWithConfig();
  }

  function createFundingWithConfig() public {
    HelperConfig hc = new HelperConfig();
    (
      address link, 
      address vrfCoordinator,
      ,
      ,
      ,
      ,
      uint64 subscriptionId,
      uint256 deployerKey
    ) = hc.activeNetworkConfig();
    fundSubscription(
      link,
      vrfCoordinator,
      subscriptionId,
      deployerKey
    );
  }

  function fundSubscription(
    address link,
    address vrfCoordinator,
    uint64 subscriptionId,
    uint256 deployerKey
  ) public {
    vm.startBroadcast(deployerKey);
    // transfer LINK token from mock contract to vrfCoordinator
    if (block.chainid == 31337) {
      VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT);
    } else {
      LinkToken(link).transferAndCall(
          vrfCoordinator,
          FUND_AMOUNT,
          abi.encode(subscriptionId)
        );
    }
    vm.stopBroadcast();
    console.log("Subscription funded");
  }
}


contract AddConsumer is Script {
    function addConsumer(
        address recentRaffle,
        address vrfCoordinator,
        uint64 subId,
        uint256 deployerKey
    ) public {
        console.log("Adding consumer contract...");
        console.log("Current ChainID: ", block.chainid);
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(
            subId,
            recentRaffle
        );
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address recentRaffle) public {
      HelperConfig helperConfig = new HelperConfig();
      (
        ,
        address vrfCoordinator,
        ,
        ,
        ,
        ,
        uint64 subscriptionId,
        uint256 deployerKey
      ) = helperConfig.activeNetworkConfig();
      addConsumer(recentRaffle, vrfCoordinator, subscriptionId, deployerKey);
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}
