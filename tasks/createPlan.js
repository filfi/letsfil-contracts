const {task} = require("hardhat/config");
const util = require("util");
const request = util.promisify(require("request"));
const { factoryAddress, callRpc } = require( "./common");

task("create-plan", "create raise plan")
  .setAction(async (taskArgs, {network, ethers}) => {
    const priorityFee = await callRpc("eth_maxPriorityFeePerGas", [])
    console.log("Calling create raise plan method: ", factoryAddress)

    //Get signer information
    const accounts = await ethers.getSigners()
    const signer = accounts[0]
    
    const raiseInfo = {
        id: 0,
        targetAmount: ethers.utils.parseEther('10'),
        securityFund: ethers.utils.parseEther('1.0'), // 1000000000
        deadline: 1680768506,
        securityFundRate: 10, // 10% 
        raiserShare: 20,      
        investorShare: 50,
        servicerShare: 30,
        sponsor: signer.address,
        serverSigner: signer.address,
        companyId: 1,
        spAddress: signer.address,
    }
   
    const nodeInfo = {
        nodeSize: 11258999,
        sectorSize: 34359738368,
        sealPeriod: 30, // 30days
        nodePeriod: 540, // 180days
        opsSecurityFund: ethers.utils.parseEther("1.0"), // 1000000000
        opsSecurityFundPayer: signer.address,
        manager: signer.address,
        minerID: 1135
    }

    const factory = await ethers.getContractFactory("LetsFilRaiseFactory", signer);
    const contract = new ethers.Contract(factoryAddress, factory.interface, signer)
  
    contract.once("eCreateRaisePlan", (addr) => {
        console.log("plan contract listen address...", addr);
    });
      
    let tx = await contract.createRaisePlan(raiseInfo, nodeInfo,  {
        // maxPriorityFeePerGas: ethers.utils.parseUnits("50", "gwei"),
        // maxFeePerGas: ethers.utils.parseUnits("50", "gwei"),
        gasLimit: 10000000000,
        maxPriorityFeePerGas: priorityFee,
        value: ethers.utils.parseEther('1.0')
    });

    await tx.wait();
    console.log(tx)
    
})
  

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {}
