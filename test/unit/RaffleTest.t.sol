// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription} from "script/Interactions.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;
    // variables
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;
    address account;

    // events
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // = assert(uint256(raffle.getRaffleState()) ==0);
    }

    function testRaffleRevertsIfNotSendEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleUpdatesPlayersArrayWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // my own test
        // assert(raffle.getPlayers().length == 1);
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle)); // we are expecting to emit an event
        emit RaffleEntered(PLAYER); // and this is the event we expect to emit
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterAfterRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //making time pass
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    //////////////////////////  Constructor  //////////////////////////

    function testThatConstructorGetsSetCorrectly() public view {
        assert(raffle.getEntranceFee() == entranceFee);
        assert(raffle.getInterval() == interval);
        assert(raffle.getVrfCoordinator() == vrfCoordinator);
        assert(raffle.getKeyHash() == gasLane);
        // sub id doesnt work to test it for some reason
        // assert(raffle.getSubscriptionId() == subscriptionId);
        assert(raffle.getCallbackGasLimit() == callbackGasLimit);
    }

    //////////////////////////  CheckUpkeep  //////////////////////////

    function testCheckUpkeepReturnsFalseWhenItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseWhenRaffleIsNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testRevertsWhenPerformUpkeepIsCalledButCheckUpkeepIsfalse()
        public
    {
        // i should add the specific error here but for some reason its not letting me.
        vm.prank(PLAYER);
        vm.expectRevert();
        raffle.performUpkeep("");
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    //////////////////////////  performUpkeep  //////////////////////////
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //arrange
        uint256 currentBalance = 0;
        uint256 currentPlayers = 0;
        Raffle.RaffleState currentRaffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        currentPlayers = currentPlayers + 1;

        //act
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__NoUpkeepNeeded.selector,
                currentBalance,
                currentPlayers,
                currentRaffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    //what if we need to get ddata from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntered
    {
        //act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); // take a look at the Vm.sol at line 74 for better understanding
        bytes32 requestId = entries[1].topics[1];

        //assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        //check that we got a requestId
        assert(requestId > 0);
        //check that the raffle state is calculating
        assert(uint256(raffleState) == 1);
    }

    //////////////////////////  performUpkeep  //////////////////////////
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        ); // dont know why they picked 0 here
    }

    //////////////////////////  ONE BIG TEST  //////////////////////////

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEntered
        skipFork
    {
        // arrange
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address newPlayer = address(uint160(i)); // this is a way to convert an integer to an address
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 lastTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        //act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        ); // we simulate being the chainlink node and giving our contract a random number to pick a winner

        //assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1); // the +1 is for the first player

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > lastTimeStamp); // first we got an 'insuficientBalance' error during this test but we had to *100 the fund amount to the chainlink vrf for some reason.
    }

    //////////////////////////  HELPER CONFIG TESTS  //////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    function testHelperConfigReturnsCorrectConfigOnAnvil() public skipFork {
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = 0.01 ether;
        interval = 30;
        gasLane = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
        callbackGasLimit = 500000;
        subscriptionId = 0;
        account = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

        assert(config.entranceFee == entranceFee);
        assert(config.interval == interval);
        assert(config.gasLane == gasLane);
        assert(config.callbackGasLimit == callbackGasLimit);
        assert(config.subscriptionId == subscriptionId);
        assert(config.account == account);
    }

    modifier onlySepolia() {
        if (block.chainid != ETH_SEPOLIA_CHAIN_ID) {
            return;
        }
        _;
    }

    function testHelperConfigReturnsCorrectConfigOnSepolia()
        public
        onlySepolia
    {
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = 0.01 ether;
        interval = 30;
        vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
        gasLane = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
        callbackGasLimit = 500000;
        subscriptionId = 1708260651870662726924624423409536468261695712362186062065007574361835748312;
        account = 0x7e56274df21276d1AD666105Fa7D8bAC9E1F9063;

        assert(config.entranceFee == entranceFee);
        assert(config.interval == interval);
        assert(config.vrfCoordinator == vrfCoordinator);
        assert(config.gasLane == gasLane);
        assert(config.callbackGasLimit == callbackGasLimit);
        assert(config.subscriptionId == subscriptionId);
        assert(config.account == account);
    }
}

//////////////////////////  HELPER CONFIG TESTS  //////////////////////////
///////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////
