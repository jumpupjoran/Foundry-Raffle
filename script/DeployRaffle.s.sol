// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // deploy HelperConfig
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            //create subscription
            CreateSubscription subscriptionContract = new CreateSubscription();
            (
                config.subscriptionId,
                config.vrfCoordinator
            ) = subscriptionContract.createSubscription(
                config.vrfCoordinator,
                config.account
            );
            // or you could do like this (its the same but you let your helperconfig take the right vrf coordinator addres):
            // ( config.subscriptionId, config.vrfCoordinator) = subscriptionContract.createSubscriptionUsingConfig();

            //fund subscription
            FundSubscription fundSubscriptionContract = new FundSubscription();
            fundSubscriptionContract.fundSubscription(
                config.vrfCoordinator,
                config.subscriptionId,
                config.link,
                config.account
            );
        }

        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );

        vm.stopBroadcast();

        AddConsumer addConsumerContract = new AddConsumer();
        // we have a broadcast inside addconsumer already
        addConsumerContract.addConsumer(
            address(raffle),
            config.vrfCoordinator,
            config.subscriptionId,
            config.account
        );
        return (raffle, helperConfig);
    }

    // function deployContract() public returns (Raffle, HelperConfig) {}
}
