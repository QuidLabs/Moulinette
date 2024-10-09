## in my ~~opinion~~ [offer]()

Hedging can be achieved  
by selling futures...QD is  
a non-custodial future $.  
Insurers receive QuiD for  
commitments to re-stake  

USDe over a duration of   
1yr; there are 16 chances  
to `mint`: 8 per year times  
[43 days](https://bit.ly/3q4tShS), "yesterday's price  

is *not* today's," 46% avg ROI  
(before accounting liabilities);  
the receivables are collateral  
for future cash flow from ETH  
getting deployed into UniV3,  

fees retained to capitalise QD...  
as well as sUSDe yield (Morpho  
boosted), **gradated** liquidations  
from longs, and deductibles of

token-holders wishing to  
insure their ETH against  
price drops of over 10%,  
minting QD as insurance  
coverage (not upfront)...  
over time, QD bridges its   

30% gap in capitalisation to  
become fully backed; using  
discount windows allows   
protocol liquidity to grow  
linearly (guarded launch).  

Levering long while buying  
insurance (at the same time)  
protects against liquidations.  
Deductible is initially [357](http://www.niagaramasons.com/Info%20Stuff/The%20Winding%20Staircase.PDF)bp;   
APY is [distributed](https://www.youtube.com/clip/UgkxOMAUJfrx-_ABwnargyEURpPygXEXJ_d9) relative to  

one's ROI versus avg. ROI,    
absorbing liabilties upon  
maturity, when any holder  
may `redeem` 1 QD for $1.  

Voting is incentivised by a  
small QD lotto, distributed  
16x `onERC721Received`.  

There will be a vetting  
process for selecting   
a pool of eligible lotto  
recipients...they must   
all show proof of work  
on our Ricardian talent    
and prediction market.  

### Technical scope (iMO)

As a simplified metaphor, QuiD  
powers an investment **vehicle**:

- electric ignition system (nervous system):  
  `deposit` ETH if nervous about its price,  
  or USDe to maximise your time value of $
- `repackNFT`:  fuel management system;  
   most of the functionality is internal (send  
    wei gas to cylinders, combined with air)
    - controlled by the electrical system, as are its sensors,  
  observing temp. (TWAP) and air density (tick range)
- `redeem` engine has a cooling system for absorbing liabilities
- breaks, clutch, CDP transmission powered by hydraulic `withdraw` 
  - can't withdraw without steering (`vote`), and suspension is related:  
  determines your ride quality (`fold` as suspension === liquidation)

Speaking of cars, another decent  
analogy is [carbide](https://www.instagram.com/p/C_t_orDph5p/) lamps...**fiat** *lux*  
 (let there be light); regarding lime,  
note how [70/30](https://www.instagram.com/p/DAgKU2dxtUq/) here  corresponds  
to the initial capitalisation of QD...  
Earth's surface is also 70% liquid.

### Launch instructions
`npm install` from the root directory, followed by:  
`SHOULD_DEPLOY=true npx hardhat run --network sepolia scripts/deploy.js`  
`cd ./frontend && npm install && npm run dev`