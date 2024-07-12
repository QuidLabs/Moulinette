
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
  
  const mock = await Mock.deploy();
  const token = await mock.getAddress()
  
  console.log('token deployed at', token)

  console.log('deploy MO');
  let MO = await ethers.getContractFactory("Moulinette");

  const mo = await MO.deploy(token)
  
  console.log(await mo.getAddress())
 
}  
  
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
