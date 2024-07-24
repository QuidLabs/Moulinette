
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.8; 
// pragma experimental SMTChecker;
import "hardhat/console.sol"; // TODO delete these 2 
import "@openzeppelin/contracts/access/Ownable.sol";

import {TransferHelper} from "./interfaces/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
    IERC721Receiver, ERC20 { // TODO tokenUri for 404 ;)

    address public SUSDE;
    address public JOHN;
    address public QUID;
    
    // TODO comment these out (sepolia testnet)
    address public WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; 
    address public WBTC = 0x29f2D40B0605204364af54EC677bD022dA425d03; 
    
    // TODO uncomment these for mainnet deployment
    // address constant public SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    // address constant public SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    // address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address constant public WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    uint constant public MAX_PER_DAY = 7_777_777 * WAD; // mint cap (QD supply)
    uint constant public DAYS = 40 days; // and nights
    uint public START_PRICE = 50 * PENNY; // till 89
    Pod[DAYS] Offering; uint public START_DATE;
    uint public AVG_ROI; uint public SUM_ROI; 
    // Sum: (QD / Total QD) x (ROI / AVG_ROI)

    // 0.3% fee tier has tick spacing of 60; 
    uint24 constant public POOL_FEE = 3000;  
    uint constant public STACK = BILL * 100;
    uint constant public PENNY = WAD / 100;
    uint constant public BILL = 100 * WAD;
    uint constant public BAG = 100 * STACK;

    uint constant public WAD = 1e18; 
    INonfungiblePositionManager NFPM;
    int24 constant INCREMENT = 60;
    int24 internal LAST_TWAP_TICK;
    // TODO VWMP in milestone 1 ?
    int24 internal UPPER_TICK; 
    int24 internal LOWER_TICK;
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
    uint internal FEE = WAD / 28; 
    uint internal MEDIAN = 17; // index in weights 
    uint internal SUM_FEE; // sum(weights[0..k]) 
    struct Pledge { // sum of sums, MEDIAN (+/- 1)
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
    } // for QD, credit is the contribution to weighted
    // sum of (QD / total QD) times (ROI / avg ROI)...
    
    // TODO remove _susde constructor param (for Sepolia testing only)...
    constructor(address _susde /* address[] round */) ERC20("QU!D", "QD") { 
        
        POOL = IUniswapV3Pool(0xD1787BA366fea7F69212Dfc0a3637ACfEFdf7f25);
        // TODO replace address (below is for mainnet deployment)
        // POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);

        address nfpm = 0x1238536071E1c677A632429e3655c799b22cDA52;
        // TODO replace address (below is for mainnet deployment)
        // address nfpm = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        
        TransferHelper.safeApprove(WETH, nfpm, type(uint256).max);
        TransferHelper.safeApprove(WBTC, nfpm, type(uint256).max);

        TransferHelper.safeTransfer(WETH, QUID, 
            IERC20(WETH).balanceOf(msg.sender));
        
        TransferHelper.safeTransfer(WBTC, QUID,
            IERC20(WBTC).balanceOf(msg.sender));

        SUSDE = _susde; NFPM = INonfungiblePositionManager(nfpm);
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
        
        /*
        _mint(JOHN, BAG); _mint(QUID, 10 * BAG);
        uint cut = balanceOf(QUID) / round.length;
        for (uint i = 0; i < round.length; i++) {
            _transfer(QUID, round[i], cut);
        } 
        */

    }

    modifier isAfter {
        require(block.timestamp > 
            START_DATE + DAYS, "after");
        _;
    }

    function _transferHelper(address from, 
        address to, uint amount) internal {
        uint supply = totalSupply(); // of QD...
        uint balance = balanceOf(from); // before
        amount = _minAmount(from, QUID, amount);
        _transfer(msg.sender, to, amount);
        if (quid[from].offers[QUID].debit > 0) {
            // proportionally transfer debit
            uint ratio = FullMath.mulDiv(WAD, 
                    amount, balanceOf(from));
            uint debit = FullMath.mulDiv(ratio, 
            quid[from].offers[QUID].debit, WAD);
            quid[from].offers[QUID].debit -= debit;
            quid[to].offers[QUID].debit += debit;            
        }   _creditHelper(from); _creditHelper(to);
    }

    function _creditHelper(address who) 
        internal { uint balance = balanceOf(who);
        SUM_ROI -= quid[who].offers[QUID].credit; 
        uint debit = quid[who].offers[QUID].debit;
        uint share = FullMath.mulDiv(WAD, balance, 
                                    totalSupply());
        uint credit = share;
        if (debit > 0) {
            uint roi = FullMath.mulDiv(WAD, 
                    balance - debit, debit);
            
            // now calculate individual ROI over total roi
            roi = FullMath.mulDiv(WAD, roi, AVG_ROI);
            credit = FullMath.mulDiv(roi, share, WAD);
        }   quid[who].offers[QUID].credit = credit;
        
        SUM_ROI += credit;
    }

    /** Quasi-ERC404 functionality (ERC 4A4 :)
     * Override the ERC20 functions to account 
     * for QD balances that are still maturing  
     * TODO implement ERC721 interface 
     */

    // TODO consequences of having an AMM pool with QD 
    function transfer(address recipient, uint256 amount) 
        public override(ERC20) returns (bool) {
        _transferHelper(msg.sender, recipient, amount); return true;      
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20) returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transferHelper(from, to, value); return true;
    }

    
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       HELPER FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/
    
    function _min(uint _a, uint _b) internal pure returns (uint) {
        return (_a < _b) ? _a : _b;
    }

    function _minAmount(address from, address token, uint amount) internal view returns (uint) {
        amount = _min(amount, IERC20(token).balanceOf(from));
        require(amount > 0, "insufficient balance"); return amount;
    }

    function _isDollar(address dollar) internal view returns 
        (bool) { return dollar == SUSDE; /* || dollar == SDAI; */ } // TODO uncomment for mainnet

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

    function _capitalisation(uint liability) internal returns (uint ratio) {
        uint assets = quid[QUID].offers[WBTC].credit + 
            quid[QUID].offers[WETH].credit + quid[QUID].offers[QUID].debit;
        ratio = FullMath.mulDiv(100, assets, totalSupply() + liability); 
    }

    // TODO remove these setters after finish testing, and uncomment in constructor
    function set_price_eth(uint price) external { // set ETH price in USD
        _ETH_PRICE = price;
    }
    function set_price_btc(uint price) external { // set BTC price in USD
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
        // TODO instead of letting this be static, adjust according
        // to the insurance rate (derive a heuristic / ratio for them)
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

    /** 
     *  Find value of k in range(0, len(Weights)) such that 
     *  sum(Weights[0:k]) = sum(Weights[k:len(Weights)+1]) = sum(Weights) / 2
     *  If there is no such value of k, there must be a value of k 
     *  in the same range range(0, len(Weights)) such that 
     *  sum(Weights[0:k]) > sum(Weights) / 2
     */ 
    function _calculateMedian(uint new_stake, uint new_vote, 
        uint old_stake, uint old_vote) internal isAfter { 
        if (old_vote != 17 && old_stake != 0) { 
            WEIGHTS[old_vote] -= old_stake;
            if (old_vote <= MEDIAN) {   
                SUM_FEE -= old_stake;
            }
        }
        if (new_stake != 0) {
            if (new_vote <= MEDIAN) {
                SUM_FEE += new_stake;
            }         
            WEIGHTS[new_vote] += new_stake;
        } 
        uint mid_stake = totalSupply() / 2;
        if (mid_stake != 0) {
            if (MEDIAN > new_vote) {
                while (MEDIAN >= 1 && (
                     (SUM_FEE - WEIGHTS[MEDIAN]) >= mid_stake
                )) { SUM_FEE -= WEIGHTS[MEDIAN]; MEDIAN -= 1; }
            } else {
                while (SUM_FEE < mid_stake) { MEDIAN += 1;
                       SUM_FEE += WEIGHTS[MEDIAN];
                }
            } 
            FEE = WAD / (MEDIAN + 11);
        }  
        else { SUM_FEE = 0; } 
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/ 

     // Two helper functions used by frontend (duplicated code)
    function qd_amt_to_dollar_amt(uint qd_amt, 
        uint block_timestamp) public view returns (uint amount) {
        uint in_days = ((block_timestamp - START_DATE) / 1 days) + 1; 
        amount = (in_days * PENNY + START_PRICE) * qd_amt / WAD;
    }
    function get_total_supply_cap(uint block_timestamp) 
        public view returns (uint total_supply_cap) {
        uint in_days = ((block_timestamp - START_DATE) / 1 days) + 1; 
        total_supply_cap = in_days * MAX_PER_DAY; 
    }

    // make sure anyone calls this at least once 
    function calculate_average_return() external isAfter {
        Pod memory day; uint ratio;
        for (uint i = 0; i < DAYS; i++) {
            day = Offering[i]; 
            ratio += FullMath.mulDiv(WAD, 
            day.credit - day.debit, day.debit);
        }
        AVG_ROI = ratio / DAYS; // sum total of daily ROIs
        // divided by the number of days gives us the avg
    }

    function vote(uint new_vote) external isAfter {
        Pledge storage pledge = quid[msg.sender];
        
        uint old_vote = pledge.vote;
        pledge.vote = new_vote;
        
        require(new_vote != old_vote &&
                new_vote < 89, "bad vote");
        
        uint stake = pledge.offers[QUID].debit;
        
        _calculateMedian(stake, new_vote, 
                         stake, old_vote);
    }

    // redeem the QD balance (minus liabilities):
    // calculates the coverage absorption for each 
    // insurer by first determining their share %
    // and then adjusting based on average ROI.
    // (insurers w/ higher avg. ROI absorb more) 
    function redeem(uint amount, address beneficiary) external isAfter {
        
        Pledge storage pledge = quid[beneficiary];

        if (block.timestamp > START_DATE + 8 * DAYS) {
            require(_capitalisation(0) >= 88, "wait"); 

            // TODO absorb = credit / SUM_ROI x coverage
            // coverage -= absorb

            // pay amount - absorb
            // 20% in crypto
        }
        else {
            if (_capitalisation(0) < 69) { 
                _burn(beneficiary, balanceOf(beneficiary));
                // gets transferred at the end of redeem
                amount = pledge.offers[QUID].debit; 
                pledge.offers[QUID].debit = 0;
                
                // TODO too inefficient to wait for everyone to withdraw ?
                // instead, allow re-using a QD balance in deposit() ??
                if (totalSupply() == 0) {
                    START_DATE = block.timestamp;
                }
            }     
        }
        if (amount > 0) {
            // TODO withdraw USD evenly 
            // 
        }
    }

    function deposit(address beneficiary, uint amount,
             address token) external payable {
        
        Pledge storage pledge = quid[beneficiary];
        if (pledge.vote == 0) { pledge.vote = 17; }
  
        // parameter is interpreted as the amount of QD to be minted
        if (_isDollar(token) && block.timestamp < START_DATE + DAYS) {
            uint in_days = ((block.timestamp - START_DATE) / 1 days); 
            Pod storage offering = Offering[in_days]; in_days += 1;

            uint supply_cap = in_days * MAX_PER_DAY; 
            require(totalSupply() <= supply_cap, "cap"); 
            uint price = in_days * PENNY + START_PRICE;
            
            uint cost = _minAmount(msg.sender, token,
                FullMath.mulDiv(price, amount, WAD)
            );
            amount = FullMath.mulDiv(WAD, cost, price);
            uint fee = FullMath.mulDiv(amount, FEE, WAD);
            uint minted = amount - fee; amount = cost; 
            // fee already distributed in constructor
            _mint(beneficiary, minted); 

            offering.credit += minted; offering.debit += cost;
            quid[QUID].offers[QUID].debit += cost;
            pledge.offers[QUID].debit += cost;  
        } 
        else { uint price = _getPrice(token); // non-stables
            uint amount0; uint amount1; // for Uni LP deposit
            if (token == WBTC) { // has a precision of 8 digits
                amount0 = _minAmount(msg.sender, WBTC, amount);
                amount = amount0 * 10 ** 10; 
            } else {
                amount1 = _minAmount(msg.sender, WETH, amount);
                if (msg.value > 0) { 
                    // WETH becomes available to address(this)
                    IWETH(WETH).deposit{value: msg.value}(); 
                    amount1 += msg.value;
                }
            }
            uint in_dollars = FullMath.mulDiv(price, amount, WAD);
            uint deductible = FullMath.mulDiv(in_dollars, FEE, WAD);
            
            in_dollars -= deductible;
            pledge.offers[token].credit += in_dollars;
            
            // keep track of the total value we're insuring
            quid[QUID].offers[token].credit += in_dollars; 

            deductible = FullMath.mulDiv(WAD, deductible, price);
            pledge.offers[token].debit += amount - deductible;
            quid[QUID].offers[token].debit += deductible; 

            require(quid[QUID].offers[WBTC].credit + 
                quid[QUID].offers[WETH].credit < quid[QUID].offers[QUID].debit,
                "cannot insure more than the value of insurance capital in AUM");
            
            // TODO ratio between amounts needs to match current price
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
    function withdraw(address token, uint amount) external isAfter { 
        _repackNFT(); Pledge storage pledge = quid[msg.sender];
        amount = _min(pledge.offers[token].debit, amount);
        require(amount > 0, "withdraw"); uint amountToTransfer;
        // withdraw WETH / WBTC that's being insured by dollars

        uint current_price = _getPrice(token); uint deductible; 
        uint current_value = FullMath.mulDiv(amount, current_price, WAD);
        uint coverable = FullMath.mulDiv(current_price, WAD + 2 * FEE, WAD); 
        // TODO instead of letting this 2x be static, adjust according
        // to the insurance rate (derive a heuristic / ratio for them)
        
        uint average_price = FullMath.mulDiv(WAD, pledge.offers[token].credit, 
                                                  pledge.offers[token].debit);
        if (average_price > coverable) {
            uint coverage = FullMath.mulDiv(amount, 
                average_price, WAD) - current_value;
           
            if (_capitalisation(coverage) >= 50) { _mint(msg.sender, coverage);
                deductible = FullMath.mulDiv(WAD, FullMath.mulDiv(
                    current_value, FEE, WAD), current_price
                );  
                quid[QUID].offers[token].debit += deductible; // assets
                quid[QUID].offers[QUID].credit += coverage; // liabilities
            }
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
        // TODO ratio between amounts needs to match current price
        NFPM.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams(
                TOKEN_ID, amount0, amount1, 0, 0, block.timestamp
            )
        );
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
    function repackNFT() external { _repackNFT(); }
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
            // TODO ratio between amounts needs to match current price
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
        // TODO ratio between amounts needs to match current price
        NFPM.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams(TOKEN_ID,
                amount0, amount1, 0, 0, block.timestamp
            )
        );
        return this.onERC721Received.selector;
    }
} 