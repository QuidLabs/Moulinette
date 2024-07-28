const Client = require('bitcoin-core');
const client = new Client({
  network: 'regtest',
  host: '127.0.0.1',
  username: 'username',
  password: 'password',
  port: 18443,
  wallet: 'w2'
});

async function mineBlocks(numberOfBlocks) {
    try {
      await client.generate(numberOfBlocks);
      console.log(`Successfully mined ${numberOfBlocks} blocks.`);
    } catch (error) {
      console.error('Error mining blocks:', error.message);
    }
  }
  
  mineBlocks(110);
  