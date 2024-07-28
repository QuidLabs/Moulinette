const bitcoin = require('bitcoinjs-lib');
const Client = require('bitcoin-core');

// Configure the Bitcoin Core client
const client = new Client({
  network: 'regtest',
  username: 'username',
  password: 'password',
  host: 'localhost',
  port: 18443, 
  wallet: 'TODO' // Specify the wallet filename, if necessary
});

const NETWORK = bitcoin.networks.regtest; // Use 'bitcoin.networks.testnet' for testnet

async function sendTransaction() {
  const utxo = { // TODO
    txid: '',
    vout: 0,
    scriptPubKey: '',
    amount: 4,
    redeemScript: Buffer.from('', 'hex')
  };

  const privateKeys = [
    'your_private_key_hex_1',
    'your_private_key_hex_2'
  ];

  const destinationAddress = 'your_destination_address';
  const amountToSend = 1; // Amount in BTC
  const fee = 0.0001; // Fee in BTC

  const keyPairs = privateKeys.map(key => bitcoin.ECPair.fromPrivateKey(Buffer.from(key, 'hex'), { network: NETWORK }));

  // Create a transaction builder
  const txb = new bitcoin.TransactionBuilder(NETWORK);
  txb.addInput(utxo.txid, utxo.vout, null, Buffer.from(utxo.scriptPubKey, 'hex'));
  txb.addOutput(destinationAddress, Math.floor(amountToSend * 1e8));
  txb.addOutput('your_change_address', Math.floor((utxo.amount - amountToSend - fee) * 1e8));

  // Sign the transaction
  for (let i = 0; i < keyPairs.length; i++) {
    txb.sign({
      prevOutScriptType: 'p2sh',
      vin: 0,
      keyPair: keyPairs[i],
      redeemScript: utxo.redeemScript
    });
  }

  // Build the transaction
  const tx = txb.build();
  const txHex = tx.toHex();

  // Broadcast the transaction
  try {
    const txid = await client.sendRawTransaction(txHex);
    console.log(`Transaction broadcasted with txid: ${txid}`);
  } catch (error) {
    console.error('Error broadcasting transaction:', error);
  }
}

sendTransaction();
