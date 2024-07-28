const bitcoin = require('bitcoinjs-lib');
const { payments } = bitcoin;
const bs58check = require('bs58check');
const { ECPairFactory } = require("ecpair");
const tinysecp = require('tiny-secp256k1');
const bitcoinMessage = require('bitcoinjs-message');

const ECPair = ECPairFactory(tinysecp);

// TODO private key in hex
const privateKeyHex = '';

// Create a key pair from the private key
const keyPair = ECPair.fromPrivateKey(Buffer.from(privateKeyHex, 'hex'), { network: bitcoin.networks.regtest });

const messageToSign = '';

// Generate the address from the key pair
const { address } = payments.p2pkh({ pubkey: keyPair.publicKey, network: bitcoin.networks.regtest });

const privateKeyBuffer = keyPair.privateKey;
// Sign the message
const signature = bitcoinMessage.sign(messageToSign, privateKeyBuffer, keyPair.compressed);
console.log('Signed Message:', signature);

// Convert signature to base64
const signatureBase64 = signature.toString('base64');
const signatureHex = signature.toString('hex');

console.log('Signed Message:', signatureBase64);
console.log('Signed Message:', signatureHex);

//const isValid = bitcoinMessage.verify(messageToSign, "", signatureBase64);
//console.log('Message:', messageToSign);
//console.log('Address:', address);
//console.log('Signature is valid:', isValid);


