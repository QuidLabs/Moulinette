const bitcoin = require('bitcoinjs-lib');
const Client = require('bitcoin-core');
const { ECPairFactory } = require("ecpair");
const tinysecp = require('tiny-secp256k1');

const ECPair = ECPairFactory(tinysecp);
// Configure the Bitcoin Core client
const client = new Client({
    network: 'regtest', // Use 'testnet' or 'mainnet' for other networks
    username: 'username',
    password: 'password',
    host: 'localhost',
    port: 18443 // Default port for regtest, adjust if necessary
});

const NETWORK = bitcoin.networks.regtest; // Use 'bitcoin.networks.testnet' for testnet

async function sendTransaction() {
    const utxo = {
        txid: '',
        vout: 0,
        scriptPubKey: '',
        amount: 5,
        redeemScript: Buffer.from('', 'hex')
    };

    const privateKeys = [
        '',
        ''
    ];

    const destinationAddress = '';
    const amountToSend = 1;
    const fee = 0.0001;

    const keyPairs = privateKeys.map(key => ECPair.fromPrivateKey(Buffer.from(key, 'hex'), { network: NETWORK }));

    console.log("K1")
    console.log(NETWORK);
    console.log("K2")
    const rawTx = "";
    const prevTx = bitcoin.Transaction.fromHex("");
    console.log(prevTx);
    const psbt = new bitcoin.Psbt({ network: NETWORK });

    // Add input (the UTXO to spend)
    psbt.addInput({
        hash: utxo.txid,
        index: utxo.vout,
        nonWitnessUtxo: Buffer.from(rawTx, 'hex'),
        redeemScript: utxo.redeemScript
    });

    // Add output (destination address and change address)
    psbt.addOutput({
        address: destinationAddress,
        value: Math.floor(amountToSend * 1e8) // Amount to send in satoshis
    });
    psbt.addOutput({
        address: "",
        value: Math.floor((utxo.amount - amountToSend - fee) * 1e8) // Change amount in satoshis
    });

    // Sign the transaction with each private key
    keyPairs.forEach((keyPair, index) => {
        console.log(index)
        console.log(keyPair)
        psbt.signInput(0, keyPair);
    });

    // Validate all signatures and finalize the transaction
    //psbt.validateSignaturesOfAllInputs();
    psbt.finalizeAllInputs();

    // Get the raw transaction hex
    const txHex = psbt.extractTransaction().toHex();
    console.log(txHex)

    // Broadcast the transaction
    try {
        const txid = await client.sendRawTransaction(txHex);
        console.log(`broadcasted, txid: ${txid}`);
    } catch (error) {
        console.error('Error:', error);
    }
}


sendTransaction();
