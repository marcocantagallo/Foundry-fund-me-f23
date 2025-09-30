// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FundMe.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Minimal Mock of Chainlink AggregatorV3Interface used by PriceConverter
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _version;

    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        _answer = initialAnswer;
        _version = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "v0.0.0";
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    // keep simple deterministic round values
    function getRoundData(
        uint80
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, _answer, block.timestamp, block.timestamp, 0);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, _answer, block.timestamp, block.timestamp, 0);
    }

    // helper to change price in tests
    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }
}

contract FundMeTest is Test {
    FundMe fundMe;
    MockV3Aggregator mockPriceFeed;

    // constants copied from FundMe contract for ease of use
    uint256 public constant MINIMUM_USD = 5 * 10 ** 18;

    address public deployer;

    function setUp() public {
        deployer = address(this);
        // price feed: 2000 USD with 8 decimals -> 2000 * 1e8
        int256 initialPrice = int256(2000 * 10 ** 8);
        mockPriceFeed = new MockV3Aggregator(8, initialPrice);
        fundMe = new FundMe(address(mockPriceFeed));
    }

    function testConstructorSetsOwnerAndPriceFeed() public {
        assertEq(fundMe.getOwner(), address(this));
        assertEq(address(fundMe.getPriceFeed()), address(mockPriceFeed));
        // version should match mock
        assertEq(fundMe.getVersion(), mockPriceFeed.version());
    }

    function testFundFailsWithoutEnoughETH() public {
        // send a tiny amount -- should revert with the require message
        vm.expectRevert(bytes("You need to spend more ETH!"));
        fundMe.fund{value: 1}();
    }

    function testFundUpdatesDataStructures() public {
        address user = vm.addr(1);
        uint256 sendValue = 0.01 ether; // With price=2000 USD/ETH this is > $5
        vm.deal(user, sendValue);
        vm.prank(user);
        fundMe.fund{value: sendValue}();

        // mapping updated
        assertEq(fundMe.getAddressToAmountFunded(user), sendValue);
        // funder recorded
        assertEq(fundMe.getFunder(0), user);
    }

    function testOnlyOwnerCanWithdraw() public {
        address nonOwner = vm.addr(2);
        // fund with a valid funder so there is something to withdraw
        address funder = vm.addr(3);
        uint256 sendValue = 0.01 ether;
        vm.deal(funder, sendValue);
        vm.prank(funder);
        fundMe.fund{value: sendValue}();

        // Try withdraw from non-owner: expect custom error FundMe__NotOwner()
        bytes4 selector = bytes4(keccak256("FundMe__NotOwner()"));
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodePacked(selector));
        fundMe.withdraw();
    }

    function testWithdrawWithSingleFunderWithdrawsFundsAndResets() public {
        address funder = vm.addr(4);
        uint256 sendValue = 0.01 ether;
        vm.deal(funder, sendValue);
        vm.prank(funder);
        fundMe.fund{value: sendValue}();

        uint256 startingOwnerBalance = address(this).balance;
        uint256 contractBalance = address(fundMe).balance;
        assertEq(contractBalance, sendValue);

        // owner (this) calls withdraw
        fundMe.withdraw();

        // contract balance should be zero
        assertEq(address(fundMe).balance, 0);
        // owner received the funds
        assertEq(address(this).balance, startingOwnerBalance + contractBalance);
        // funder's mapping reset
        assertEq(fundMe.getAddressToAmountFunded(funder), 0);
        // getFunder(0) should revert because array cleared
        vm.expectRevert();
        fundMe.getFunder(0);
    }

    function testCheaperWithdrawWithMultipleFunders() public {
        // create multiple funders
        uint256 numberOfFunders = 5;
        uint256 sendValue = 0.01 ether;
        for (uint256 i = 0; i < numberOfFunders; i++) {
            address funder = vm.addr(10 + i);
            vm.deal(funder, sendValue);
            vm.prank(funder);
            fundMe.fund{value: sendValue}();
        }

        uint256 startingOwnerBalance = address(this).balance;
        uint256 expectedTotal = numberOfFunders * sendValue;
        assertEq(address(fundMe).balance, expectedTotal);

        // owner calls cheaperWithdraw
        fundMe.cheaperWithdraw();

        // contract emptied
        assertEq(address(fundMe).balance, 0);
        // owner balance increased by expected total
        assertEq(address(this).balance, startingOwnerBalance + expectedTotal);

        // all funders reset
        for (uint256 i = 0; i < numberOfFunders; i++) {
            address funder = vm.addr(10 + i);
            assertEq(fundMe.getAddressToAmountFunded(funder), 0);
        }

        // getFunder(0) should revert
        vm.expectRevert();
        fundMe.getFunder(0);
    }

    function testGetAddressToAmountFundedForZeroReturnsZero() public {
        address nobody = vm.addr(99);
        assertEq(fundMe.getAddressToAmountFunded(nobody), 0);
    }

    receive() external payable {}
}
