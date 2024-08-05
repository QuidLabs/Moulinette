const bitcoin = require('bitcoinjs-lib');
const bitcoinRPC = require('bitcoin-rpc-promise');

const rpcConfig = {
    protocol: 'http',
    user: 'username',
    pass: 'password',
    host: 'localhost',
    port: 18443,
};

const multisigScriptHex = '';
const multisigAddress = '';
const receivingAddress = '';
const privateKeys = [
    '',
    '',
    ''
];

(async function () {
    try {
        const client = new bitcoinRPC.Client(rpcConfig);

        // Step 1: Get UTXOs
        const utxos = await client.listUnspent(1, 9999999, [multisigAddress]);
        
        // Step 2: Create transaction builder
        const txb = new bitcoin.TransactionBuilder(bitcoin.networks.regtest);

        // Step 3: Add inputs from UTXOs
        for (const utxo of utxos) {
            txb.addInput(utxo.txid, utxo.vout);
        }

        // Step 4: Add output for destination address
        txb.addOutput(receivingAddress, 100000); // Amount in satoshis

        // Step 5: Sign transaction with private keys
        for (let i = 0; i < privateKeys.length; i++) {
            const keyPair = bitcoin.ECPair.fromPrivateKey(Buffer.from(privateKeys[i], 'hex'));
            for (let j = 0; j < utxos.length; j++) {
                if (utxos[j].address === multisigAddress) {
                    txb.sign({
                        prevOutScriptType: 'p2sh-p2wsh',
                        vin: j,
                        keyPair,
                        redeemScript: Buffer.from(multisigScriptHex, 'hex'),
                    });
                }
            }
        }

        // Step 6: Build and broadcast the transaction
        const tx = txb.build();
        const txHex = tx.toHex();
        const txid = await client.sendRawTransaction(txHex);
        console.log('Transaction ID:', txid);
    } catch (err) {
        console.error('Error:', err);
    }
})();
