// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {

    mapping (address => uint256) public balances;
    uint256 public deadline;
    uint256 public threshold = 1 ether;
    bool public openForWithdraw;

    event Stake(address,uint256);

    ExampleExternalContract public exampleExternalContract;

    constructor(address exampleExternalContractAddress) {
        exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
        deadline = block.timestamp + 72 hours;
    }

    // Collect funds in a payable `stake()` function and track individual `balances` with a mapping:
    // (Make sure to add a `Stake(address,uint256)` event and emit it for the frontend `All Stakings` tab to display)
    function stake() external payable {
        require(block.timestamp < deadline, "deadline expired");

        balances[msg.sender] += msg.value;
        emit Stake(msg.sender,msg.value);

    }

    // After some `deadline` allow anyone to call an `execute()` function
    // If the deadline has passed and the threshold is met, it should call `exampleExternalContract.complete{value: address(this).balance}()`
    function execute() external {
        require(block.timestamp >= deadline, "deadline not completed");

        if (address(this).balance >= threshold) {
            exampleExternalContract.complete{value: address(this).balance}();
        } else {
            openForWithdraw = true;
        }
    }

    // If the `threshold` was not met, allow everyone to call a `withdraw()` function to withdraw their balance
    function withdraw() external {
        require(openForWithdraw, "not open for withdraw");
        uint256 amount = balances [msg.sender];
        balances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    // Add a `timeLeft()` view function that returns the time left before the deadline for the frontend
    function timeLeft() external view returns (uint256) {
        if (block.timestamp >= deadline) {
            return 0;
        }
        return deadline - block.timestamp;
    }

    // Add the `receive()` special function that receives eth and calls stake()
    receive() external payable {
        this.stake();
    }
}
