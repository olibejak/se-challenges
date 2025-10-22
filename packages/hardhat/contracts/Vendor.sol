pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "./YourToken.sol";

contract Vendor is Ownable{
    event BuyTokens(address buyer, uint256 amountOfETH, uint256 amountOfTokens);

    YourToken public yourToken;

    uint256 public constant tokensPerEth = 100;

    constructor(address tokenAddress) Ownable(msg.sender) {
        yourToken = YourToken(tokenAddress);
    }

    // ToDo: create a payable buyTokens() function:
    function buyTokens() external payable {
        uint256 tokenAmount = msg.value * tokensPerEth;
        require(yourToken.balanceOf(address(this)) >= tokenAmount, "Not enough tokens in the reserve");
        yourToken.transfer(msg.sender, tokenAmount);
        emit BuyTokens(msg.sender, msg.value, tokenAmount);
    }

    // ToDo: create a withdraw() function that lets the owner withdraw ETH
    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No ETH to withdraw");
        payable(msg.sender).transfer(amount);
    }

    // ToDo: create a sellTokens(uint256 _amount) function:
    function sellTokens(uint256 tokenAmount) external {
        uint256 ethAmount = tokenAmount / tokensPerEth;

        require(tokenAmount > 0, "Specify an amount of token greater than zero");
        require(yourToken.balanceOf(msg.sender) >= tokenAmount, "You do not have enough tokens");
        require(address(this).balance >= ethAmount, "Vendor does not have enough ETH");

        yourToken.transferFrom(msg.sender, address(this), tokenAmount);

        payable(msg.sender).transfer(ethAmount);
    }
}
