// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.8; 
// pragma experimental SMTChecker;
import "hardhat/console.sol"; // TODO comment out

import "./interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; // TODO delete after finish testing

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "./interfaces/math/TickMath.sol";
import {FullMath} from "./interfaces/math/FullMath.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "./interfaces/TransferHelper.sol";
import {LiquidityAmounts} from "./interfaces/math/LiquidityAmounts.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract Moulinette is IERC721Receiver, Ownable { 
    address public SUSDE; // TODO set in constructor during testing period...
    address constant public SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant public WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    uint public FEE = WAD / 28; // 3.57143% upfront premium for drop insurance
    
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
    error UnsupportedToken();

    uint public TOKEN_ID; // protocol manages one giant NFT deposit 
    IUniswapV3Pool POOL; // the largest liquidity pool on UNIswapV3
    
    uint internal _ETH_PRICE; // TODO comment out when finished testing
    uint internal _BTC_PRICE; // TODO comment out when finished testing
    
    // Chainlink AggregatorV3 Addresses on mainnnet
    address constant public ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant public BTC_PRICE = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    
    uint[90] weights; // sum weights for each FEE
    // index 0 represents largest possibility = 9%
    // index 89 represents the smallest one = 1%
    // derivation of FEE = WAD / (index + 11)...
    event Median(uint oldMedian, uint newMedian);
    struct Medianiser { 
        uint total; // _POINTS > sum of ALL weights... 
        uint sum_w_k; // sum(weights[0..k]) sum of sums
        uint k; // approximate index of median (+/- 1)
    } Medianiser public median; 
    
    struct Pledge { 
        // An offer is a promise or commitment to do
        // or refrain from doing something specific
        // in the future. Our case is bilateral...
        // promise for a promise, aka quid pro quo
        mapping (address => Pod) offers; // stakes
        uint deposit; // insurer's USDe deposit... 
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
    
    constructor(address _usde) Ownable() { // TODO parameter + Ownable only for testing
        POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
        address nfpm = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        TransferHelper.safeApprove(WETH, nfpm, type(uint256).max);
        TransferHelper.safeApprove(WBTC, nfpm, type(uint256).max);
        USDE = _usde; NFPM = INonfungiblePositionManager(nfpm);
    }
    
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       HELPER FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    modifier isLP {
      require(TOKEN_ID > 0, "QD: !LP");
      _;
    }
    
    function _min(uint _a, uint _b) internal pure returns (uint) {
        return (_a < _b) ? _a : _b;
    }
    
    // TODO comment out these setters after finish testing, and uncomment in constructor
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

    function _adjustTicks(int24 input) 
        internal pure returns (int24, int24) {
        int256 delta = int256(WAD / 14); // 7.143%
        int24 increase = int24((int256(input) * (WAD + delta)) / WAD);
        int24 decrease = int24((int256(input) * (WAD - delta)) / WAD);

        // Adjust to the nearest multiple of 60
        int24 adjustedIncrease = _adjustToNearestIncrement(increase);
        int24 adjustedDecrease = _adjustToNearestIncrement(decrease);

        return (adjustedIncrease, adjustedDecrease);
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

    function _decreaseAndCollect(uint128 liquidity) internal returns (uint amount0, uint amount1) {
         NFPM.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(TOKEN_ID, 
                liquidity, 0, 0, block.timestamp
            )
        );
        (amount0, amount1) = NFPM.collect(
            INonfungiblePositionManager.CollectParams(TOKEN_ID, 
                address(this), type(uint128).max, type(uint128).max
            )
        );
    }

     /** 
     * Returns the latest price obtained from the Chainlink ETH:USD aggregator 
     * reference contract...https://docs.chain.link/docs/get-the-latest-price
     */
    function _getPrice(address token) internal view returns (uint price) {
        AggregatorV3Interface chainlink; 
        if (token == WETH) {
            if (_ETH_PRICE > 0) return _ETH_PRICE; // TODO comment out 
            chainlink = AggregatorV3Interface(ETH_PRICE);
        } else if (token == WBTC) {
            if (_BTC_PRICE > 0) return _BTC_PRICE; // TODO comment out
            chainlink = AggregatorV3Interface(BTC_PRICE);
        } else {
            revert UnsupportedToken();
        }
        (, int priceAnswer,, uint timeStamp,) = chainlink.latestRoundData();
        require(timeStamp > 0 && timeStamp <= block.timestamp 
                && priceAnswer >= 0, "QD::price");
        uint8 answerDigits = chainlink.decimals();
        price = uint(priceAnswer);
        // currently the Aggregator returns an 8-digit precision, but we handle the case of future changes
        if (answerDigits > 18) { price /= 10 ** (answerDigits - 18); }
        else if (answerDigits < 18) { price *= 10 ** (18 - answerDigits); } 
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/    

    function deposit(address beneficiary, uint amount,
                     address token) external payable {
        
        amount = _min(amount, IERC20(token).balanceOf(_msgSender()));
        require(amount > 0, "QD::deposit: insufficient balance");
        TransferHelper.safeTransferFrom(token, 
            _msgSender(), address(this), amount);
        
        uint amount0 = token == WBTC ? amount : 0;
        uint amount1 = token == WETH ? amount : 0;
        Pledge storage pledge =  quid[addr];

        if (msg.value > 0) {
            require(token == WETH, "QD::deposit: WETH");
            IWETH(WETH).deposit{value: msg.value}(); // WETH balance available to address(this)
            amount1 += msg.value;
        }   
        else if (token == SUSDE) { pledge.deposit = amount;
            quid[address(this)].offers[token].debit += amount;
        } 
        else {
            _deposit()
            if (TOKEN_ID > 0) 
            {
                NFPM.increaseLiquidity(
                    INonfungiblePositionManager.IncreaseLiquidityParams(TOKEN_ID,
                                                        amount0, amount1, 0, 0, // TODO slippage
                                                    block.timestamp + 1 minutes)
                );
            }
        } 
    }

    function _deposit() {
        uint price = _getPrice(token);     
        
        uint in_dollars = FullMath.mulDiv(price, amount, WAD);
        uint deductible = FullMath.mulDiv(in_dollars, FEE, WAD);
        pledge.offers[token].credit += in_dollars - deductible;

        deductible = FullMath.mulDiv(WAD, deductible, price);
        pledge.offers[token].debit += amount - deductible;
        quid[address(this)].offers[token].debit += deductible; 
    }

    function vote() {

    }
    
    // You had not sold the tokens to the contract, but they were at
    // at stake in an offering (an option contract for coverage)...
    function withdraw(address token,
        uint amount) isLP external {
        uint current_price = _getPrice(token);
        Pledge storage pledge = _fetch(_msgSender(), true);
        amount = _min(pledge.offers[token].debit, amount);
        require(amount > 0, "QD::withdraw: non-existant offer");
        if (token == SUSDE) { amountToTransfer = amount;
            // Calculate pro rata in rewards & coverage...
            
        } else { // withdraw WETH or WBTC that was being insured by USDe
            uint deductible; // only payable if there is an insured event...
            uint current_value = FullMath.mulDiv(amount, current_price, WAD);
            uint coverable = FullMath.mulDiv(current_price, WAD + 3 * FEE, WAD);
            uint average_price = FullMath.mulDiv(WAD, pledge.offers[token].credit, 
                                                    pledge.offers[token].debit);
            if (average_price > coverable) { // more than an 11% drop is an insured event...
                uint coverage = FullMath.mulDiv(amount, average_price, WAD) - current_value;
                // coverage is not the same as if you borrowed at 90 LTV, then 
                // relinquished your collateral, and walked away with the stables
                // here, you get your colleteral back, with an additional coverage
                pledge.offers[SUSDE].debit += coverage; 
                // if you withdraw assets, but don't receive coverage, you don't pay
                deductible = FullMath.mulDiv(FullMath.mulDiv(
                    current_value, FEE, WAD), WAD, current_price
                );  
                quid[address(this)].offers[token].debit += deductible;
                quid[address(this)].offers[SUSDE].credit += coverage;
            }
            pledge.offers[token].debit -= amount;  
            pledge.offers[token].credit -= current_value;  
            // Procedure for unwrapping from Uniswap to send the amount...
            // first determine liquidity needed to call decreaseLiquidity:
            uint160 sqrtPriceX96AtTickLower = TickMath.getSqrtPriceAtTick(LOWER_TICK);
            uint160 sqrtPriceX96AtTickUpper = TickMath.getSqrtPriceAtTick(UPPER_TICK);
            uint amount0; uint amount1; uint amountToTransfer = amount - deductible;
            if (token == WETH) {
                uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtPriceX96AtTickUpper, sqrtPriceX96AtTickLower,
                    amount
                );
                (amount0,
                amount1) = _decreaseAndCollect(liquidity); amount1 -= amountToTransfer;
            } else if (token == WBTC) {
                uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtPriceX96AtTickUpper, sqrtPriceX96AtTickLower,
                    amount
                );
                (amount0,
                amount1) = _decreaseAndCollect(liquidity); amount0 -= amountToTransfer;
            }
            NFPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(TOKEN_ID,
                    amount0, amount1, 0, 0, block.timestamp
                )
            );
        }
        TransferHelper.safeTransfer(token,
                      _msgSender(), amountToTransfer);
    }
    
    // We want to make sure that all of the WETH and / or WBTC
    // provided to this contract is always in range (collecting)
    // Since repackNFT() is relatively costly in terms of gas, 
    // we want to call it rarely...so as a rule of thumb, the  
    // range is roughly 14% total, 7% below TWAP and 7% above 
    function _repackNFT() internal {  uint128 liquidity = 0;
        if (LAST_TWAP_TICK > 0) { int24 twap = _getTWAPtick();  
            if (twap > UPPER_TICK || // TWAP over last 2 days
                twap < LOWER_TICK) { LAST_TWAP_TICK = twap; 
                (,,,,,,, liquidity,,,,) = NFPM.positions(TOKEN_ID);
                _decreaseAndCollect(liquidity); NFPM.burn(TOKEN_ID);
            }
        }   
        else if (TOKEN_ID == 0) { // first time creating the Uniswap V3 NFT...
            uint eth_price = _getPrice(WETH); uint btc_price = _getPrice(WBTC);
            uint eth = FullMath.mulDiv(IERC20(WETH).balanceOf(
                address(this)), eth_price, WAD
            );
            uint btc = FullMath.mulDiv(IERC20(WBTC).balanceOf(
                address(this)), btc_price, WAD
            );
            // two stacks can be used as sandals (sole-bounds),
            // so this is the minimum amount for the soul-bound
            if (eth >= STACK && btc >= STACK) { liquidity = 1; 
                LAST_TWAP_TICK = _getTWAPtick();
            }   
        }   
        if (liquidity > 0) {
            (UPPER_TICK, LOWER_TICK) = _adjustTicks(LAST_TWAP_TICK);
            INonfungiblePositionManager.MintParams memory params =
                INonfungiblePositionManager.MintParams({
                    token0: WBTC, token1: WETH, fee: POOL_FEE,
                    tickLower: LOWER_TICK, tickUpper: UPPER_TICK,
                    amount0Desired: IERC20(WBTC).balanceOf(address(this)),
                    amount1Desired: IERC20(WETH).balanceOf(address(this)),
                    amount0Min: 0, amount1Min: 0, recipient: address(this),
                    deadline: block.timestamp });
            (TOKEN_ID,,,) = NFPM.mint(params);
        } 
        else { // no need to repack NFT, but compound
            (uint amount0, uint amount1) = NFPM.collect(
                INonfungiblePositionManager.CollectParams(TOKEN_ID, 
                    address(this), type(uint128).max, type(uint128).max
                )
            );
            NFPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(TOKEN_ID,
                    amount0, amount1, 0, 0, block.timestamp
                )
            );
        }
    }   function repack() external { _repackNFT(); }

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
        
        (,, address token0, address token1,
         ,,,,,,,) = NFPM.positions(tokenId);

        require(token0 == WBTC && token1 == WETH, "wrong pool");

        // TODO unwrap and collect then call _deposit()


        return this.onERC721Received.selector;
    }
} 