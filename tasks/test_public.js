// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const util = require("util");
const request = util.promisify(require("request"));
const { planAddress, callRpc } = require( "./common");

async function main() {
    const [owner] = await ethers.getSigners();
    console.log("owner addr =", owner.address);

    const LetsFilRaisePlan = await hre.ethers.getContractFactory("LetsFilRaisePlan");
    const contract = new hre.ethers.Contract(planAddress, LetsFilRaisePlan.interface, owner)

    const priorityFee = await callRpc("eth_maxPriorityFeePerGas", [])
    console.log("Calling pledge method: ", priorityFee)
 
    let tx = await contract.raiseInfo({
        // maxPriorityFeePerGas: ethers.utils.parseUnits("50", "gwei"),
        // maxFeePerGas: ethers.utils.parseUnits("50", "gwei"),
        gasLimit: 10000000000,
        maxPriorityFeePerGas: priorityFee,
    });

    console.log(tx)
    
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
