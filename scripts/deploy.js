
const { ethers } = require("hardhat");

async function getContract(name, addr) {
  const CONTRACT = await ethers.getContractFactory(name);
  const contract = await CONTRACT.attach(addr);
  return contract;
}

async function main() { // rinkeby:
  try {
    // const currentTimestampInSeconds = Math.round(Date.now() / 1000);
    console.log('deploy mock');
    let Mock = await ethers.getContractFactory("mock");
    
    const mockUSDe = await Mock.deploy();
    const USDeToken = await mockUSDe.getAddress()
    console.log('USDeToken deployed at', USDeToken)

    console.log('deploying MO');
    let MO = await ethers.getContractFactory("Moulinette");

    const mo = await MO.deploy(USDeToken)
    console.log(await mo.getAddress())
  } catch (error) {
     console.error('Error in deployment:', error);
  }
}  
  
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
