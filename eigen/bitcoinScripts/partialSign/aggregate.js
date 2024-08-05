const bitcoin = require('bitcoinjs-lib');

// Function to combine and finalize multiple PSBTs
function combineAndFinalizeMultisigPsbt(signedPsbtBase64List) {
    const psbts = signedPsbtBase64List.map(psbtBase64 => bitcoin.Psbt.fromBase64(psbtBase64, { network: bitcoin.networks.regtest }));
    
    // Combine partially signed PSBTs
    const combinedPsbt = psbts[0];
    for (let i = 1; i < psbts.length; i++) {
        combinedPsbt.combine(psbts[i]);
    }

    // Finalize all inputs
    combinedPsbt.finalizeAllInputs();

    // Extract the raw transaction hex
    const txHex = combinedPsbt.extractTransaction().toHex();
    console.log('Final transaction hex:', txHex);
    
    return txHex;
}

// TODO
let signedPsbtBase64List = [
    '',
];

const finalTxHex = combineAndFinalizeMultisigPsbt(signedPsbtBase64List);

async function broadcastTransaction(txHex) {
    const Client = require('bitcoin-core');

    const client = new Client({
        network: 'regtest',
        username: 'username',
        password: 'password',
        host: 'localhost',
        port: 18443
    });

    try {
        const txid = await client.sendRawTransaction(txHex);
        console.log('Transaction broadcasted, txid:', txid);
    } catch (error) {
        console.error('Error broadcasting transaction:', error);
    }
}

// Example usage
broadcastTransaction(finalTxHex);

