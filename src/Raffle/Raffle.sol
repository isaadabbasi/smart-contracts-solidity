// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// * Import Statements ** //
import { console } from 'forge-std/Test.sol';
import { VRFCoordinatorV2Interface } from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import { VRFConsumerBaseV2 } from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Raffle - Lottery Contract
 * @author Saad Abbasi | @isaadabbasi
 * @notice Raffle is a lottery contract that allows users to enter a lottery and win a prize based on the number of entries.
 * The winner is decided totally by random number obtained from oracles.
 */

contract Raffle is VRFConsumerBaseV2 {
  // * Type Declarations ** //
  enum RaffleState {
    Open,
    Calculating,
    Closed
  }

  // * Errors ** //
  error Raffle__NotEnoughEntranceFees();
  error Raffle__NotOwner();
  error Raffle__RaffleNotOpen();
  error Raffle__TransferFailed();
  error Raffle__UpkeepNotNeeded();


  // * Constants and Immutables ** //
  uint16 private constant REQUEST_CONFIRMATIONS = 3;
  uint32 private constant NUM_WORDS = 1;

  address private immutable owner;
  address private lastWinner;
  bytes32 private immutable gasLane;
  uint private immutable entranceFees;
  uint private immutable withdrawInterval;
  uint32 private immutable callbackGasLimit;
  uint64 private immutable subscriptionId;
  VRFCoordinatorV2Interface private immutable vrfCoordinator;
  RaffleState private state;


  // ** State Variables ** //
  uint private lastWithdrawTimestamp;
  address payable[] private players;

  // ** Events ** //
  event Raffle__RequestedRaffleWinner(uint256 indexed requestId);
  event Raffle__RaffleEntered(address indexed player);  
  event Raffle__RaffleFulfilled(uint requestId, address winner);

  constructor(
    address _vrfCoordinator,
    bytes32 _gasLane,
    uint _entranceFees,
    uint _withdrawInterval,
    uint32 _callbackGasLimit,
    uint64 _subscriptionId
  ) VRFConsumerBaseV2(_vrfCoordinator) {
    callbackGasLimit = _callbackGasLimit;
    entranceFees = _entranceFees;
    gasLane = _gasLane;
    lastWithdrawTimestamp = block.timestamp;
    owner = msg.sender;
    state = RaffleState.Open;
    subscriptionId = _subscriptionId;
    vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
    withdrawInterval = _withdrawInterval;
  }

  function enterRaffle() external payable {
    if (state != RaffleState.Open) {
      revert Raffle__RaffleNotOpen();
    }

    if (msg.value < entranceFees) {
      revert Raffle__NotEnoughEntranceFees();
    }

    players.push(payable(msg.sender));
    emit Raffle__RaffleEntered(msg.sender);
  }

  function checkUpkeep(
    bytes memory /* data */
  ) public view returns (bool upkeepNeeded, bytes memory /* data */) {
    bool timePassed = block.timestamp - lastWithdrawTimestamp >= withdrawInterval;
    bool poolFilled = players.length > 0;
    bool isOpen = state == RaffleState.Open;

    upkeepNeeded = timePassed && poolFilled && isOpen;
    return (upkeepNeeded, "");
  }

  function performUpkeep(bytes memory /* data */) external {
    (bool success, ) = checkUpkeep("");
    if (!success) {
      revert Raffle__UpkeepNotNeeded();
    }

    state = RaffleState.Calculating;

    uint256 requestId = vrfCoordinator.requestRandomWords(
        gasLane,
        subscriptionId,
        REQUEST_CONFIRMATIONS,
        callbackGasLimit,
        NUM_WORDS
    );

    emit Raffle__RequestedRaffleWinner(requestId);
  }

  function fulfillRandomWords(
    uint256 _requestId,
    uint256[] memory _randomWords
  ) internal override {
    console.log("Raffle.sol -> fulfillRandomWords -> called");
    address payable winner = players[_randomWords[0] % players.length];
    state = RaffleState.Open;
    lastWinner = winner;
    players = new address payable[](0);
    lastWithdrawTimestamp = block.timestamp;

    emit Raffle__RaffleFulfilled(_requestId, winner);

    (bool success, ) = winner.call{ value: address(this).balance }("");
    if (!success) {
      revert Raffle__TransferFailed();
    }
  }

  function getEntranceFees() public view returns (uint) {
    return entranceFees;
  }

  function getCurrentState() public view returns (RaffleState) {
    return state;
  }

    function getLastWinner() public view returns (address) {
    return lastWinner;
  }

  function totalJoinedPlayers() public view returns (uint) {
    return players.length;
  }

  modifier onlyOwner {
    if (msg.sender != owner) {
      revert Raffle__NotOwner();
    }
    _;
  }
}