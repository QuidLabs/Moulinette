const {
    loadFixture, time
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const BN = require('bn.js'); const { expect } = require("chai");

describe("Moulinette contract", function () {

    async function deployFixture() {
        const currentTime = (Date.now() / 1000).toFixed(0)

        const [owner, addr1, addr2, 
            addr3, addr4, addr5 ] = await ethers.getSigners()
            
        const USDe = await ethers.deployContract("mockToken")
        await USDe.waitForDeployment()

        const SUSDe = await ethers.deployContract("mockVault")
        await DAI.waitForDeployment()
          
        const MO = await ethers.deployContract("MO", 
            [USDe.target, SUSDe.target]);
        
        await MO.waitForDeployment()

        const QD = await ethers.deployContract("Quid", [MO.target]);
        await QD.waitForDeployment()
        
        await MO.connect(owner).setQuid(QD.target)   
        const WETH = MO.connect(owner).WETH() 
        const USDC = MO.connect(owner).USDC()     
        
        return { USDe, DAI, USDC, WETH, MO, 
            QD, owner, addr1, addr2, addr3,
            addr4, addr5, currentTime }
    }
    
    it("Test ", async function () {
        const {  MO,  QD, addr1 } = await loadFixture(deployFixture)
        // const balanceBefore = await ethers.provider.getBalance(addr1)
        // ^^ this is ETH
    });
});