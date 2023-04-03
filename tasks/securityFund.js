const {task} = require("hardhat/config");
const util = require("util");
const request = util.promisify(require("request"));
const { planAddress } = require( "./common");

task("payOPSSecurityFund", "pay OPS security fund")
  .setAction(async (taskArgs, {network, ethers}) => {
    const accounts = await ethers.getSigners()
    const signer = accounts[0]

    const factory = await ethers.getContractFactory("LetsFilRaisePlan", signer);
    const contract = new ethers.Contract(planAddress, factory.interface, signer)

    const priorityFee = await callRpc("eth_maxPriorityFeePerGas", [])
 
    let tx = await contract.payOpsSecurityFund({
        // maxPriorityFeePerGas: ethers.utils.parseUnits("50", "gwei"),
        // maxFeePerGas: ethers.utils.parseUnits("50", "gwei"),
        gasLimit: 10000000000,
        maxPriorityFeePerGas: priorityFee,
        value: ethers.utils.parseEther('1.0'),
    });

    await tx.wait();
    console.log(tx)
    
})
  

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {}
