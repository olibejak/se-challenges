//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { PredictionMarketToken } from "./PredictionMarketToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PredictionMarket is Ownable {
    /////////////////
    /// Errors //////
    /////////////////

    error PredictionMarket__MustProvideETHForInitialLiquidity();
    error PredictionMarket__InvalidProbability();
    error PredictionMarket__PredictionAlreadyReported();
    error PredictionMarket__OnlyOracleCanReport();
    error PredictionMarket__OwnerCannotCall();
    error PredictionMarket__PredictionNotReported();
    error PredictionMarket__InsufficientWinningTokens();
    error PredictionMarket__AmountMustBeGreaterThanZero();
    error PredictionMarket__MustSendExactETHAmount();
    error PredictionMarket__InsufficientTokenReserve(Outcome _outcome, uint256 _amountToken);
    error PredictionMarket__TokenTransferFailed();
    error PredictionMarket__ETHTransferFailed();
    error PredictionMarket__InsufficientBalance(uint256 _tradingAmount, uint256 _userBalance);
    error PredictionMarket__InsufficientAllowance(uint256 _tradingAmount, uint256 _allowance);
    error PredictionMarket__InsufficientLiquidity();
    error PredictionMarket__InvalidPercentageToLock();

    //////////////////////////
    /// State Variables //////
    //////////////////////////

    enum Outcome {
        YES,
        NO
    }

    uint256 private constant PRECISION = 1e18;

    /// Checkpoint 2 ///
    address immutable public i_oracle;
    string public s_question;
    uint256 immutable public i_initialTokenValue;
    uint8 immutable public i_initialYesProbability;
    uint8 immutable public i_percentageLocked;
    uint256 public s_ethCollateral;
    uint256 public s_lpTradingRevenue;

    /// Checkpoint 3 ///
    PredictionMarketToken immutable public i_yesToken;
    PredictionMarketToken immutable public i_noToken;

    /// Checkpoint 5 ///
    PredictionMarketToken public s_winningToken;
    bool public s_isReported;

    /////////////////////////
    /// Events //////
    /////////////////////////

    event TokensPurchased(address indexed buyer, Outcome outcome, uint256 amount, uint256 ethAmount);
    event TokensSold(address indexed seller, Outcome outcome, uint256 amount, uint256 ethAmount);
    event WinningTokensRedeemed(address indexed redeemer, uint256 amount, uint256 ethAmount);
    event MarketReported(address indexed oracle, Outcome winningOutcome, address winningToken);
    event MarketResolved(address indexed resolver, uint256 totalEthToSend);
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokensAmount);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokensAmount);

    /////////////////
    /// Modifiers ///
    /////////////////

    /// Checkpoint 5 ///
    modifier predictionNotReported() {
        if (s_isReported) {
            revert PredictionMarket__PredictionAlreadyReported();
        }
        _;
    }

    /// Checkpoint 6 ///
    modifier predictionReported() {
        if (!s_isReported) {
            revert PredictionMarket__PredictionNotReported();
        }
        _;
    }

    /// Checkpoint 8 ///
    modifier tokenAmountNotNull(uint256 _amountTokenToBuy) {
        if (_amountTokenToBuy == 0) {
            revert PredictionMarket__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier notOwner() {
        if (msg.sender == owner()) {
            revert PredictionMarket__OwnerCannotCall(); 
        }
        _;
    }

    //////////////////
    ////Constructor///
    //////////////////

    constructor(
        address _liquidityProvider,
        address _oracle,
        string memory _question,
        uint256 _initialTokenValue,
        uint8 _initialYesProbability,
        uint8 _percentageToLock
    ) payable Ownable(_liquidityProvider) {
        /// Checkpoint 2 ////
        if (msg.value == 0) {
            revert PredictionMarket__MustProvideETHForInitialLiquidity();
        }
        if (_initialYesProbability == 0 || _initialYesProbability >= 100) {
            revert PredictionMarket__InvalidProbability();
        }
        if (_percentageToLock == 0 || _percentageToLock >= 100) {
            revert PredictionMarket__InvalidPercentageToLock();
        }

        i_oracle = _oracle;
        s_question = _question;
        i_initialTokenValue = _initialTokenValue;
        i_initialYesProbability = _initialYesProbability;
        i_percentageLocked = _percentageToLock;
        s_ethCollateral = msg.value;

        /// Checkpoint 3 ////
        uint256 initialTokenAmount = (msg.value * PRECISION) / _initialTokenValue;
        i_yesToken = new PredictionMarketToken("YES", "Y", _liquidityProvider, initialTokenAmount);
        i_noToken = new PredictionMarketToken("NO", "N", _liquidityProvider, initialTokenAmount);
        uint256 initialYesAmountLocked = (initialTokenAmount * i_initialYesProbability * _percentageToLock * 2) / 10000;
        uint256 initialNoAmountLocked = (initialTokenAmount * (100 - i_initialYesProbability) * _percentageToLock * 2) / 10000;

        if (i_yesToken.transfer(_liquidityProvider, initialYesAmountLocked) == false ||
           i_noToken.transfer(_liquidityProvider, initialNoAmountLocked) == false) {
            revert PredictionMarket__TokenTransferFailed();
        }
    }

    /////////////////
    /// Functions ///
    /////////////////

    /**
     * @notice Add liquidity to the prediction market and mint tokens
     * @dev Only the owner can add liquidity and only if the prediction is not reported
     */
    function addLiquidity() external payable onlyOwner predictionNotReported {
        //// Checkpoint 4 ////
        s_ethCollateral += msg.value;
        uint256 tokensAmount = (msg.value * PRECISION) / i_initialTokenValue;
        i_yesToken.mint(address(this), tokensAmount);
        i_noToken.mint(address(this), tokensAmount);
        emit LiquidityAdded(msg.sender, msg.value, tokensAmount);
    }

    /**
     * @notice Remove liquidity from the prediction market and burn respective tokens, if you remove liquidity before prediction ends you got no share of lpReserve
     * @dev Only the owner can remove liquidity and only if the prediction is not reported
     * @param _ethToWithdraw Amount of ETH to withdraw from liquidity pool
     */
    function removeLiquidity(uint256 _ethToWithdraw) external onlyOwner predictionNotReported {
        //// Checkpoint 4 ////
        uint256 amountTokenToBurn = (_ethToWithdraw / i_initialTokenValue) * PRECISION;

        if (i_yesToken.balanceOf(address(this)) < amountTokenToBurn) {
          revert PredictionMarket__InsufficientTokenReserve(Outcome.YES, amountTokenToBurn);
        }
        if (i_noToken.balanceOf(address(this)) < amountTokenToBurn) {
          revert PredictionMarket__InsufficientTokenReserve(Outcome.NO, amountTokenToBurn);
        }

        s_ethCollateral -= _ethToWithdraw;
        i_yesToken.burn(address(this), amountTokenToBurn);
        i_noToken.burn(address(this), amountTokenToBurn);
        payable(msg.sender).transfer(_ethToWithdraw);
        emit LiquidityRemoved(msg.sender, _ethToWithdraw, amountTokenToBurn);

    }

    /**
     * @notice Report the winning outcome for the prediction
     * @dev Only the oracle can report the winning outcome and only if the prediction is not reported
     * @param _winningOutcome The winning outcome (YES or NO)
     */
    function report(Outcome _winningOutcome) external predictionNotReported {
        //// Checkpoint 5 ////
        if (msg.sender != i_oracle) {
            revert PredictionMarket__OnlyOracleCanReport();
        }
        s_isReported = true;
        if (_winningOutcome == Outcome.YES) {
            s_winningToken = i_yesToken;
        } else {
            s_winningToken = i_noToken;
        }
        emit MarketReported(msg.sender, _winningOutcome, address(s_winningToken));
    }

    /**
     * @notice Owner of contract can redeem winning tokens held by the contract after prediction is resolved and get ETH from the contract including LP revenue and collateral back
     * @dev Only callable by the owner and only if the prediction is resolved
     * @return ethRedeemed The amount of ETH redeemed
     */
    function resolveMarketAndWithdraw() external onlyOwner predictionReported returns (uint256 ethRedeemed) {
        /// Checkpoint 6 ////
        uint256 contractWinningTokens = s_winningToken.balanceOf(address(this));
        ethRedeemed = (contractWinningTokens * i_initialTokenValue) / PRECISION;
        if (ethRedeemed > s_ethCollateral) {
            ethRedeemed = s_ethCollateral;
        }

        s_ethCollateral -= ethRedeemed;
        uint256 totalEthToSend = ethRedeemed + s_lpTradingRevenue;
        s_lpTradingRevenue = 0;
        s_winningToken.burn(address(this), contractWinningTokens);
        payable(msg.sender).transfer(ethRedeemed);

        emit MarketResolved(msg.sender, totalEthToSend);
    }

    /**
     * @notice Buy prediction outcome tokens with ETH, need to call priceInETH function first to get right amount of tokens to buy
     * @param _outcome The possible outcome (YES or NO) to buy tokens for
     * @param _amountTokenToBuy Amount of tokens to purchase
     */
    function buyTokensWithETH(Outcome _outcome, uint256 _amountTokenToBuy) external payable predictionNotReported tokenAmountNotNull(_amountTokenToBuy) notOwner {
        /// Checkpoint 8 ////
        (uint256 currentReserve, ) = _getCurrentReserves(_outcome);
        if (currentReserve < _amountTokenToBuy) {
            revert PredictionMarket__InsufficientLiquidity();
        }
        if (msg.value != getBuyPriceInEth(_outcome, _amountTokenToBuy)) {
            revert PredictionMarket__MustSendExactETHAmount();
        }
        s_lpTradingRevenue += msg.value;
        if (_outcome == Outcome.YES) {
            i_yesToken.transfer(msg.sender, _amountTokenToBuy);
        } else {
            i_noToken.transfer(msg.sender, _amountTokenToBuy);
        }

        emit TokensPurchased(msg.sender, _outcome, _amountTokenToBuy, msg.value);
    }

    /**
     * @notice Sell prediction outcome tokens for ETH, need to call priceInETH function first to get right amount of tokens to buy
     * @param _outcome The possible outcome (YES or NO) to sell tokens for
     * @param _tradingAmount The amount of tokens to sell
     */
    function sellTokensForEth(Outcome _outcome, uint256 _tradingAmount) external predictionNotReported tokenAmountNotNull(_tradingAmount) notOwner {
        /// Checkpoint 8 ////
        uint256 senderTokenAmount;
        uint256 allowance;
        if (_outcome == Outcome.YES) {
            senderTokenAmount = i_yesToken.balanceOf(msg.sender);
            allowance = i_yesToken.allowance(msg.sender, address(this));
        } else {
            senderTokenAmount = i_noToken.balanceOf(msg.sender);
            allowance = i_noToken.allowance(msg.sender, address(this));
        }
        
        uint256 currentTokenPrice = _calculatePriceInEth(_outcome, _tradingAmount, true);

        if (senderTokenAmount < _tradingAmount)
            revert PredictionMarket__InsufficientBalance(_tradingAmount, senderTokenAmount);
        if (currentTokenPrice > address(this).balance)
            revert PredictionMarket__InsufficientLiquidity();
        if (allowance < _tradingAmount)
            revert PredictionMarket__InsufficientAllowance(_tradingAmount, allowance);

        s_lpTradingRevenue -= currentTokenPrice;

        payable(msg.sender).transfer(currentTokenPrice);

        _outcome == Outcome.YES 
            ? i_yesToken.transferFrom(msg.sender, address(this), _tradingAmount)
            : i_noToken.transferFrom(msg.sender, address(this), _tradingAmount);

        emit TokensSold(msg.sender, _outcome, _tradingAmount, currentTokenPrice);
    }

    /**
     * @notice Redeem winning tokens for ETH after prediction is resolved, winning tokens are burned and user receives ETH
     * @dev Only if the prediction is resolved
     * @param _amount The amount of winning tokens to redeem
     */
    function redeemWinningTokens(uint256 _amount) external predictionReported tokenAmountNotNull(_amount) notOwner {
        /// Checkpoint 9 ////
        if (s_winningToken.balanceOf(msg.sender) != _amount)
            revert PredictionMarket__InsufficientWinningTokens();

        uint256 winningPriceInEth = _amount * i_initialTokenValue / PRECISION; 
        s_ethCollateral -= winningPriceInEth;
        s_winningToken.burn(msg.sender, _amount);
        payable(msg.sender).transfer(winningPriceInEth);

        emit WinningTokensRedeemed(msg.sender, _amount, winningPriceInEth);
    }

    /**
     * @notice Calculate the total ETH price for buying tokens
     * @param _outcome The possible outcome (YES or NO) to buy tokens for
     * @param _tradingAmount The amount of tokens to buy
     * @return The total ETH price
     */
    function getBuyPriceInEth(Outcome _outcome, uint256 _tradingAmount) public view returns (uint256) {
        /// Checkpoint 7 ////
        return _calculatePriceInEth(_outcome, _tradingAmount, false);
    }

    /**
     * @notice Calculate the total ETH price for selling tokens
     * @param _outcome The possible outcome (YES or NO) to sell tokens for
     * @param _tradingAmount The amount of tokens to sell
     * @return The total ETH price
     */
    function getSellPriceInEth(Outcome _outcome, uint256 _tradingAmount) public view returns (uint256) {
        /// Checkpoint 7 ////
        return _calculatePriceInEth(_outcome, _tradingAmount, true);
    }

    /////////////////////////
    /// Helper Functions ///
    ////////////////////////

    /**
     * @dev Internal helper to calculate ETH price for both buying and selling
     * @param _outcome The possible outcome (YES or NO)
     * @param _tradingAmount The amount of tokens
     * @param _isSelling Whether this is a sell calculation
     */
    function _calculatePriceInEth(
        Outcome _outcome,
        uint256 _tradingAmount,
        bool _isSelling
    ) private view returns (uint256) {
        /// Checkpoint 7 ////
        (uint256 currentReserve, uint256 currentOtherReserve) = _getCurrentReserves(_outcome);

        if (!_isSelling && currentReserve < _tradingAmount) {
            revert PredictionMarket__InsufficientLiquidity();
        }

        uint256 totalSupply = i_yesToken.totalSupply(); 

        uint256 currentTokensSoldBefore = totalSupply - currentReserve;
        uint256 currentOtherTokensSoldBefore = totalSupply - currentOtherReserve;
        uint256 totalTokensSoldBefore = currentTokensSoldBefore + currentOtherTokensSoldBefore;
        uint256 probabilityBefore = _calculateProbability(currentTokensSoldBefore, totalTokensSoldBefore);

        uint256 currentReserveAfter = _isSelling ? currentReserve + _tradingAmount : currentReserve - _tradingAmount;
        uint256 currentTokenSoldAfter = totalSupply - currentReserveAfter;
        uint256 totalTokensSoldAfter = _isSelling ? totalTokensSoldBefore - _tradingAmount : totalTokensSoldBefore + _tradingAmount;
        uint256 probabilityAfter = _calculateProbability(currentTokenSoldAfter, totalTokensSoldAfter);

        uint256 probabilityAvg = (probabilityBefore + probabilityAfter) / 2;

        return (_tradingAmount * i_initialTokenValue * probabilityAvg) / (PRECISION**2);
    }

    /**
     * @dev Internal helper to get the current reserves of the tokens
     * @param _outcome The possible outcome (YES or NO)
     * @return The current reserves of the tokens
     */
    function _getCurrentReserves(Outcome _outcome) private view returns (uint256, uint256) {
        /// Checkpoint 7 ////
        if (_outcome == Outcome.YES) {
            return (i_yesToken.balanceOf(address(this)), i_noToken.balanceOf(address(this)));
        } else {
            return (i_noToken.balanceOf(address(this)), i_yesToken.balanceOf(address(this)));
        }
    }

    /**
     * @dev Internal helper to calculate the probability of the tokens
     * @param tokensSold The number of tokens sold
     * @param totalSold The total number of tokens sold
     * @return The probability of the tokens
     */
    function _calculateProbability(uint256 tokensSold, uint256 totalSold) private pure returns (uint256) {
        /// Checkpoint 7 ////
        return (tokensSold * PRECISION) / totalSold;
    }

    /////////////////////////
    /// Getter Functions ///
    ////////////////////////

    /**
     * @notice Get the prediction details
     */
    function getPrediction()
        external
        view
        returns (
            string memory question,
            string memory outcome1,
            string memory outcome2,
            address oracle,
            uint256 initialTokenValue,
            uint256 yesTokenReserve,
            uint256 noTokenReserve,
            bool isReported,
            address yesToken,
            address noToken,
            address winningToken,
            uint256 ethCollateral,
            uint256 lpTradingRevenue,
            address predictionMarketOwner,
            uint256 initialProbability,
            uint256 percentageLocked
        )
    {
        /// Checkpoint 3 ////
        oracle = i_oracle;
        initialTokenValue = i_initialTokenValue;
        percentageLocked = i_percentageLocked;
        initialProbability = i_initialYesProbability;
        question = s_question;
        ethCollateral = s_ethCollateral;
        lpTradingRevenue = s_lpTradingRevenue;
        predictionMarketOwner = owner();
        yesToken = address(i_yesToken);
        noToken = address(i_noToken);
        outcome1 = i_yesToken.name();
        outcome2 = i_noToken.name();
        yesTokenReserve = i_yesToken.balanceOf(address(this));
        noTokenReserve = i_noToken.balanceOf(address(this));
        /// Checkpoint 5 ////
        isReported = s_isReported;
        winningToken = address(s_winningToken);
    }
}
