// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import { DeployRaffle } from '@RaffleScript/DeployRaffle.s.sol';
import { VRFCoordinatorV2Mock } from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import { HelperConfig } from '@RaffleScript/HelperConfig.s.sol';
import { Raffle } from '@Raffle/Raffle.sol';
import { Test, console } from 'forge-std/Test.sol';
import { Vm } from 'forge-std/Vm.sol';

contract RaffleTest is Test {
  
  address ALICE = makeAddr("1");
  address BOB = makeAddr("2");
  address CHARLIE = makeAddr("3");
  
  Raffle private raffle;
  HelperConfig private hc;

  // TODO - Remove not needed variables
  address vrfCoordinator;
  bytes32 gasLane;
  uint entranceFees;
  uint withdrawInterval;
  uint32 callbackGasLimit;
  uint64 subscriptionId; 

  event Raffle__RaffleEntered(address indexed player);

  function setUp() external {
    DeployRaffle dr = new DeployRaffle();
    (raffle, hc) = dr.run();
    (
      ,
      vrfCoordinator,
      gasLane,
      entranceFees,
      withdrawInterval,
      callbackGasLimit,
      subscriptionId,
    ) = hc.activeNetworkConfig();
  }

  function test_InitialState() public view {
    assert(raffle.getCurrentState() == Raffle.RaffleState.Open);
  }

  // should not be able to join raffle when insufficient or no ethers sent
  function test_JoiningWithNoBalance() public {
    vm.prank(ALICE); // for now ALICE has no balance.
    vm.expectRevert(); // OutOfFundException
    raffle.enterRaffle{value: 0.1 ether}();
  }

  function test_JoiningWithInsufficientEthSent() public {
    vm.prank(ALICE); // use ALICE for the test context
    vm.deal(ALICE, 10 ether); // sending 10 eth to ALICE
    vm.expectRevert(Raffle.Raffle__NotEnoughEntranceFees.selector);
    raffle.enterRaffle{ value: 0.01 ether }();
  }

  function test_JoiningWithSufficientEthSent() public withFundedAlice {
    // sending entranceFees to enter raffle
    raffle.enterRaffle{ value: entranceFees }();
  }

  function test_MultipleUsersCanJoin() public {
    vm.prank(ALICE);
    vm.deal(ALICE, 10 ether);
    raffle.enterRaffle{ value: entranceFees }();

    vm.prank(BOB);
    vm.deal(BOB, 10 ether);
    raffle.enterRaffle{ value: entranceFees }();

    vm.prank(CHARLIE);
    vm.deal(CHARLIE, 10 ether);
    raffle.enterRaffle{ value: entranceFees }();
    
    uint256 totalPlayers = raffle.totalJoinedPlayers();
    assert(totalPlayers == 3);
  }
  
  // NOT a very good test but just to see if it does not blow up.
  function test_winnerGetsAllTheFunds() public {
    vm.prank(ALICE);
    vm.deal(ALICE, 10 ether);
    raffle.enterRaffle{ value: entranceFees }();

    vm.prank(BOB);
    vm.deal(BOB, 10 ether);
    raffle.enterRaffle{ value: entranceFees }();

    vm.prank(CHARLIE);
    vm.deal(CHARLIE, 10 ether);
    raffle.enterRaffle{ value: entranceFees }();

    raffle.checkUpkeep("0x0");
  }

  function test_EventEmitOnRaffleEnter() public withFundedAlice {
    vm.expectEmit(true, false, false, false, address(raffle));
    emit Raffle__RaffleEntered(ALICE);

    raffle.enterRaffle{ value: entranceFees }();
  }

  function test_CheckUpkeepReturnsFalseIfRaffleIsntOpen() public withFundedAlice {
    // Arrange
    raffle.enterRaffle{value: entranceFees}();
    vm.warp(block.timestamp + withdrawInterval + 1);
    vm.roll(block.number + 1);
    raffle.performUpkeep("");
    Raffle.RaffleState state = raffle.getCurrentState();
    // Act
    (bool upkeepNeeded, ) = raffle.checkUpkeep("");
    // Assert
    assert(state == Raffle.RaffleState.Calculating);
    assert(upkeepNeeded == false);
  }

  function test_PerformUpkeepReturnsFalseIfRaffleIsntOpen() public withFundedAlice {
    // Arrange
    raffle.enterRaffle{value: entranceFees}();
    // Act
    // Assert
    vm.expectRevert(Raffle.Raffle__UpkeepNotNeeded.selector);
    raffle.performUpkeep(""); // should throw error because enough time isn't passed 

    vm.warp(block.timestamp + withdrawInterval + 1);
    vm.roll(block.number + 1); // some blocks ahead.
    raffle.performUpkeep(""); // should not throw an error.
  }

  function test_PerformUpkeepUpdatesRaffleStateAndEmitsRequestId() 
    public 
    withFundedAlice 
    withRaffleEnteredAndTimePassedPassed {
      // Arrange
      raffle.enterRaffle{value: entranceFees}();
      vm.warp(block.timestamp + withdrawInterval + 1);
      vm.roll(block.number + 1);

      // Act
      vm.recordLogs();
      raffle.performUpkeep(""); // emits requestId
      Vm.Log[] memory entries = vm.getRecordedLogs();
      bytes32 requestId = entries[1].topics[1];

      // Assert
      Raffle.RaffleState raffleState = raffle.getCurrentState();
      // requestId = raffle.getLastRequestId();
      assert(uint256(requestId) > 0);
      assert(uint(raffleState) == 1); // 0 = open, 1 = calculating
  }

  function test_fulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
    uint256 requestId
  )
    withFundedAlice
    withRaffleEnteredAndTimePassedPassed
    withOnlyLocalEnv
    public {
      vm.expectRevert("nonexistent request");
      VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));
    }

  function test_fulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
    withFundedAlice
    withRaffleEnteredAndTimePassedPassed 
    withOnlyLocalEnv
    public {
      // Arrange
      uint256 STARTING_BALANCE = 10 ether;
      uint256 additionalEntrances = 5;
      
      // to make first player is address(1) that's why startingIndex = 1;
      uint256 startingIndex = 1;
      uint256 prize = (startingIndex + additionalEntrances) * entranceFees;

      for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
        address player = address(uint160(i));
        hoax(player, STARTING_BALANCE); // deal 10 eth to the player
        raffle.enterRaffle{value: entranceFees}();
      }

          // Act
      vm.recordLogs();
      raffle.performUpkeep(""); // emits requestId
      Vm.Log[] memory entries = vm.getRecordedLogs();
      bytes32 requestId = entries[1].topics[1];

      VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
        uint256(requestId),
        address(raffle)
      );

      assert(uint256(raffle.getCurrentState()) == 0);
      assert(raffle.getLastWinner() != address(0));

      assert(raffle.getLastWinner().balance == STARTING_BALANCE - entranceFees + prize);
  }

  modifier withOnlyLocalEnv() {
    if (block.chainid != 31337) {
      return;
    }
    _;
  }

  modifier withFundedAlice() {
    vm.prank(ALICE);
    vm.deal(ALICE, 10 ether);
    _;
  }

  // Modifiers are sequentially executed
  modifier withRaffleEnteredAndTimePassedPassed() {
    raffle.enterRaffle{value: entranceFees}();
    vm.warp(block.timestamp + withdrawInterval + 1);
    vm.roll(block.number + 1);
    _;
  }

}
