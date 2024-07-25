// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.8; 

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mock is ERC20 { 
    
    uint constant public WAD = 1e18; 

    constructor() ERC20("Ethena", "sUSDe") { }

    function mint() external {
        _mint(msg.sender, WAD * 10000);
    }

}