const bitcoin = require('bitcoinjs-lib');
const tinysecp = require('tiny-secp256k1');
const { ECPairFactory } = require('ecpair');
const ECPair = ECPairFactory(tinysecp);

const NETWORK = bitcoin.networks.regtest;

const rawPrivateKeys = [
    '',
    '',
    '',
    ''
];

const wifKeys = rawPrivateKeys.map(hex => {
    const keyPair = ECPair.fromPrivateKey(Buffer.from(hex, 'hex'));
    return keyPair.toWIF();
});

console.log(wifKeys);
