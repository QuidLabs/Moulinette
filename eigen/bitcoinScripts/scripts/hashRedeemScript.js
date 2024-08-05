const bitcoin = require('bitcoinjs-lib');

// Redeem script provided
const redeemScriptHex = '';
const redeemScript = Buffer.from(redeemScriptHex, 'hex');

// Compute the hash160 of the redeem script
const hash160 = bitcoin.crypto.hash160(redeemScript);

console.log('Redeem Script Hash:', hash160.toString('hex'));

// Build the scriptPubKey for the P2SH address
const scriptPubKey = bitcoin.payments.p2sh({ redeem: { output: redeemScript } }).output;
console.log('scriptPubKey:', scriptPubKey.toString('hex'));

// Get the P2SH address
const address = bitcoin.payments.p2sh({ redeem: { output: redeemScript }, network: bitcoin.networks.regtest }).address;
console.log('P2SH Address:', address);
