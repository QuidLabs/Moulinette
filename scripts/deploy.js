
const { ethers } = require("hardhat");

async function getContract(name, addr) {
  const CONTRACT = await ethers.getContractFactory(name);
  const contract = await CONTRACT.attach(addr);
  return contract;
}

async function main() { // rinkeby:
  // const currentTimestampInSeconds = Math.round(Date.now() / 1000);
  console.log('deploy mock');
  let Mock = await ethers.getContractFactory("mock");
  
  const mockUSDe = await Mock.deploy();
  const USDeToken = await mockUSDe.getAddress()
  console.log('USDeToken deployed at', USDeToken)

  const mockWBTC = await Mock.deploy();
  const WBTCtoken = await mockWBTC.getAddress()
  console.log('WBTCtoken deployed at', WBTCtoken)
  
  const mockWETH = await Mock.deploy();
  const WETHtoken = await mockWETH.getAddress()
  console.log('WETHtoken deployed at', WETHtoken)
  

  console.log('deploying MO');
  let MO = await ethers.getContractFactory("Moulinette");

  const mo = await MO.deploy(USDeToken, WBTCtoken, WETHtoken)
  
  console.log(await mo.getAddress())
 
}  
  
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
