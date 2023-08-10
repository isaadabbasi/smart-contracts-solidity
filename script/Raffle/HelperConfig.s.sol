// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { console } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { VRFCoordinatorV2Mock } from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import { LinkToken } from "test/mock/LinkToken.sol";


contract HelperConfig is Script {
  enum ActiveDeployedChain {
    Sepolia,
    Anvil,
    Ethereum
  }

  ActiveDeployedChain private activeDeployedChain;
  uint256 private constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

  struct NetworkConfig {
    address link;
    address vrfCoordinator;
    bytes32 gasLane;
    uint entranceFees;
    uint withdrawInterval;
    uint32 callbackGasLimit;
    uint64 subscriptionId;
    uint256 deployerKey;
  }

  NetworkConfig public activeNetworkConfig;
  uint256 private constant SEPOLIA_CHIANID = 11155111;

  constructor() {
    if (block.chainid == SEPOLIA_CHIANID) {
      activeNetworkConfig = getSepoliaNetworkConfig();
    } else {
      activeNetworkConfig = getOrCreateAnvilNetworkConfig();
    }
  }

  function getSepoliaNetworkConfig() private view returns (NetworkConfig memory) {
    NetworkConfig memory networkConfig = NetworkConfig({
      link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
      vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
      gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
      entranceFees: 0.1 ether,
      withdrawInterval: 30,
      callbackGasLimit: 500_000,
      subscriptionId: 3815,
      deployerKey: vm.envUint("PRIVATE_KEY")
    });

    return networkConfig;
  }

  function getOrCreateAnvilNetworkConfig() private returns (NetworkConfig memory) {
    if (address(activeNetworkConfig.vrfCoordinator) != address(0)) {
      return activeNetworkConfig;
    }

    uint96 baseFee = 0.25 ether; // 0.25 LINK
    uint96 gasPriceLink = 1e9; // 1 gwei LINK
    vm.startBroadcast();
    VRFCoordinatorV2Mock vrfCoordMock = new VRFCoordinatorV2Mock(
      baseFee,
      gasPriceLink
    );
    LinkToken lt = new LinkToken();
    vm.stopBroadcast();

    // fix with correct values
    NetworkConfig memory networkConfig = NetworkConfig({
      link: address(lt),
      vrfCoordinator: address(vrfCoordMock),
      gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // not important
      entranceFees: 0.1 ether,
      withdrawInterval: 30,
      callbackGasLimit: 500_000,
      subscriptionId: 0,
      deployerKey: DEFAULT_ANVIL_KEY
    });

    return networkConfig;
  }
}