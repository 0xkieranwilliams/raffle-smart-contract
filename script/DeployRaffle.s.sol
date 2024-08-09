// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
      event DeployLog(string message, uint256 value);
    event DeployLogAddress(string message, address addr);
    event DeployLogBytes32(string message, bytes32 value);

  function deployContract() public returns(Raffle, HelperConfig) {
    HelperConfig helperConfig = new HelperConfig();
    HelperConfig.NetworkConfig memory config = helperConfig.getConfig();  

    if (config.subscriptionId == 0) {
      CreateSubscription createSubscription = new CreateSubscription();
      (config.subscriptionId, config.vrfCoordinator) = createSubscription.createSubscription(config.vrfCoordinator, config.account);
      FundSubscription fundSubscription = new FundSubscription();
      fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
    }
    vm.startBroadcast(config.account);
    console.log(config.entranceFee);

    Raffle raffle = new Raffle(
      config.entranceFee,
      config.interval,
      config.vrfCoordinator,
      config.gasLane,
      config.subscriptionId,
      config.callbackGasLimit
    );
    vm.stopBroadcast();

    AddConsumer addConsumer = new AddConsumer();
    addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

    return (raffle, helperConfig);
  }

  function run() external returns (Raffle, HelperConfig){
    return deployContract();
  }
} 
