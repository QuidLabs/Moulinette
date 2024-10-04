
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.8; 
import {TransferHelper} from "./interfaces/TransferHelper.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol"; 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 
import {TickMath} from "./interfaces/math/TickMath.sol";
import {FullMath} from "./interfaces/math/FullMath.sol";
import {IV3SwapRouter} from "./interfaces/IV3SwapRouter.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "./interfaces/math/LiquidityAmounts.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
interface IWETH is IERC20 {
    function deposit() 
    external payable;
}   import "./QD.sol";
contract MO is Ownable { 
    address public SUSDE; 
    address public USDE;
    address constant public WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // token0 on mainnet, token1 on sepolia
    address constant public USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // token1 on mainnet, token0 on sepolia
    
    // TODO uncomment these for mainnet deployment, make sure to respect token0 and token1 order in _swap and NFPM.mint
    // address constant public SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    // address constant public USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    // address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address constant public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; 
    uint internal _ETH_PRICE; // TODO delete when finished testing
    uint24 constant POOL_FEE = 500;  uint internal FEE = WAD / 28;
    uint128 constant Q96 = 2**96; uint constant DIME = 10  * WAD;
    uint constant public WAD = 1e18; 
    INonfungiblePositionManager NFPM;
    int24 internal LAST_TWAP_TICK;
    int24 internal UPPER_TICK; 
    int24 internal LOWER_TICK;
    
    uint public ID; uint public MINTED; // QD
    IUniswapV3Pool POOL; IV3SwapRouter ROUTER; 
    struct FoldState { uint delta; uint price;
        uint average_price; uint average_value;
        uint deductible; uint cap; uint minting;
        bool liquidate; uint repay; uint collat; 
    }
    struct SwapState { 
        uint256 positionAmount0;
        uint256 positionAmount1;
        int24 currentTick;
        int24 twapTick;
        uint160 sqrtPriceX96;
        uint160 sqrtPriceX96Lower;
        uint160 sqrtPriceX96Upper;
        uint256 priceX96;
        uint256 amountRatioX96;
        uint256 delta0;
        uint256 delta1;
        bool sell0;
    }   Quid QUID;
    // TODO test...
    // event CreditHelperShare(uint share); 
    // event CreditHelperROI(uint roi);
    // event DebitTransferHelper(uint debit);
    // event WithdrawingETH(uint amount, uint amount0, uint ammount1);
    // TODO test redeem after all others 
    // event USDCinRedeem(uint usdc);
    // event QuidUSDCinRedeemBefore(uint usdc);
    // event QuidUSDCinRedeemAfter(uint usdc);
    // event WeirdRedeem(uint absorb, uint amount);
    // event ThirdInRedeem(uint third);
    // event AbsorbInRedeem(uint absorb);
    event Fold(uint price, uint value, uint cover);
    event FoldDelta(uint delta);
    // event SwapAmountsForLiquidity(uint amount0, uint amount1);

    // TODO remove events (for testing only...)
    // event RepackNFTamountsAfterCollectInBurn(uint amount0, uint amount1);
    // event RepackNFTtwap(int24 twap);
    // event RepackNFTamountsBefore(uint amount0, uint amount1);
    // event RepackNFTamountsAfterCollect(uint amount0, uint amount1);
    // event RepackNFTamountsAfterSwap(uint amount0, uint amount1);
    // event RepackMintingNFT(int24 upper, int24 lower, uint amount0, uint amount1);
    // event DepositDeductibleInDollars(uint deductible);
    // event DepositDeductibleInETH(uint deductible);
    // event DepositInsured(uint insured);
    // event DepositInDollars(uint in_dollars); 
    // TODO ^these seem right, double check later?

    

    function get_info(address who) view
        external returns (uint, uint) {
        Offer memory pledge = pledges[who];
        return (pledge.carry.debit, QUID.balanceOf(who));
        // we never need pledge.carry.credit in the frontend,
        // this is more of an internal tracking variable...
    }
    function get_more_info(address who) view
        external returns (uint, uint, uint, uint) { 
        Offer memory pledge = pledges[who];
        return (pledge.work.debit, pledge.work.credit, 
                pledge.weth.debit, pledge.weth.credit);
        // for address(this), this ^^^^^^^^^^^^^^^^^^
        // is an ETH amount (that we're insuring), and
        // for depositors it's the $ value insured...
    } // continuous payment comes from Uniswap LP fees
     // while a fixed charge (deductible) is payable 
     // upfront (upon deposit), half upon withdrawal
     // deducted as a % FEE from the $ value which
     // is either being deposited or moved in fold
    struct Pod { // same as Pot in QD, Babi renamed 
        uint credit; // sum of (amt x price on offer)
        uint debit; //  quantity of tokens pledged 
    } /* for QD, credit = contribution to weighted
    ...SUM of (QD / total QD) x (ROI / avg ROI) */
    uint public SUM = 1; uint public AVG_ROI = 1; 
    // formal contracts require a specific method of 
    // formation to be enforaceable; one example is
    // negotiable instruments like promissory notes 
    // an Offer is a promise or commitment to do
    // or refrain from doing something specific
    // in the future...our case is bilateral...
    // promise for a promise, aka quid pro quo...
    struct Offer { Pod weth; Pod carry; Pod work;
    uint last; } // timestamp of last fold() event
    // work is like a checking account (credit can
    // be drawn against it) while weth is savings,
    // but it pays interest to the contract itself;
    // together, and only if used in combination,
    // they form an insured revolving credit line;
    // carry is relevant for redemption purposes.
    // fold() holds depositors accountable for 
    // work as well as accountability for weth
    function setQuid(address _quid) external 
        onlyOwner {  QUID = Quid(_quid); 
        // renounceOwnership();
    } 
    modifier onlyQuid {
        require(_msgSender() 
            == address(QUID), 
            "unauthorised"); _;
    }
    function setFee(uint index) 
        public onlyQuid { FEE = 
        WAD / (index + 11); }
    //  recall 3rd Delphic maxim
    mapping (address => Offer) pledges;
    function _min(uint _a, uint _b) 
        internal pure returns (uint) {
        return (_a < _b) ? _a : _b;
    }
    function _minAmount(address from, address token, 
        uint amount) internal view returns (uint) {
        amount = _min(amount, IERC20(token).balanceOf(from));
        require(amount > 0, "zero balance"); 
        if (token != address(QUID)) {
            amount = _min(amount,IERC20(token).allowance(from, address(this)));
            require(amount > 0, "zero allowance"); 
        }
        return amount;
    }
    function setMetrics(uint avg_roi, uint minted) public
        onlyQuid { AVG_ROI = avg_roi; MINTED = minted;
    }
    function _isDollar(address dollar) internal view returns 
        (bool) { return dollar == SUSDE || dollar == USDE; } 
    constructor(address _usde, address _susde) { 
        USDE = _usde; SUSDE = _susde; // TODO remove (for Sepolia only)
                                         // as well as from constructor...
        // TODO replace addresses (with ones below for mainnet deployment)
        // POOL = IUniswapV3Pool(0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640);
        // ROUTER = IV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        // address nfpm = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        POOL = IUniswapV3Pool(0x3289680dD4d6C10bb19b899729cda5eEF58AEfF1);
        ROUTER = IV3SwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
        address nfpm = 0x1238536071E1c677A632429e3655c799b22cDA52; 
        TransferHelper.safeApprove(WETH, nfpm, type(uint256).max);
        TransferHelper.safeApprove(USDC, nfpm, type(uint256).max);
        TransferHelper.safeApprove(USDE, SUSDE, type(uint256).max);
        NFPM = INonfungiblePositionManager(nfpm);
    }
    // present value of the expected cash flows...
    function capitalisation(uint qd, bool burn) 
        public returns (uint ratio) { // ^ extra QD
        uint price = _getPrice(); // $ value of ETH
        // earned from deductibles and Uniswap fees
        uint collateral = FullMath.mulDiv(price,
            pledges[address(this)].work.credit, WAD
        );
        uint deductibles = FullMath.mulDiv(price,
            pledges[address(this)].weth.debit, WAD
        );
        // composition of our insurance capital
        uint assets = collateral + deductibles + 
            pledges[address(this)].work.debit +
            // sUSDe (not including stake yield)
            pledges[address(this)].carry.debit;

        // doesn't account for pledges[address(this)].weth.credit,
        // which are, in a sense, liabilities (that are insured)
        if (burn) {
            ratio = FullMath.mulDiv(100, assets, 
                QUID.totalSupply() - qd); 
        } else {
            ratio = FullMath.mulDiv(100, assets, 
                QUID.totalSupply() + qd); 
        }
    }

    function transferHelper(address from, 
        address to, uint amount) onlyQuid public {
            if (to != address(0)) { // not burn
                // percentage of carry.debit gets 
                // transferred over in proportion 
                // to amount's % of total balance
                // determine % of total balance
                // transferred for ROI pro rata
                uint ratio = FullMath.mulDiv(WAD, 
                    amount, QUID.balanceOf(from));
                // proportionally transfer debit...
                uint debit = FullMath.mulDiv(ratio, 
                pledges[from].carry.debit, WAD);
                // emit DebitTransferHelper(debit);
                pledges[to].carry.debit += debit;  
                pledges[from].carry.debit -= debit;
                // pledge.carry.credit in helper...
                // QD minted in coverage claims or 
                // over-collateralisation does not 
                // transfer over carry.credit b/c
                // carry credit only gets created
                // in the discounted mint windows
                _creditHelper(to); 
            }   _creditHelper(from); 
    }
    function _creditHelper(address who) // QD holder 
        internal { // until batch 1 we have no AVG_ROI
        if (QUID.currentBatch() > 0) { // to work with
            uint credit = pledges[who].carry.credit;
            SUM -= credit; // subtract old share, which
            // may be zero if this is the first time 
            // _creditHelper is called for `who`...
            uint balance = QUID.balanceOf(who);
            uint debit = pledges[who].carry.debit;
            uint share = FullMath.mulDiv(WAD, 
                balance, QUID.totalSupply());
            // emit CreditHelperShare(share);
            credit = share;
            if (debit > 0) { // share is product
                // projected ROI if QD is $1...
                uint roi = FullMath.mulDiv(WAD, 
                    balance - debit, debit);
                // emit CreditHelperROI(roi);
                // calculate individual ROI over total 
                // TODO possibly too many WADs 
                roi = FullMath.mulDiv(WAD, roi, AVG_ROI);
                credit = FullMath.mulDiv(roi, share, WAD);
                // credit is the product (composite) of 
                // two separate share (ratio) quantities 
                // and the sum of products is what we use
                // in determining pro rata in redeem()...
            }   pledges[who].carry.credit = credit;
            SUM += credit; // update sum with new share
        }
    }

    function _collect() internal returns 
        (uint amount0, uint amount1) {
        (amount0, amount1) = NFPM.collect( 
            INonfungiblePositionManager.CollectParams(ID, 
                address(this), type(uint128).max, type(uint128).max
            ) // "collect calls to the tip sayin' how ya changed" 
        ); // 
    }
    function _withdrawAndCollect(uint128 liquidity) 
        internal returns (uint amount0, uint amount1) {
        NFPM.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(
                ID, liquidity, 0, 0, block.timestamp
            )
        );  (amount0, // collect includes proceeds from the decrease... 
             amount1) = _collect(); // above + fees since last collect      
    }

    function _adjustToNearestIncrement(int24 input) 
        internal pure returns (int24 result) {
        int24 remainder = input % 10; // 10 
        // is the tick width for WETH<>USDC
        if (remainder == 0) { result = input;
        } else if (remainder >= 5) { // round up
            result = input + (10 - remainder);
        } else { // round down instead...
            result = input - remainder;
        }
        // just here as sanity check
        if (result > 887220) { // max
            return 887220; 
        } else if (-887220 > result) { 
            return -887220;
        }   return result;
    }
    // adjust to the nearest multiple of our tick width...
    function _adjustTicks(int24 twap) internal pure returns 
        (int24 adjustedIncrease, int24 adjustedDecrease) {
        int256 upper = int256(WAD + (WAD / 14)); 
        int256 lower = int256(WAD - (WAD / 14));
        int24 increase = int24((int256(twap) * upper) / int256(WAD));
        int24 decrease = int24((int256(twap) * lower) / int256(WAD));
        adjustedIncrease = _adjustToNearestIncrement(increase);
        adjustedDecrease = _adjustToNearestIncrement(decrease);
        if (adjustedIncrease == adjustedDecrease) { // edge case
            adjustedIncrease += 10; 
        } 
    }
    function _getTWAP(bool immediate) internal view returns (int24) {
        uint32[] memory when = new uint32[](2); when[0] = immediate ? 60 : 177777; when[1] = 0; 
        try POOL.observe(when) returns (int56[] memory tickCumulatives, uint160[] memory) {
            int24 delta = int24(tickCumulatives[0] - tickCumulatives[1]);  
            int24 result = immediate ? delta / 60 : delta / 177777;
            return result;
        } catch { return int24(0); } 
    }
    function _getPrice() internal returns (uint) {
        if (_ETH_PRICE > 0) return _ETH_PRICE; // TODO
        // (uint160 sqrtPriceX96,,,,,,) = POOL.slot0();
        // price = FullMath.mulDiv(uint256(sqrtPriceX96), 
        //                         uint256(sqrtPriceX96), Q96);
        return QUID.getPrice(); 
    }

    function set_price_eth(bool up,
        bool refresh) external returns (uint) { 
        if (refresh) { _ETH_PRICE = 0;
            _ETH_PRICE = _getPrice();
        }   else {
            uint delta = _ETH_PRICE / 5;
            _ETH_PRICE = up ? _ETH_PRICE + delta 
                              : _ETH_PRICE - delta;
        } // TODO remove this admin testing function
        return _ETH_PRICE;
    } 

    // TODO uncomment when testing redeem
    /*
    function draw_stables(address to, uint amount) 
        public { if (_msgSender() == address(QUID)) {
            to = owner();
        } else {
            require(_msgSender() == address(this), "$");
        }
        if (capitalisation(0) > 100 && amount > 0) { 
            // uint reserveSDAI = IERC4626(SDAI).balanceOf(address(this));
            uint reserveSUSDE = IERC4626(SUSDE).balanceOf(address(this));
            // TODO does ^^^ return shares?
            amount = _min(reserveSUSDE, amount);
            // require(pledges[address(this)].carry.debit 
            //     == reserveSDAI + reserveSUSDE, "don't add up");

            // uint totalBalance = reserveSDAI + reserveSUSDE;
            // uint newTotalBalance = totalBalance - amount;
            // uint targetBalance = newTotalBalance / 2;

            // uint withdrawFromSDAI = reserveSDAI > targetBalance ? 
            //                         reserveSDAI - targetBalance : 0;
            // uint withdrawFromSUSDE = reserveSUSDE > targetBalance ? 
            //                          reserveSUSDE - targetBalance : 0;

            // uint totalWithdrawn = withdrawFromSDAI + withdrawFromSUSDE;
            // if (totalWithdrawn < amount) {
            //     uint remainingAmount = amount - totalWithdrawn;
            //     if (reserveSDAI - withdrawFromSDAI > remainingAmount / 2) {
            //         withdrawFromSDAI += remainingAmount / 2;
            //         remainingAmount -= remainingAmount / 2;
            //     } else {
            //         withdrawFromSDAI += reserveSDAI - withdrawFromSDAI;
            //         remainingAmount -= reserveSDAI - withdrawFromSDAI;
            //     }
            //     if (reserveSUSDE - withdrawFromSUSDE > remainingAmount) {
            //         withdrawFromSUSDE += remainingAmount;
            //     } else {
            //         withdrawFromSUSDE += reserveSUSDE - withdrawFromSUSDE;
            //     }
            // }
            // IERC4626(SDAI).redeem(withdrawFromSDAI, to, address(this));
            IERC4626(SUSDE).redeem(amount, to, address(this));
            // redeem takes amount of sUSDe you want to turn into USDe. 
            // withdraw specifies amount of USDe you wish to withdraw, 
            // and will pull the required amount of sUSDe from sender. 
            // TODO steps to withdraw from morpho (mainnet)
        }
    }
    */
    function _swap(uint amount0, uint amount1) internal returns (uint, uint) {
        SwapState memory state; state.twapTick = _getTWAP(true);
        (state.sqrtPriceX96, state.currentTick,,,,,) = POOL.slot0();
        // 100 = 1% max tick difference // TODO attack vector? causing revert
        // (protection from price manipulation attacks / sandwich attacks)
        require(state.twapTick > 0 /* && (state.twapTick > state.currentTick 
        && ((state.twapTick - state.currentTick) < 100)) || (state.twapTick <= state.currentTick  
        && ((state.currentTick  - state.twapTick) < 100)) */, "price delta");

        state.priceX96 = FullMath.mulDiv(uint256(state.sqrtPriceX96), 
                                         uint256(state.sqrtPriceX96), Q96);
        
        state.sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(LOWER_TICK);
        state.sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(UPPER_TICK);

        (state.positionAmount0, 
         state.positionAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                                                    state.sqrtPriceX96, 
                                                    state.sqrtPriceX96Lower, 
                                                    state.sqrtPriceX96Upper, Q96);
        // emit SwapAmountsForLiquidity(state.positionAmount0, state.positionAmount1);
        // how much of the position needs to
        // be converted to the other token:
        if (state.positionAmount0 == 0) { 
            state.sell0 = true; state.delta0 = amount0;
        } else if (state.positionAmount1 == 0) { state.sell0 = false;
            state.delta0 = FullMath.mulDiv(Q96, amount1, state.priceX96);
        } else {
            state.amountRatioX96 = FullMath.mulDiv(Q96, state.positionAmount0, state.positionAmount1);
            uint denominator = FullMath.mulDiv(state.amountRatioX96, state.priceX96, Q96) + Q96;
            uint numerator; state.sell0 = (state.amountRatioX96 * amount1 < amount0 * Q96); 
            if (state.sell0) {
                numerator = (amount0 * Q96) - FullMath.mulDiv(state.amountRatioX96, amount1, 1);
            } else {    
                numerator = FullMath.mulDiv(state.amountRatioX96, amount1, 1) - (amount0 * Q96);
            }
            state.delta0 = numerator / denominator;
        }
        if (state.delta0 > 0) {
            if (state.sell0) { 
                TransferHelper.safeApprove(USDC, 
                address(ROUTER), state.delta0);
                uint256 amount = ROUTER.exactInput(
                    IV3SwapRouter.ExactInputParams(abi.encodePacked(
                        USDC, POOL_FEE, WETH), address(this), state.delta0, 0)
                ); 
                TransferHelper.safeApprove(USDC, address(ROUTER), 0);
                // IERC20(WETH).approve(address(ROUTER), 0);
                amount0 = amount0 - state.delta0;
                amount1 = amount1 + amount;
            } 
            else { // sell1
                state.delta1 = FullMath.mulDiv(state.delta0, state.priceX96, Q96);
                if (state.delta1 > 0) { // prevent possible rounding to 0 issue
                    TransferHelper.safeApprove(WETH, 
                    address(ROUTER), state.delta1);
                    uint256 amount = ROUTER.exactInput(
                        IV3SwapRouter.ExactInputParams(abi.encodePacked(
                            WETH, POOL_FEE, USDC), address(this), state.delta1, 0)
                    ); 
                    TransferHelper.safeApprove(WETH, address(ROUTER), 0);
                    // IERC20(USDC).approve(address(ROUTER), 0);
                    amount0 = amount0 + amount;
                    amount1 = amount1 - state.delta1;
                }
            }
        }
        return (amount0, amount1); 
    }

    // call in QD's worth (redeem sans liabilities)
    // calculates the coverage absorption for each 
    // insurer by first determining their share %
    // and then adjusting based on average ROI...
    // (insurers w/ higher avg. ROI absorb more) 
    // "you never count your money while you're
    // sittin' at the table...there'll be time 
    // enough for countin' when dealin's done."
    function redeem(uint amount) 
        external returns (uint absorb) {
        uint max = QUID.balanceOf(_msgSender());
        amount = _min(max, QUID.matureBalanceOf(_msgSender())); 
        uint share = FullMath.mulDiv(WAD, amount, max); // %
        // of overall balance, but not more than mature QD:
        // share helps determine pledge's share of coverage
        uint coverage = pledges[address(this)].carry.credit; 
        Offer storage pledge = pledges[_msgSender()];     

        // maximum that pledge would absorb
        // if they redeemed all their QD...
        absorb = FullMath.mulDiv(coverage, 
            FullMath.mulDiv(WAD, 
            pledge.carry.credit, SUM), WAD  
        );  // if not all the mature QD is
        if (WAD > share) { // being redeemed
            absorb = FullMath.mulDiv(absorb, share, WAD);
        }   
        // emit AbsorbInRedeem(absorb);
        QUID.burn(_msgSender(), amount); 

        // convert amount from QD to value in dollars
        amount = amount * capitalisation(amount, true) / 100;

        // should almost always
        // evaluate to true...
        if (amount > absorb) {
            amount -= absorb; 
            // remainder is the 
            // $ value released 
            // after taking into 
            // account total liabilities 
            uint third = 3 * amount / 10; 
            // emit ThirdInRedeem(third);
            // emit QuidUSDCinRedeemBefore(pledges[address(this)].work.debit);
            // draw_stables(_msgSender(), amount - third); // TODO uncomment !
            // convert 1/3 of amount into USDC precision...
            uint usdc = FullMath.mulDiv(1000000, third, WAD);
            // emit USDCinRedeem(usdc);
            if (third > pledges[address(this)].work.debit) {
                uint delta = third - pledges[address(this)].work.debit;
                pledges[address(this)].work.debit = 0; // releasing 
                // protocol assets in order to redeem amount - absorb
                pledges[address(this)].weth.debit -= FullMath.mulDiv(
                    WAD, delta, _getPrice()
                );
            } else { pledges[address(this)].work.debit -= third; }
            uint160 sqrtPriceX96atLowerTick = TickMath.getSqrtPriceAtTick(LOWER_TICK);
            uint160 sqrtPriceX96atUpperTick = TickMath.getSqrtPriceAtTick(UPPER_TICK);
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                sqrtPriceX96atUpperTick, sqrtPriceX96atLowerTick, usdc
            );
            (uint amount0, uint amount1) = _withdrawAndCollect(liquidity);
            if (amount0 >= usdc) {
                // address(this) balance should be >= usdc
                TransferHelper.safeTransfer(USDC, 
                        _msgSender(), usdc);
                           amount0 -= usdc;
            }   _repackNFT(amount0, amount1);
        } 
        // else {
        //     emit WeirdRedeem(absorb, amount);
        // }
        // else the entire amount being redeemed
        // is consumed by absorbing protocol debt
        pledges[address(this)].carry.credit -= absorb;
        // regardless, we have to subtract the ^^^^^^
    }

    // quid says if amount is QD...
    // ETH can only be withdrawn from
    // pledge.work.debit; if ETH was 
    // deposited into pledge.weth.debit,
    // first call fold() before withdraw()
    function withdraw(uint amount, 
        bool quid) external payable {
        uint amount0; uint amount1; 
        uint price = _getPrice();
        Offer memory pledge = pledges[_msgSender()];
        if (quid) { // amount is in units of QD
            require(amount >= DIME, "too small");
            if (msg.value > 0) { amount0 = msg.value;
                IWETH(WETH).deposit{value: amount0}();
                pledge.work.debit += amount0;
                pledges[address(this)].work.credit += amount0;
            }     
            uint debit = FullMath.mulDiv(price, 
                         pledge.work.debit, WAD
            ); uint buffered = debit - debit / 5;
            uint credit = FullMath.mulDiv(
                capitalisation(amount, false), amount, 100
            );  require(buffered >= pledge.work.credit, "CR");
            credit = _min(credit, buffered - pledge.work.credit);
            amount = (100 + (100 - capitalisation(0, false))) * credit / 100;
            QUID.mint(amount, _msgSender(), address(QUID));
            pledge.work.credit += credit;
        } else { uint withdrawable; // ETH
            if (pledge.work.credit > 0) {
                uint debit = FullMath.mulDiv(price, 
                    pledge.work.debit, WAD
                ); uint buffered = debit - debit / 5;
                require(buffered >= pledge.work.credit, "CR");
                withdrawable = FullMath.mulDiv(WAD, 
                buffered - pledge.work.credit, price); 
            }
            uint transfer = amount;
            if (transfer > withdrawable) {
                withdrawable = FullMath.mulDiv(
                    WAD, pledge.work.credit, price 
                );
                pledges[address(this)].weth.debit += // sell ETH
                withdrawable; // to clear work.credit of pledge
                // "we sip the [weth], warm wisps of [work]"
                amount = _min(pledge.work.debit, withdrawable);
                transfer = amount; pledge.work.debit -= transfer; 
                pledge.work.credit -= FullMath.mulDiv(amount, price, WAD); 
            }   pledges[address(this)].work.credit -= transfer;
            // Procedure for unwrapping from Uniswap to transfer ETH:
            // determine liquidity needed to call decreaseLiquidity...
            uint160 sqrtPriceX96atLowerTick = TickMath.getSqrtPriceAtTick(LOWER_TICK);
            uint160 sqrtPriceX96atUpperTick = TickMath.getSqrtPriceAtTick(UPPER_TICK);
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
                sqrtPriceX96atUpperTick, sqrtPriceX96atLowerTick, transfer
            );
            (amount0,
             amount1) = _withdrawAndCollect(liquidity);
            // emit WithdrawingETH(transfer, amount0, amount1);
            if (amount1 >= transfer) { 
                // address(this) balance should be >= amount1
                TransferHelper.safeTransfer(
                    WETH, _msgSender(), transfer
                );
                             amount1 -= transfer;
            }     _repackNFT(amount0, amount1);
        }   pledges[_msgSender()] = pledge;
    }

    // allowing deposits on behalf of a benecifiary
    // enables similar functionality to suretyship
    function deposit(address beneficiary, uint amount,
        address token, bool long) external payable { 
        Offer memory pledge = pledges[beneficiary];
        if (_isDollar(token)) { // amount interpreted as QD to mint
            uint cost = QUID.mint(amount, beneficiary, token);
            cost = _minAmount(beneficiary, token, cost);
            TransferHelper.safeTransferFrom(
                token, beneficiary, address(this), cost
            );  pledges[address(this)].carry.debit += cost;
            // ^needed for tracking total capitalisation
            pledge.carry.debit += cost; // contingent
            // variable for ROI as well as redemption,
            // carry.credit gets reset in _creditHelper
            pledges[beneficiary] = pledge; // save changes
            _creditHelper(beneficiary); // because we read
            // from pledge ^^^^^^^^^^ in _creditHelper
            if (token == USDE) { // to accrue rewards
                IERC4626(SUSDE).deposit( // before...t 
                    cost, address(this) // move to 
                );
                // TODO stake into morpho (mainnet)
            } 
            // else if (token == DAI) { // TODO
                // IERC4626(SDAI).deposit( // before 
                //     cost, address(this) // move to 
                // ); // advanced integration of USDS 
                // Aave USDS market + USDS Savings Rate 
            // }
        } 
        else if (token == address(QUID)) {
            amount = _minAmount(_msgSender(),
                       token, amount);
            amount = _min((capitalisation(0, 
                false) / 100) * amount, 
                pledge.work.credit
            );  pledge.work.credit -= amount; 
            QUID.burn(_msgSender(), amount);
            // pay debt borrowed against collat
        }    
        else { 
            if (amount > 0) { amount = _minAmount(
                _msgSender(), WETH, amount); 
                TransferHelper.safeTransferFrom(WETH, 
                _msgSender(), address(this), amount);
            } else { require(msg.value > 0, "no ETH");
                 amount += msg.value; }
            if (msg.value > 0) { IWETH(WETH).deposit{
                                 value: msg.value}(); }   
            if (long) { pledge.work.debit += amount; } // collat
            else { uint price = _getPrice(); // insuring the $ value
                uint in_dollars = FullMath.mulDiv(price, amount, WAD);
                // emit DepositInDollars(in_dollars);
                uint deductible = FullMath.mulDiv(in_dollars, FEE, WAD);
                // emit DepositDeductibleInDollars(deductible);
                in_dollars -= deductible; // deductive in units of $
                // change deductible to be in units of ETH instead...
                deductible = FullMath.mulDiv(WAD, deductible, price);
                // emit DepositDeductibleInETH(deductible);
                uint insured = amount - deductible; // in ETH
                // emit DepositInsured(insured);
                pledge.weth.debit += insured; // withdrawable
                // by folding balance into pledge.work.debit...
                pledges[address(this)].weth.debit += deductible;
                pledges[address(this)].weth.credit += insured;
                pledge.weth.credit += in_dollars;
                in_dollars = FullMath.mulDiv(price, 
                    pledges[address(this)].weth.credit, WAD
                );
                require(pledges[address(this)].carry.debit >
                    in_dollars, "insuring too much ether"
                ); 
                pledges[beneficiary] = pledge; // save changes
            } _repackNFT(0, amount); // 0 represents USDC...
        } 
    }
    
    // "Entropy" comes from a Greek word for transformation; 
    // Clausius interpreted as the magnitude of the degree 
    // to which molecules are separated from each other... 
    // "so close no matter how far, rage be in it like you 
    // couldn’t believe...or [work] like one could scarcely 
    // imagine...if one isn’t satisfied, indulge the latter,
    // ‘neath the halo of a street-lamp, I turn my [straddle]
    // to the cold and damp...know when to hold 'em...know 
    // when to..." 
     function fold(address beneficiary, // amount is...
        uint amount, bool sell) external { //  in ETH
        // sell may be enabled as a setting in frontend...
        FoldState memory state; state.price = _getPrice();
        // call in collateral that's insured, or liquidate;
        // if there is an insured event, QD may be minted,
        // or simply clear the debt of a long position...
        // "we can serve our [wick nest] or we can serve
        // our purpose, but not both" ~ Mother Cabrini
        Offer memory pledge = pledges[beneficiary];
        amount = _min(amount, pledge.weth.debit);
        require(amount > 0, "too low of an amount");
        state.cap = capitalisation(0, false);
        if (pledge.work.credit > 0) {
            state.collat = FullMath.mulDiv(
                state.price, pledge.work.debit, WAD
            );
            // "lookin' too hot; simmer down, or soon,"
            if (pledge.work.credit > state.collat) {
                state.repay = pledge.work.credit - state.collat; 
                state.repay += state.collat / 10; 
                state.liquidate = true; // try to
            } else { 
                state.delta = state.collat - pledge.work.credit;
                if (state.collat / 10 > state.delta) { 
                    state.repay = (state.collat / 10) - state.delta;
                }
            }   
        }
        if (amount > 0) { // claim ETH amount that's been insured...
            state.collat = FullMath.mulDiv(amount, state.price, WAD);
            state.average_price = FullMath.mulDiv(WAD, 
                pledge.weth.credit, pledge.weth.debit
            ); // ^^^^^^^^^^^^^^^^ must be in dollars
            state.average_value = FullMath.mulDiv( 
                amount, state.average_price, WAD
            );  
            // emit Fold(state.average_price, state.average_value, FullMath.mulDiv(110, state.price, 100));
            // if price drop > 10% (average_value > 10% more than current value) 
            if (state.average_price >= FullMath.mulDiv(110, state.price, 100)) { 
                state.delta = state.average_value - state.collat;
                emit FoldDelta(state.delta);
                if (!sell) { state.minting = state.delta;  
                    state.deductible = FullMath.mulDiv(WAD, 
                        FullMath.mulDiv(state.collat, FEE, WAD), 
                        state.price
                    ); 
                }
                else { state.deductible = amount;  
                    state.minting = state.average_value - 
                        FullMath.mulDiv( // deducted
                            state.average_value, FEE, WAD
                        );
                }
                if (state.repay > 0) { // capitalise into credit
                    state.cap = _min(state.minting, state.repay);
                    pledge.work.credit -= state.cap; 
                    state.minting -= state.cap; 
                    state.repay -= state.cap; 
                }
                state.cap = capitalisation(state.delta, false); 
                if (state.minting > 0 && state.cap > 57) { 
                    QUID.mint(
                        (100 + (100 - state.cap)) * state.minting 
                        / 100, beneficiary, address(QUID)
                    );
                    pledges[address(this)].carry.credit += state.delta; 
                } 
                pledges[address(this)].weth.credit -= amount;
                // amount is no longer insured by the protocol
                pledge.weth.debit -= amount; // deduct amount
                pledge.weth.credit -= state.average_value; 
                
                pledge.work.debit += amount - state.deductible;
                // this can effectively be zero if sell is true...
                pledges[address(this)].weth.debit += state.deductible; // ETH
                
                state.collat = FullMath.mulDiv(pledge.work.debit, state.price, WAD);
                if (state.collat > pledge.work.credit) { state.liquidate = false; }
            } 
        } // "things have gotten closer to the sun, and I've done 
        // things in small doses, so don't think that I'm pushing 
        // you away...when you're the one that I've kept closest..."
        if (state.liquidate && (QUID.blocktimestamp() - pledge.last > 1 hours)) {  
            amount = _min((100 + (100 - state.cap)) * state.repay / 100, 
            QUID.balanceOf(beneficiary)); QUID.burn(beneficiary, amount);
            // subtract the $ value of QD burned from pledge's work credit...
            pledge.work.credit -= amount * state.cap / 100; 
            // "lightnin' strikes and the court lights...
            if (pledge.work.credit > state.collat) { // get dim"
                if (pledge.work.credit > DIME) { // TODO make pledge.last a Pod, 
                    // so we can track the last amount pledge credit deducted,
                    // making it work like Euler's disk (decreasing amplitude,
                    // while increasing the frequency of the deductions)
                    amount = pledge.work.debit / 727;
                    // there are ~727 hours per month
                    pledge.work.debit -= amount; 
                    pledges[address(this)].weth.debit += amount;
                    amount = FullMath.mulDiv(state.price, 
                                              amount, WAD);
                    // "It's like inch by inch, step by step,
                    // I'm closin' in on your position and 
                    // [eviction] is my mission..."
                    pledge.work.credit -= amount; 
                    pledge.last = QUID.blocktimestamp();
                } else { // "it don't get no better than this, you catch my [dust]"
                    // otherwise we run into a vacuum leak (infinite contraction)
                    pledges[address(this)].weth.debit += pledge.work.debit;
                    pledges[address(this)].carry.credit += pledge.work.credit;
                    // debt surplus absorbed ^^^^^^^^^ as if it were cov    erage
                    pledge.work.credit = 0; pledge.work.debit = 0; // reset
                }   
            }
        }   pledges[beneficiary] = pledge;
    }
    
    // "to improve is to change, to perfect is to change often,"
    // we want to make sure that all of the WETH deposited to 
    // this contract is always in range (collecting), since 
    // repackNFT() is relatively costly in terms of gas, we 
    // want to call it rarely...so as a rule of thumb, the  
    // range is roughly 14% total, 7% below and above TWAP;
    // this number was inspired by automotive science: how
    // voltage regulators watch the currents and control the 
    // relay (which turns on & off the alternator, if below 
    // or above 14 volts, respectively, re-charging battery)
    function _repackNFT(uint amount0, uint amount1) internal {
        uint128 liquidity; int24 twap = _getTWAP(false); 
        // emit RepackNFTtwap(twap); 
        // emit RepackNFTamountsBefore(amount0, amount1);
        if (LAST_TWAP_TICK != 0) { // not first _repack call
            if (twap > UPPER_TICK || twap < LOWER_TICK) {
                (,,,,,,, liquidity,,,,) = NFPM.positions(ID);
                (uint collected0, 
                 uint collected1) = _withdrawAndCollect(liquidity); 
                amount0 += collected0; amount1 += collected1;
                // emit RepackNFTamountsAfterCollectInBurn(amount0, amount1);
                pledges[address(this)].weth.debit += collected1;
                pledges[address(this)].work.debit += collected0;
                NFPM.burn(ID); // this ^^^^^^^^^^ is USDC fees
            }
        }
        LAST_TWAP_TICK = twap; if (liquidity > 0 || ID == 0) {
        (UPPER_TICK, LOWER_TICK) = _adjustTicks(LAST_TWAP_TICK);
        (amount0, amount1) = _swap(amount0, amount1);
        
        // emit RepackMintingNFT(
        //     UPPER_TICK, LOWER_TICK, amount0, amount1
        // );
        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: USDC, token1: WETH, fee: POOL_FEE,
                tickLower: LOWER_TICK, tickUpper: UPPER_TICK,
                amount0Desired: amount0, amount1Desired: amount1,
                amount0Min: 0, amount1Min: 0, recipient: address(this),
                deadline: block.timestamp + 1 minutes }); (ID,,,) = NFPM.mint(params);
        } // else no need to repack NFT, but need to collect idle LP fees 
        else { // at this stage transactions, fees are protocol property
            (uint collected0, uint collected1) = _collect(); 
            amount0 += collected0; amount1 += collected1;
            // emit RepackNFTamountsAfterCollect(amount0, amount1);
            pledges[address(this)].weth.debit += collected1;
            pledges[address(this)].work.debit += collected0;
            // (amount0, 
            //  amount1) = _swap(amount0, amount1);
            // emit RepackNFTamountsAfterSwap(amount0, amount1);
            NFPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    ID, amount0, amount1, 0, 0, block.timestamp
                )
            );
        }
    } function repackNFT() external { _repackNFT(0,0); }
}
