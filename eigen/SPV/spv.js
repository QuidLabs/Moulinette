const os = require('os');
const fs = require('fs');
const path = require('path');

const NETWORK = "regtest" 

const bcoin = require("bcoin").set(NETWORK)

const Network = bcoin.Network;
const NetAddress = bcoin.net.NetAddress;
const network = Network.get().toString();
const logPrefix = path.join(__dirname, (network === "main") ? "hello" : "hello-regtest");

async function delay(ms) {
    return new Promise(resolve => {
        setTimeout(resolve, ms);
    });
}

const spvNode = new bcoin.SPVNode({
    network: network,
    httpPort: 48449,
    prefix: path.join(logPrefix, 'SPV'),
    memory: false,
    logFile: true,
    logConsole: false,
    logLevel: 'spam',
    maxOutbound: 1,
});


const txs = require("./txs.json");

const multisigAddress = ''; // TODO

function saveTxs() {
    fs.writeFile("./txs.json", JSON.stringify(txs, null, 4), function (_) { });
}

(async () => {
    console.log("Ensurujem");
    await spvNode.ensure();
    await spvNode.open();
    await spvNode.connect();
    spvNode.startSync();

    const address = bcoin.Address.fromString(multisigAddress, spvNode.network);
    spvNode.pool.watchAddress(address);
   
    spvNode.on('block', async (block) => {
       
        for (const tx in txs) {
            txs[tx].confirmations++;
        }
        const btxs = JSON.parse(JSON.stringify(block.txs));
        for (const tx of btxs) {
            console.log(tx);
            const txHash = tx.hash;
            const payerPublicKey = tx.inputs[0].address;
            if (payerPublicKey == multisigAddress) {
                continue;
            }
            const outputs = tx.outputs
            let amount = 0;
            for (const output of outputs) {
                if (output.address == multisigAddress) {
                    amount += parseFloat(output.value)
                }
            }
            if (amount > 0) {
                const transaction = {
                    hash: txHash,
                    payer: payerPublicKey,
                    amount,
                    confirmations: 1
                }

                txs[transaction.hash] = transaction;
            }
        }

        saveTxs();
    });
    await delay(800);

    const addr = new NetAddress({
        host: '127.0.0.1',
        port: 18444
    });

    const peer = spvNode.pool.createOutbound(addr);
    spvNode.pool.peers.add(peer);
})()

module.exports = { txs, saveTxs }