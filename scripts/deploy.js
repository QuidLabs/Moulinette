
const { ethers } = require("hardhat");
const fs = require('fs');
const path = require('path');
require('dotenv').config();
const BN = require('bn.js');

// Path to save the contract addresses
const addressesFilePath = path.join(__dirname, 'deployedAddresses.json'); 

async function getContract(name, addr) {
  const CONTRACT = await ethers.getContractFactory(name);
  const contract = await CONTRACT.attach(addr);
  return contract;
}

// Load the deployed contract addresses from the file
function loadAddresses() {
  if (fs.existsSync(addressesFilePath)) {
    const data = fs.readFileSync(addressesFilePath, 'utf-8');
    return JSON.parse(data);
  }
  return {};
  // TODO write to constant.jsx
}

// Save the deployed contract addresses to the file
function saveAddresses(addresses) {
  fs.writeFileSync(addressesFilePath, JSON.stringify(addresses, null, 2));
}

async function deployContracts() {
    console.log('deploy mocks');
    let mockToken = await ethers.getContractFactory("mockToken");
    let mockVault = await ethers.getContractFactory("mockVault");
    
    const mockUSDe = await mockToken.deploy();
    const USDeToken = await mockUSDe.getAddress()
    console.log('USDe deployed at', USDeToken)

    const mockSUSDe = await mockVault.deploy(USDeToken);
    const sUSDeToken = await mockSUSDe.getAddress()
    console.log('sUSDe deployed at', sUSDeToken)

    console.log('deploying MO');
    const MO = await ethers.getContractFactory("MO")

    const mo = await MO.deploy(USDeToken, sUSDeToken)
    const MOaddress = await mo.getAddress()
    console.log("MO deployed at", MOaddress)

    const QD = await ethers.getContractFactory("Quid")
    const qd = await QD.deploy(MOaddress)
    
    const QDaddress = await qd.getAddress()
    console.log("QD deployed at", QDaddress)
    
    // Save addresses to the file
    const addresses = {
      USDe: USDeToken,
      sUSDe: sUSDeToken,
      Moulinette: MOaddress,
      Quid: QDaddress
    };
    saveAddresses(addresses);
    console.log("setQuid");
    
    var tx = await mo.setQuid(QDaddress)
    await tx.wait()
    
    console.log("set price");    
    tx = await mo.set_price_eth(false, true) 
    console.log("START");
    
    tx = await qd.restart()
    
    return addresses;
}

async function main() { 
  try {
    const currentTimestampInSeconds = Math.round(Date.now() / 1000);
    const shouldDeploy = process.env.SHOULD_DEPLOY !== 'false';
    
    var addresses;
    if (!shouldDeploy) {
      console.log("not deploying")
      addresses = loadAddresses();
      if (!addresses.Quid) {
        throw new Error("can't load addresses");
      }
    }
    else {
      addresses = await deployContracts()
    }
    // Get the signer
    const signers = await ethers.getSigners();
    // Get the signer's address (public key)
    const beneficiary = await signers[0].getAddress();
    // run some tests on our contracts 
    const MO = await getContract("MO", addresses.Moulinette);
    const QD = await getContract("Quid", addresses.Quid);
    const USDE = await getContract("mockToken", addresses.USDe)
    const sUSDE = await getContract("mockVault", addresses.sUSDe)
    
    const provider = ethers.provider;
    const latestBlock = await provider.getBlockNumber();
    console.log('latest block', latestBlock)
    
    const fromBlock = latestBlock - 30;
    const toBlock = latestBlock;
    // Create a filter to get all logs emitted
    var filter = { address: addresses.Moulinette, 
        fromBlock: fromBlock, toBlock: toBlock 
    };
    // Query logs based on the filter
    const logsMO = await provider.getLogs(filter);
    // event SpecificEvent(address quid);
    // MO.on("SpecificEvent", (quidAddress) => {
    //   console.log(`Quid address set to: ${quidAddress}`);
    // });
    // filter = { address: addresses.Quid, 
    //     fromBlock: fromBlock, toBlock: toBlock 
    // };
    // // Query logs based on the filter
    // const logsQD = await provider.getLogs(filter);
    // // TODO test medianiser
    // logsQD.forEach((log) => {
    //     try {
    //         // Decode the log using the contract's interface
    //         const parsedLog = QD.interface.parseLog(log);
    //         // Custom handling of BigInt serialization
    //         const argsWithBigIntConverted = JSON.stringify(parsedLog.args, (key, value) =>
    //             value.toString()
    //         );
    //         console.log(`Event: ${parsedLog.name}`);
    //         console.log(`Args: ${argsWithBigIntConverted}`);
    //     } catch (error) {
    //         console.error("Error decoding log:", error);
    //     }
    //     console.log(`Block Number: ${log.blockNumber}`);
    //     console.log(`Transaction Hash: ${log.transactionHash}`);
    //     console.log('----------------------------------------');
    // });
    var balance;
    var tx; var receipt;
    const bill = '100000000000000000000'
    const rack = '1000000000000000000000'
    if (shouldDeploy) {
      console.log('minting 1k USDE to', beneficiary)
      tx = await USDE.mint()
      receipt = await tx.wait()
      balance = await USDE.balanceOf(beneficiary)
      console.log('balance', balance)
    }
    console.log('approving')
    tx = await USDE.approve(addresses.Moulinette, rack)
    await tx.wait()

    receipt = await USDE.allowance(beneficiary, addresses.Moulinette)
    console.log('allowance', receipt)
    
    try {
      tx = await MO.deposit(beneficiary, bill, addresses.USDe, false)
      receipt = await tx.wait() 
      balance = await QD.balanceOf(beneficiary)
      console.log('balance', balance)
    }
    catch (error) {
      console.error("Error in transaction:", error)
    }
    balance = await sUSDE.balanceOf(addresses.Moulinette)
    console.log('sUSDe balance MO after', balance)
    // TODO approve MO to do transferFrom if doing WETH
    tx = await MO.get_info(beneficiary)
    console.log("get_info():", tx.toString());
  
    const amountInWei = ethers.parseEther("0.001");
    const WETH = '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14';
    var myETH = await provider.getBalance(beneficiary) 
    var before = new BN(myETH.toString())
    console.log('myETH before deposit', before.toString())
    // now that we have some insurance capital (USDe), we can 
    // actually insure some ETH (up to $265 worth)
    const gasLimit = 5_000_000; // High gas limit

    tx = await MO.deposit(beneficiary, 0, WETH, false, {
      value: amountInWei, // Attach Ether to transaction
      gasLimit 
    });
    await tx.wait()
    tx = await MO.get_more_info(addresses.Moulinette)
    console.log("get_more_info() of MO:", tx.toString());
    
    myETH = await provider.getBalance(beneficiary) // TODO print before and after
    console.log('myETH after deposit', myETH)
    myETH =  new BN(myETH.toString())
    var difference = before.sub(myETH)
    console.log('difference', difference.toString())

    tx = await MO.get_more_info(beneficiary)
    console.log("get_more_info():", tx.toString());
   
    // simulate a price drop, so that we can claim 
    tx = await MO.set_price_eth(false, false) 
    await tx.wait()

    console.log("calling fold")
    // simulate a price drop, so that we can claim 
    tx = await MO.fold(beneficiary, amountInWei, false) 
    await tx.wait()

    tx = await MO.get_more_info(beneficiary)
    console.log("get_more_info() of beneficiary:", tx.toString());

    tx = await MO.get_more_info(addresses.Moulinette)
    console.log("get_more_info() of MO:", tx.toString());

    // TODO try fold with sell

    // TODO try fold liquidation
    // fastForward, try again
    
    // TODO final
    // before we redeem
    // we must do a fastForward
    logsMO.forEach((log) => {
        try {
            // Decode the log using the contract's interface
            const parsedLog = MO.interface.parseLog(log);
            // Custom handling of BigInt serialization
            const argsWithBigIntConverted = JSON.stringify(parsedLog.args, (key, value) =>
                value.toString()
            );
            console.log(`Event: ${parsedLog.name}`);
            console.log(`Args: ${argsWithBigIntConverted}`);
        } catch (error) {
            console.error("Error decoding log:", error);
        }
        console.log(`Block Number: ${log.blockNumber}`);
        console.log(`Transaction Hash: ${log.transactionHash}`);
        console.log('----------------------------------------');
    });
  } catch (error) {
     console.error('Error in deployment:', error);
  }
}  

// We recommend this pattern to be able to 
// use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
