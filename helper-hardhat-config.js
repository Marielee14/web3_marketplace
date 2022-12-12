const developmentChains = ["hardhat", "localhost"];
const VERIFICATION_BLOCK_CONFIRMATIONS = 6; //number of blocks that must be added to the blockchain 
//before we assume that a transaction(including the creation of a new smart contract) is confirmed. 

module.exports = { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS };
