const {
    loadFixture, time
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const BN = require('bn.js'); const { expect } = require("chai");

describe("Moulinette contract", function () {

    async function deployFixture() { // plain, and empty deployment
        const currentTime = (Date.now() / 1000).toFixed(0)

        const [owner, addr1, addr2, 
            addr3, addr4, addr5 ] = await ethers.getSigners()
            
        const USDe = await ethers.deployContract("mock")
        await USDe.waitForDeployment()

        const WBTC = await ethers.deployContract("mock")
        await WBTC.waitForDeployment()

        const WETH = await ethers.deployContract("mock")
        await WETH.waitForDeployment()
          
        const MO = await ethers.deployContract("Moulinette", 
            [USDe.target], [WBTC.target], [WETH.target]);
        
        await MO.waitForDeployment()

        const eth_price = '2900000000000000000000'
        const btc_price = '29000000000000000000'
        await MO.connect(owner).set_price_eth(eth_price)
        await MO.connect(owner).set_price_btc(btc_price)
        
        // const contractPrice = await MO.get_price()
        // expect(contractPrice).to.equal(price)

        return { USDe, WBTC, WETH, MO, 
            owner, addr1, addr2, addr3,
            addr4, addr5, currentTime }
    }

    it("Test ", async function () {
        const {  MO, addr1 } = await loadFixture(deployFixture)
        const balanceBefore = await ethers.provider.getBalance(addr1)

    });
        

});