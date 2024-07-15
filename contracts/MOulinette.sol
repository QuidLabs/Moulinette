// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.8; 
// pragma experimental SMTChecker;
import "hardhat/console.sol"; // TODO delete these 2 
import "@openzeppelin/contracts/access/Ownable.sol";

import {TransferHelper} from "./interfaces/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/AggregatorV3Interface.sol";
import {TickMath} from "./interfaces/math/TickMath.sol";
import {FullMath} from "./interfaces/math/FullMath.sol";
import {LiquidityAmounts} from "./interfaces/math/LiquidityAmounts.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

interface IWETH is IERC20 {
    function deposit() 
    external payable;
}

contract Moulinette is // en.wiktionary.org/wiki/moulinette
    IERC721Receiver, Ownable { 
    // TODO delete these 
    address public SUSDE;
    address public SFRAX; 
    address public SDAI;
    address public QUID;
    address public WETH; 
    address public WBTC; 
    
    // TODO uncomment these
    // address constant public SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    // address constant public SFRAX = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;
    // address constant public SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    // address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address constant public WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // 0.3% fee tier has tick spacing of 60; 
    uint24 constant public POOL_FEE = 3000;  
    uint constant public STACK = BILL * 100;
    uint constant public PENNY = WAD / 100;
    uint constant public BILL = 100 * WAD;
    uint constant public WAD = 1e18; 
    INonfungiblePositionManager NFPM;

    int24 constant INCREMENT = 60;
    int24 internal LAST_TWAP_TICK;

    int24 internal UPPER_TICK;
    int24 internal LOWER_TICK;
    uint public FEE = WAD / 28; 
    error UnsupportedToken();

    uint public TOKEN_ID; // protocol manages one giant NFT deposit 
    IUniswapV3Pool POOL; // the largest liquidity pool on UNIswapV3
    
    uint internal _ETH_PRICE; // TODO delete when finished testing
    uint internal _BTC_PRICE; // TODO delete when finished testing
    
    // Chainlink AggregatorV3 Addresses on mainnnet
    address constant public ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant public BTC_PRICE = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    
    // The following 3 variables are used to _calculateMedian
    uint[90] internal WEIGHTS; // sum of weights for each FEE
    // index 0 represents largest possibility = 9%
    // index 89 represents the smallest one = 1%
    // derivation of FEE = WAD / (index + 11)...
    uint internal MEDIAN = 17; // index of median (+/- 1)
    uint internal SUM; // sum(weights[0..k]) sum of sums...
    struct Pledge { 
        // An offer is a promise or commitment to do
        // or refrain from doing something specific
        // in the future. Our case is bilateral...
        // promise for a promise, aka quid pro quo
        mapping (address => Pod) offers; // stakes
        uint vote; // for what the FEE should be
    }   mapping (address => Pledge) internal quid; 
    // continuous payment comes from Uniswap LP fees
    // while a fixed charge (deductible) is payable 
    // upfront (upon deposit) and upon withdrawal
    // (if a coverage event is thereby triggered)
    // deducted as a % FEE from the $ value that
    // is either being deposited or withdrawn...
    struct Pod { // in the context of most offers,
        uint credit; // sum of (amount x price upon offer)
        uint debit; // actual quantity of tokens pledged 
    }

    // TODO make offers transferrable
    // for quid[pledge].offers[QUID] increment credit variable on any transfer
    // instead of calculating share of credit only in withdraw
        // using snapshots for quid[QUID].offers[QUID] at weekly intervals:
        // snapshot captures both the credit and debit at that moment
    // any pledge has a time stamp of their last state change
        // as the time stamp catches up to the timestamp of the latest snapshot
        // it pulls in shares for each snapshot up to the latest one 

    
    constructor(address _susde, address _wbtc, address _weth) Ownable() { // TODO remove parameters and Ownable (only for testing)
        POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
        address nfpm = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        TransferHelper.safeApprove(WETH, nfpm, type(uint256).max);
        TransferHelper.safeApprove(WBTC, nfpm, type(uint256).max);
        
        SUSDE = _susde; WBTC = _wbtc; WETH = _weth;
        NFPM = INonfungiblePositionManager(nfpm);

        LAST_TWAP_TICK = _getTWAPtick(); QUID = address(this);        
        (UPPER_TICK, LOWER_TICK) = _adjustTicks(LAST_TWAP_TICK);
        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: WBTC, token1: WETH, fee: POOL_FEE,
                tickLower: LOWER_TICK, tickUpper: UPPER_TICK,
                amount0Desired: IERC20(WBTC).balanceOf(QUID),
                amount1Desired: IERC20(WETH).balanceOf(QUID),
                amount0Min: 0, amount1Min: 0, recipient: QUID,
                deadline: block.timestamp });
        (TOKEN_ID,,,) = NFPM.mint(params);
    }
    
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       HELPER FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/
    
    function _min(uint _a, uint _b) internal pure returns (uint) {
        return (_a < _b) ? _a : _b;
    }

    function _isDollar(address dollar) internal returns (bool) {
        return dollar == SUSDE || dollar == SDAI || dollar == SFRAX;
    }
    
    // TODO remove these setters after finish testing, and uncomment in constructor
    function set_price_eth(uint price) external onlyOwner { // set ETH price in USD
        _ETH_PRICE = price;
    }
    function set_price_btc(uint price) external onlyOwner { // set BTC price in USD
        _BTC_PRICE = price;
    }

    function _adjustToNearestIncrement(int24 input) internal pure returns (int24 result) {
        // Adjust the input to the nearest multiple of 60
        int24 remainder = input % 60;
        if (remainder == 0) {
            result = input;
        } else if (remainder >= 30) { // round up
            result = input + (60 - remainder);
        } else { // round down
            result = input - remainder;
        }
        // this last clause is just for sanity
        if (result > 887220) { // max
            return 887220; 
        } else if (-887220 > result) { // min
            return -887220;
        }   return result;
    }

    // Adjust to the nearest multiple of 60
    function _adjustTicks(int24 input) 
        internal pure returns 
        (int24 adjustedIncrease, 
        int24 adjustedDecrease) {
        int256 upper = int256(WAD + WAD / 14);
        int256 lower = int256(WAD - WAD / 14);
        int24 increase = int24((int256(input) * upper) / int256(WAD));
        int24 decrease = int24((int256(input) * lower) / int256(WAD));
        adjustedIncrease = _adjustToNearestIncrement(increase);
        adjustedDecrease = _adjustToNearestIncrement(decrease);
    }
   
    function _getTWAPtick() internal view returns (int24) {
        uint32[] memory ago = new uint32[](2);
        ago[0] = 177777; // ~2 days in seconds
        ago[1] = 0; 
        try POOL.observe(ago) returns (int56[] memory tickCumulatives, uint160[] memory) {
            return int24((tickCumulatives[0] - tickCumulatives[1]) / 177777);
        } catch {
            return int24(0);
        } 
    }

    function _decreaseAndCollect(uint128 liquidity) 
        internal returns (uint amount0, uint amount1) {
        NFPM.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(
                TOKEN_ID, liquidity, 0, 0, block.timestamp
            )
        );
        (amount0, 
         amount1) = NFPM.collect(
            INonfungiblePositionManager.CollectParams(TOKEN_ID, 
                QUID, type(uint128).max, type(uint128).max
            )
        );
    }

    /** 
     * Returns the latest price obtained from the Chainlink ETH:USD aggregator 
     * reference contract...https://docs.chain.link/docs/get-the-latest-price
     */
    function _getPrice(address token) 
    internal view returns (uint price) {
        AggregatorV3Interface chainlink; 
        if (token == WETH) {
            if (_ETH_PRICE > 0) return _ETH_PRICE; // TODO remove
            chainlink = AggregatorV3Interface(ETH_PRICE);
        } else if (token == WBTC) {
            if (_BTC_PRICE > 0) return _BTC_PRICE; // TODO remove
            chainlink = AggregatorV3Interface(BTC_PRICE);
        } else {
            revert UnsupportedToken();
        }
        (, int priceAnswer,, uint timeStamp,) = chainlink.latestRoundData();
        
        require(timeStamp > 0 
            && timeStamp <= block.timestamp 
            && priceAnswer >= 0, "price");
        
        uint8 answerDigits = chainlink.decimals();
        price = uint(priceAnswer);
        // Aggregator returns an 8-digit precision, 
        // but we handle the case of future changes
        if (answerDigits > 18) { price /= 10 ** (answerDigits - 18); }
        else if (answerDigits < 18) { price *= 10 ** (18 - answerDigits); } 
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/    

    function deposit(address beneficiary, uint amount,
                     address token) external payable {
        
        amount = _min(amount, IERC20(token).balanceOf(msg.sender));
        
        require(amount > 0, "insufficient balance");
        Pledge storage pledge = quid[beneficiary];
        if (pledge.vote == 0) { pledge.vote = 7; }
  
        if (_isDollar(token)) {
            uint old_stake = pledge.offers[QUID].debit;
            pledge.offers[QUID].debit += amount;
            quid[QUID].offers[QUID].debit += amount;
            
            _calculateMedian(pledge.offers[QUID].debit, 
                pledge.vote, old_stake, pledge.vote);
        } 
        else { 
            uint amount0; uint amount1; // for Uni LP deposit
            if (token == WBTC) { // has a precision of 8 digits
                amount *= 10 ** 10; // convert for compatibility
            } else {
                amount1 = amount;
                if (msg.value > 0) { 
                    require(token == WETH, "WETH");
                    // WETH becomes available to address(this)
                    IWETH(WETH).deposit{value: msg.value}(); 
                    amount1 += msg.value;
                } 
            }
            uint price = _getPrice(token);
            uint in_dollars = FullMath.mulDiv(price, amount, WAD);
            uint deductible = FullMath.mulDiv(in_dollars, FEE, WAD);
            
            in_dollars -= deductible;
            pledge.offers[token].credit += in_dollars;
            quid[QUID].offers[token].credit += in_dollars; 

            deductible = FullMath.mulDiv(WAD, deductible, price);
            pledge.offers[token].debit += amount - deductible;
            quid[QUID].offers[token].debit += deductible; 

            require(quid[QUID].offers[WBTC].credit + 
                quid[QUID].offers[WETH].credit < quid[QUID].offers[QUID].debit,
                "cannot insure more than the value of insurance capital on hand");
            
            NFPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    TOKEN_ID, amount0, amount1, 0, 0, block.timestamp)
            );
        }
        TransferHelper.safeTransferFrom(token, 
                    msg.sender, QUID, amount);
    }
    
    // You had not sold the tokens to the contract, but they were at
    // at stake in an offering (an option contract for coverage)...
    function withdraw(address token,
        uint amount) external { _repackNFT();
        Pledge storage pledge = quid[msg.sender];
        amount = _min(pledge.offers[token].debit, amount);
        require(amount > 0, "withdraw"); 
        uint amountToTransfer;
        if (_isDollar(token)) {
            uint old_stake = pledge.offers[QUID].debit;
            // Calculate pro rata in rewards & coverage (debt)
            uint ratio = FullMath.mulDiv(WAD, // % of total debt
                amount, quid[QUID].offers[QUID].debit);
            
            uint btc_price = _getPrice(WBTC);
            uint rewardsBTC = FullMath.mulDiv(ratio, 
                quid[QUID].offers[WBTC].debit, WAD);
            // BTC rewards withdrawable in a separate transaction
            quid[QUID].offers[WBTC].debit -= rewardsBTC;
            pledge.offers[WBTC].debit += rewardsBTC; 
            pledge.offers[WBTC].credit += FullMath.mulDiv(rewardsBTC, 
                                                    btc_price, WAD); 
            uint eth_price = _getPrice(WETH);
            uint rewardsETH = FullMath.mulDiv(ratio,
                quid[QUID].offers[WETH].debit, WAD);
            // ETH rewards withdrawable in a separate transaction
            quid[QUID].offers[WETH].debit -= rewardsETH;
            pledge.offers[WETH].debit += rewardsETH;
            pledge.offers[WETH].credit += FullMath.mulDiv(rewardsETH, 
                                                    eth_price, WAD);
            uint debt = FullMath.mulDiv(ratio,
                quid[QUID].offers[QUID].credit, WAD
            );
            quid[QUID].offers[QUID].credit -= debt;
            if (debt > amount) {
                if (pledge.offers[QUID].debit > debt) {
                    pledge.offers[QUID].debit -= debt;
                    amountToTransfer = _min(amount, 
                        pledge.offers[QUID].debit);
                }
                else {
                    pledge.offers[QUID].debit = 0;
                    amountToTransfer = 0;
                }
            } else {
                pledge.offers[QUID].debit -= amount;
                amountToTransfer = amount - debt;
            }
            _calculateMedian(pledge.offers[QUID].debit, 
                 pledge.vote, old_stake, pledge.vote);  
        } 
        else { // withdraw WETH / WBTC that's being insured by dollars
            uint current_price = _getPrice(token); uint deductible; 
            uint current_value = FullMath.mulDiv(amount, current_price, WAD);
            uint coverable = FullMath.mulDiv(current_price, WAD + 2 * FEE, WAD); 
            // TODO instead of letting this 2x be static, adjust according
            // to the insurance rate (derive a heuristic / ratio for them)
            
            uint average_price = FullMath.mulDiv(WAD, pledge.offers[token].credit, 
                                                      pledge.offers[token].debit);
            if (average_price > coverable) {
                uint coverage = FullMath.mulDiv(amount, average_price, WAD) - current_value;
                // coverage is not the same as if you borrowed at 90 LTV, then 
                // relinquished your collateral, and walked away with the stables
                // here, you get your colleteral back, with an additional coverage
                pledge.offers[QUID].debit += coverage; 
                // only pay if you've received ^^^^^^^
                deductible = FullMath.mulDiv(WAD, FullMath.mulDiv(
                    current_value, FEE, WAD), current_price
                );  
                quid[QUID].offers[token].debit += deductible; // assets
                quid[QUID].offers[QUID].credit += coverage; // liabilities
            }
            pledge.offers[token].debit -= amount;  
            pledge.offers[token].credit -= _min(current_value, 
                                pledge.offers[token].credit);

            quid[QUID].offers[token].credit -= _min(current_value, 
                                quid[QUID].offers[token].credit); 

            // Procedure for unwrapping from Uniswap to send the amount...
            // first determine liquidity needed to call decreaseLiquidity:
            uint160 sqrtPriceX96AtTickLower = TickMath.getSqrtPriceAtTick(LOWER_TICK);
            uint160 sqrtPriceX96AtTickUpper = TickMath.getSqrtPriceAtTick(UPPER_TICK);
            
            amountToTransfer = amount - deductible;
            uint amount0; uint amount1; 
            if (token == WETH) {
                uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtPriceX96AtTickUpper, sqrtPriceX96AtTickLower,
                    amountToTransfer
                );
                (amount0,
                 amount1) = _decreaseAndCollect(liquidity); amount1 -= amountToTransfer;
            }
            else {
                amountToTransfer /= 10 ** 10; // has a precision of 8 digits
                uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtPriceX96AtTickUpper, sqrtPriceX96AtTickLower,
                    amountToTransfer
                );
                (amount0,
                 amount1) = _decreaseAndCollect(liquidity); amount0 -= amountToTransfer;
            }
            NFPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    TOKEN_ID, amount0, amount1, 0, 0, block.timestamp
                )
            );
        }
        if (amountToTransfer > 0) {
            amountToTransfer = _min(amountToTransfer, 
                IERC20(token).balanceOf(QUID));
            TransferHelper.safeTransfer(token,
                msg.sender, amountToTransfer);
        }
    }
    
    // We want to make sure that all of the WETH and / or WBTC
    // provided to this contract is always in range (collecting)
    // Since repackNFT() is relatively costly in terms of gas, 
    // we want to call it rarely...so as a rule of thumb, the  
    // range is roughly 14% total, 7% below TWAP and 7% above 
    // TODO instead of letting this be static, adjust according
    // to the insurance rate (derive a heuristic / ratio for them)
    function repaceNFT() external { _repackNFT(); }
    function _repackNFT() internal {
        uint128 liquidity; int24 twap = _getTWAPtick();  
        if (twap > UPPER_TICK || // TWAP over last 2 days
            twap < LOWER_TICK) { LAST_TWAP_TICK = twap; 
            (,,,,,,, liquidity,,,,) = NFPM.positions(TOKEN_ID);
            _decreaseAndCollect(liquidity); NFPM.burn(TOKEN_ID);
        }
        if (liquidity > 0) {
            (UPPER_TICK, LOWER_TICK) = _adjustTicks(LAST_TWAP_TICK);
            INonfungiblePositionManager.MintParams memory params =
                INonfungiblePositionManager.MintParams({
                    token0: WBTC, token1: WETH, fee: POOL_FEE,
                    tickLower: LOWER_TICK, tickUpper: UPPER_TICK,
                    amount0Desired: IERC20(WBTC).balanceOf(QUID),
                    amount1Desired: IERC20(WETH).balanceOf(QUID),
                    amount0Min: 0, amount1Min: 0, recipient: QUID,
                    deadline: block.timestamp });
            (TOKEN_ID,,,) = NFPM.mint(params);
        } 
        else { // no need to repack NFT, but compound
            (uint amount0, uint amount1) = NFPM.collect( // LP fees
                INonfungiblePositionManager.CollectParams(TOKEN_ID, 
                    QUID, type(uint128).max, type(uint128).max
                )
            ); 
            quid[QUID].offers[WBTC].debit += amount0;
            quid[QUID].offers[WETH].debit += amount1;
            NFPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    TOKEN_ID, amount0, amount1, 0, 0, block.timestamp
                )
            );
        }
    }

    /** Whenever an {IERC721} `tokenId` token is transferred to this contract:
     * @dev Safe transfer `tokenId` token from `from` to `address(this)`, 
     * checking that contract recipient prevent tokens from being forever locked.
     * - `tokenId` token must exist and be owned by `from`
     * - If the caller is not `from`, it must have been allowed 
     *   to move this token by either {approve} or {setApprovalForAll}.
     * - {onERC721Received} is called after a safeTransferFrom...
     * - It must return its Solidity selector to confirm the token transfer.
     *   If any other value is returned or the interface is not implemented
     *   by the recipient, the transfer will be reverted.
     */
    function onERC721Received(address, 
        address from, // previous owner
        uint tokenId, bytes calldata data
    ) external override returns (bytes4) {
        Pledge storage pledge = quid[from];
        (,, address token0, address token1,
         ,,, uint128 liquidity,,,,) = NFPM.positions(tokenId);
        require(token0 == WBTC && token1 == WETH, "wrong pool");
        (uint amount0, 
         uint amount1) = _decreaseAndCollect(liquidity);
        uint price; uint in_dollars; uint deductible;
        if (amount0 > 0) { price = _getPrice(token0);
            amount0 *= 10 ** 10; // WBTC has precision of 8
            in_dollars = FullMath.mulDiv(price, amount0, WAD);
            deductible = FullMath.mulDiv(in_dollars, FEE, WAD);

            pledge.offers[token0].credit += in_dollars - deductible;
            deductible = FullMath.mulDiv(WAD, deductible, price);
            pledge.offers[token0].debit += amount0 - deductible;
            quid[QUID].offers[token0].debit += deductible; 
        }
        if (amount1 > 0) { price = _getPrice(token1);
            in_dollars = FullMath.mulDiv(price, amount1, WAD);
            deductible = FullMath.mulDiv(in_dollars, FEE, WAD);

            pledge.offers[token1].credit += in_dollars - deductible;
            deductible = FullMath.mulDiv(WAD, deductible, price);
            pledge.offers[token1].debit += amount1 - deductible;
            quid[QUID].offers[token1].debit += deductible; 
        }
        NFPM.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams(TOKEN_ID,
                amount0, amount1, 0, 0, block.timestamp
            )
        );
        return this.onERC721Received.selector;
    }

    function vote(uint new_vote) external {
        Pledge storage pledge = quid[msg.sender];
        uint old_vote = pledge.vote;
        pledge.vote = new_vote;
        require(new_vote != old_vote &&
                new_vote < 89, "bad vote");
        uint stake = pledge.offers[QUID].debit;
        _calculateMedian(stake, new_vote, 
                         stake, old_vote);
    }

    /** 
     *  Find value of k in range(0, len(Weights)) such that 
     *  sum(Weights[0:k]) = sum(Weights[k:len(Weights)+1]) = sum(Weights) / 2
     *  If there is no such value of k, there must be a value of k 
     *  in the same range range(0, len(Weights)) such that 
     *  sum(Weights[0:k]) > sum(Weights) / 2
     */ 
    function _calculateMedian(uint new_stake, uint new_vote, 
        uint old_stake, uint old_vote) internal { 
        uint total = quid[QUID].offers[QUID].debit;
        if (old_vote != 0 && old_stake != 0) { 
            WEIGHTS[old_vote] -= old_stake;
            if (old_vote <= MEDIAN) {   
                SUM -= old_stake;
            }
        }
        if (new_stake != 0) {
            if (new_vote <= MEDIAN) {
                SUM += new_stake;
            }		  
            WEIGHTS[new_vote] += new_stake;
        } 
        uint mid_stake = total / 2;
        if (total != 0 && mid_stake != 0) {
            if (MEDIAN > new_vote) {
                while (MEDIAN >= 1 && (
                     (SUM - WEIGHTS[MEDIAN]) >= mid_stake
                )) { SUM -= WEIGHTS[MEDIAN]; MEDIAN -= 1; }
            } else {
                while (SUM < mid_stake) { MEDIAN += 1;
                       SUM += WEIGHTS[MEDIAN];
                }
            } 
            FEE = WAD / (MEDIAN + 11);
        }  
        else { SUM = 0; } 
    }
} 