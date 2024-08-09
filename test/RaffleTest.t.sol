// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
  Raffle public raffle;
  HelperConfig public helperConfig;

  event RaffleEntered(address indexed player);
  event WinnerPicked(address indexed winner);

  uint256 entranceFee;
  uint256 interval;
  address vrfCoordinator;
  bytes32 gasLane;
  uint32 callbackGasLimit;
  uint256 subscriptionId;
  
  address public PLAYER = makeAddr("player");
  uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

  function setUp() external {
    DeployRaffle deployer = new DeployRaffle();
    (raffle, helperConfig) = deployer.run();
    vm.deal(PLAYER, STARTING_PLAYER_BALANCE);

    HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
    entranceFee = config.entranceFee;
    interval = config.interval;
    vrfCoordinator = config.vrfCoordinator;
    gasLane = config.gasLane;
    callbackGasLimit = config.callbackGasLimit;
    subscriptionId = config.subscriptionId;
  }  

  function testRaffleInitalizesInStartingState() public view {
    assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
  }

  function testRaffleRevertsWhenYouDontPayEnough() public {
    vm.prank(PLAYER);
    vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
    raffle.enterRaffle();
  }

  function testRaffleRecordsPlayersWhenTheyEnter() public {
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    address playerRecorded = raffle.getPlayer(0);
    assert(playerRecorded == PLAYER);
  }

  function testEnteringEmitsEvent() public {
      vm.prank(PLAYER);
      vm.expectEmit(true, false, false, false, address(raffle));
      emit RaffleEntered(PLAYER);
      raffle.enterRaffle{value: entranceFee}();
  }

  function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
     vm.prank(PLAYER);
     raffle.enterRaffle{value: entranceFee}();
     vm.warp(block.timestamp + interval + 1);
     vm.roll(block.number+1);
     raffle.performUpkeep("");

     vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
     vm.prank(PLAYER);
     raffle.enterRaffle{value: entranceFee}();
  }

  function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);
    (bool upkeepNeeded, ) =  raffle.checkUpkeep(""); 

    assert(!upkeepNeeded);
  }

  function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);
    raffle.performUpkeep("");

    (bool upkeepNeeded,) = raffle.checkUpkeep("");
    assert(!upkeepNeeded);
  }

  function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);

    raffle.performUpkeep("");
  }

  function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
     uint256 currentBalance = 0;
     uint256 numPlayers = 0;
     Raffle.RaffleState rState = raffle.getRaffleState();

     vm.prank(PLAYER);
     raffle.enterRaffle{value: entranceFee}();
     currentBalance = currentBalance + entranceFee;
     numPlayers = 1;

     vm.expectRevert(
       abi.encodeWithSelector(Raffle.Raffle__UpKeepNotNeeded.selector, currentBalance, numPlayers, rState)
     );
     raffle.performUpkeep("");
  }

  modifier raffleEntered () {
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);
    _;
  }

  function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {

    vm.recordLogs();
    raffle.performUpkeep("");
    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 requestId = entries[1].topics[1];

    Raffle.RaffleState raffleState = raffle.getRaffleState();
    assert(uint256(requestId) > 0);
    assert(uint256(raffleState) == 1);
  }

  modifier skipFork() {
    if (block.chainid != LOCAL_CHAIN_ID) {
      return;
    }
    _;
  }

  function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork{
    vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
  }

  function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork { 
    uint256 additionalEntrants = 3;
    uint256 startingIndex = 1;
    address expectedWinner = address(1);
    
    for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
      address newPlayer = address(uint160(i));
      hoax(newPlayer, 1 ether);
      raffle.enterRaffle{value: entranceFee}();
    }

    uint256 startingTimeStamp = raffle.getLastTimeStamp();
    uint256 winnerStartingBalance = expectedWinner.balance;

    vm.recordLogs();
    raffle.performUpkeep("");
    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 requestId = entries[1].topics[1];
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

    address recentWinner = raffle.getRecentWinner();
    Raffle.RaffleState raffleState = raffle.getRaffleState();
    uint256 winnerBalance = recentWinner.balance;

    uint256 endingTimeStamp = raffle.getLastTimeStamp();
    uint256 prize = entranceFee * (1 + additionalEntrants);

    assert(recentWinner == expectedWinner);
    assert(uint256(raffleState) == 0);
    assert(winnerBalance == winnerStartingBalance + prize);
    assert(endingTimeStamp > startingTimeStamp);
  }
}
