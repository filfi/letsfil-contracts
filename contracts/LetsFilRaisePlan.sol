// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/ILetsFilRaisePlan.sol";
import "./interfaces/ILetsFilRaiseInfo.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import "./LetsFilRaiseFactory.sol";

enum RaiseState { 
    WaitingStart,   
    WaitingPayOPSSecurityFund,
    WaitingSPSign, 
    Raising,  
    Closed,  
    Success,
    Failure   
}

enum NodeState {
    WaitingStart,
    Started,
    Delayed,
    End,
    Success,
    Failure,
    Destroy
}


contract LetsFilRaisePlan is ILetsFilRaisePlan, Ownable {

    uint256 public immutable PLEDGE_MIN_AMOUNT = 10 ether;

    RaiseState public raiseState;
    NodeState public nodeState;

    uint256 public raiseID;
    RaiseInfo public raiseInfo;
    NodeInfo public nodeInfo;
    uint256 public totalRewardAmount;
    uint256 public availableRewardAmount;

    uint256 public pledgeTotalAmount;
    mapping(address => uint256) public pledgeRecord;
    mapping(address => uint256) public withdrawRecord;

    uint256 public startSealTime;
    uint256 public initPledgeAmount;
    uint256 public securityFundRemainAmount;
    uint256 public opsSecurityFundRemainAmount;

    //api manager
    address private manager;
    address private factoryAddress;

    // events
    event eDepositOPSSecurityFund(uint256 raiseID, address sender, uint256 amount);
    event eStartRaisePlan(address caller, uint256 raiseID);
    event eCloseRaisePlan(address caller, uint256 raiseID);
    event eWithdrawRaiseSecurityFund(address caller, uint256 raiseID, uint256 amount);
    event eWithdrawOPSSecurityFund(address caller, uint256 raiseID, uint256 amount);
    event eStaking(uint256 raiseID, address from, address to, uint256 amount);
    event eRaiseFailed(uint256 raiseID);
    event eUnstaking(uint256 raiseID, address from, address to, uint256 amount);
    event eSealingState(uint256 raiseID, NodeState state);
    event ePushBlockReward(uint256 released, uint256 willRelease);
    event eInvestorWithdraw(uint256 raiseID, address contractAddress, address from, address to, uint256 amount);
    event eRaiseWithdraw(uint256 raiseID, address from, address to, uint256 amount);
    event eSPWithdraw(uint256 raiseID, address from, address to, uint256 amount);

    // errors
    string constant PARAMS_ERROR = "param error";
    string constant PERMISSION_ERROR = "No permission";
    error NonPaymentOPSSecurityFund(); 
    error RaiseHaveSucceeded();
    error CannotWithdrawRaiseSecurityFund();
    error CannotWithdrawOPSSecurityFund();
    error RaiseNotInRaising(RaiseState state);
    error RaiseMinAmountWrong();
    error ForbidWithdrawSecurityFund();
    error UnstakingAmountError();

    constructor(uint256 _raiseID, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo, address _manager, address _factoryAddress) payable {
        raiseID = _raiseID;
        raiseInfo = _raiseInfo;
        nodeInfo = _nodeInfo;
        manager = _manager;
        raiseState = RaiseState.WaitingPayOPSSecurityFund;
        securityFundRemainAmount = msg.value;
    }

    modifier onlyManager() {
        require(msg.sender == manager ,"Not manager");
        _;
    }

    modifier onlySP() {
        require(msg.sender == raiseInfo.spAddress ,"Not server signer");
        _;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function specifyOpsPayer(address payer) external onlyOwner {
        nodeInfo.opsSecurityFundPayer = payer;
    }

    //pay second ops security fund by specify sp address
    function payOpsSecurityFund() payable external {
        require(raiseState == RaiseState.WaitingPayOPSSecurityFund, "Raise state must be WaitingPayOPSSecurityFund");
        require(msg.value == nodeInfo.opsSecurityFund, "Wrong ops security fund");
        require(msg.sender == nodeInfo.opsSecurityFundPayer, PERMISSION_ERROR);
        require(pledgeRecord[msg.sender] == 0, "OPSSecurityFund has been paid");

        pledgeRecord[msg.sender] = msg.value;
        pledgeTotalAmount = msg.value;
        opsSecurityFundRemainAmount = msg.value;

        raiseState = RaiseState.WaitingSPSign;
        emit eDepositOPSSecurityFund(raiseID, msg.sender, msg.value);
    }

    function startRaisePlan() external onlySP {
        if(raiseState != RaiseState.WaitingSPSign) {
            revert NonPaymentOPSSecurityFund();
        }
        // Verify that the node owner is the contract address todo...

        // Confirm set-owner todo...
        changeBeneficiary(CommonTypes.FilActorId.wrap(nodeInfo.minerID), CommonTypes.ChainEpoch.wrap(int64(uint64(block.timestamp + nodeInfo.nodePeriod * 2))));

        raiseState = RaiseState.Raising;
        emit eStartRaisePlan(msg.sender, raiseID);
    }

    event eChangeBeneficiary(CommonTypes.FilActorId _minerId, CommonTypes.ChainEpoch expiration);
    function changeBeneficiary(CommonTypes.FilActorId _minerId, CommonTypes.ChainEpoch expiration) internal {
        MinerTypes.ChangeBeneficiaryParams memory params;
        params.new_quota = BigInts.fromUint256(type(uint256).max);
        params.new_expiration = expiration;
        params.new_beneficiary = FilAddresses.fromEthAddress(address(this));
        emit eChangeBeneficiary(_minerId, expiration);
        MinerAPI.changeBeneficiary(_minerId, params);
    }

    // confirm set-owner todo...
    // getOwner todo...
    // getBeneficiary todo...

    function closeRaisePlan() external onlyOwner {
        if(raiseState >= RaiseState.Closed) {
            revert RaiseHaveSucceeded();
        }
        raiseState = RaiseState.Closed;

        // move minerId into inactive array
        require(LetsFilRaiseFactory(factoryAddress).endPlan(raiseID), "close raise plan failed");
        
        emit eCloseRaisePlan(msg.sender, raiseID);
    }

    function withdrawRaiseSecurityFund() external onlyOwner {
        require(securityFundRemainAmount >= raiseInfo.securityFund, "securityFund Insufficient balance");
        if(raiseState == RaiseState.Closed || raiseState == RaiseState.Failure) {
            payable(msg.sender).transfer(raiseInfo.securityFund);
        } else {
            revert CannotWithdrawRaiseSecurityFund();
        }
        securityFundRemainAmount -= raiseInfo.securityFund;

        emit eWithdrawRaiseSecurityFund(msg.sender, raiseID, raiseInfo.securityFund);
    }
    
    function withdrawOPSSecurityFund() external {
        //opsSecurityFundRemainAmount
        require(opsSecurityFundRemainAmount >= nodeInfo.opsSecurityFund, "opsSecurityFund Insufficient balance");
        require(msg.sender == nodeInfo.opsSecurityFundPayer, "Wrong withdraw address");
        if(!((raiseState == RaiseState.Closed || raiseState == RaiseState.Failure) && (nodeState == NodeState.Failure || nodeState == NodeState.Destroy))) {
            revert CannotWithdrawOPSSecurityFund();
        }

        opsSecurityFundRemainAmount -= nodeInfo.opsSecurityFund;
        payable(msg.sender).transfer(nodeInfo.opsSecurityFund);

        emit eWithdrawOPSSecurityFund(msg.sender, raiseID, nodeInfo.opsSecurityFund);
    }

    function staking() external payable {
        require(block.timestamp < raiseInfo.deadline, "Raise plan has expired");
        require(pledgeTotalAmount + msg.value <= raiseInfo.targetAmount, "More than the number raised");
        if(raiseState != RaiseState.Raising) {
            revert RaiseNotInRaising(raiseState);
        }

        // Less than the minimum amount needed to raise all
        if(msg.value < PLEDGE_MIN_AMOUNT) {
            if(raiseInfo.targetAmount - pledgeTotalAmount < PLEDGE_MIN_AMOUNT) {
                if(msg.value != (raiseInfo.targetAmount - pledgeTotalAmount)) {
                    revert RaiseMinAmountWrong();
                }
            } else {
                revert RaiseMinAmountWrong();
            }
        }

        pledgeRecord[msg.sender] += msg.value;
        pledgeTotalAmount += msg.value;
        
        if(raiseIsSuccessed()) {
            raiseState = RaiseState.Success;
            startSealTime = block.timestamp;
        }

        emit eStaking(raiseID, msg.sender, address(this), msg.value);
    }

    function unStaking(uint256 _amount) external {
        require(raiseState == RaiseState.Raising || raiseState == RaiseState.Closed || raiseState == RaiseState.Failure, "Wrong state");
        require(pledgeRecord[msg.sender] > 0 && _amount <= pledgeRecord[msg.sender], "Insufficient balance");

        //Cannot unStaking opsSecurityFund
        if(msg.sender == nodeInfo.opsSecurityFundPayer && _amount > (pledgeRecord[msg.sender] - nodeInfo.opsSecurityFund)) {
            revert ForbidWithdrawSecurityFund();
        }

        if(pledgeRecord[msg.sender] - _amount < PLEDGE_MIN_AMOUNT) {
            revert UnstakingAmountError();
        }

        // Raise expires, target not met, end of plan
        if (block.timestamp >= raiseInfo.deadline && pledgeTotalAmount < raiseInfo.targetAmount) {
            raiseState = RaiseState.Failure;
            emit eRaiseFailed(raiseID);
        }

        pledgeRecord[msg.sender] -= _amount;
        pledgeTotalAmount -= _amount;
        payable(msg.sender).transfer(_amount);

        emit eUnstaking(raiseID, msg.sender, address(this), _amount);
    }

    // investor withdraw
    function investorWithdraw(address _to, uint256 _amount) external {
        require(_amount > 0, PARAMS_ERROR);
        require(_amount <= availableRewardOf(msg.sender), "reward Insufficient balance");

        withdrawRecord[msg.sender] -= _amount;
        payable(_to).transfer(_amount);

        emit eInvestorWithdraw(raiseID, address(this), msg.sender, _to, _amount);
    }

    // raiser withdraw
    function raiserWithdraw(uint256 _amount) external onlyOwner {
        require(_amount > 0, PARAMS_ERROR);
        uint256 reward = availableRewardAmount * raiseInfo.raiserShare / 100;
        require(reward - withdrawRecord[msg.sender] >= _amount, "reward Insufficient balance");

        withdrawRecord[msg.sender] += _amount;
        payable(msg.sender).transfer(_amount);

        emit eRaiseWithdraw(raiseID, address(this), msg.sender, _amount);
    }

    // sp withdraw
    function spWithdraw(uint256 _amount) external onlySP {
        require(_amount > 0, PARAMS_ERROR);
        uint256 reward = availableRewardAmount * raiseInfo.servicerShare / 100;
        require(reward - withdrawRecord[msg.sender] >= _amount, "reward Insufficient balance");

        withdrawRecord[msg.sender] += _amount;
        payable(msg.sender).transfer(_amount);

        emit eSPWithdraw(raiseID, address(this), msg.sender, _amount);
    }

    // ########################## job api ############################
    function startSeal(uint256 startTime) external onlyManager {
        require(startTime <= block.timestamp, PARAMS_ERROR);

        startSealTime = startTime;
        nodeState = NodeState.Started;
        emit eSealingState(raiseID, nodeState);
    }

    // judge node's current state :
    // sealing: less 50% => End; greater 50% => Delay
    function pushSealProgress(uint256 _sealPledgedAmount) external onlyManager {
        if(nodeState == NodeState.Started) {
            nodeState = _sealPledgedAmount < raiseInfo.targetAmount / 2 ? NodeState.End : NodeState.Delayed;
        }

        emit eSealingState(raiseID, nodeState);
    }

    function stopSeal(uint256 _initPledgeAmount) external onlyManager {
        require(_initPledgeAmount <= raiseInfo.targetAmount, PARAMS_ERROR);
        nodeState = NodeState.Success;
        initPledgeAmount = _initPledgeAmount;
    }

    function destroyNode() external onlyManager {
        nodeState= NodeState.Destroy;
    }

    function pushBlockReward(uint256 _released, uint256 _willRelease) external onlyManager {
        require(_released > 0 && _willRelease >= 0, PARAMS_ERROR);
        totalRewardAmount = _released + _willRelease;
        availableRewardAmount = _released;

        emit ePushBlockReward(_released, _willRelease);
    }

    function raiseIsSuccess() public view onlyManager returns (bool) {
        return pledgeTotalAmount == raiseInfo.targetAmount;
    }
    // ########################## job api end ############################


    function availableReward() public view returns (uint256) {
        return availableRewardOf(msg.sender);
    }

    function availableRewardOf(address addr) public view returns (uint256) {
        return totalRewardOf(addr) - withdrawRecord[addr];
    }

    function totalReward() public view returns (uint256) {
        return totalRewardOf(msg.sender);
    }

    function totalRewardOf(address addr) public view returns (uint256) {
        return pledgeRecord[addr] * ((availableRewardAmount * raiseInfo.investorShare) / 100) / pledgeTotalAmount;
    }

    function willRelease() public view returns (uint256) {
        return willRelease(msg.sender);
    }

    function willRelease(address addr) public view returns (uint256) {
        return (pledgeRecord[addr] * ((totalRewardAmount - availableRewardAmount) * raiseInfo.investorShare) / 100) / pledgeTotalAmount;
    }


    function raiseIsSuccessed() public view returns (bool) { 
        return pledgeTotalAmount  == raiseInfo.targetAmount;
    }

    
}