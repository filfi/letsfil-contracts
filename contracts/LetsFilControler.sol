// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/ILetsFilPackInfo.sol";

interface ITools {
    function manager() external view returns (address);
    function receiver() external view returns (address);
}

interface IFilMiner {
    function getOwner(uint64 minerId) external returns (bytes memory);
}

enum RaiseState {
    WaitingStart,
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
    Destroy
}

contract LetsFilControler is ILetsFilPackInfo {
    bool private initialized;

    mapping(uint256 => RaiseState) public raiseState;
    mapping(uint256 => NodeState) public nodeState;

    mapping(uint256 => RaiseInfo) public raiseInfo;
    mapping(uint256 => NodeInfo) public nodeInfo;
    mapping(uint256 => ExtendInfo) public extendInfo;
    mapping(uint256 => uint256) public totalRewardAmount;
    mapping(uint256 => uint256) public totalReleasedRewardAmount;
    mapping(uint256 => uint256) public pledgeTotalAmount;
    mapping(uint256 => uint256) public pledgeTotalCalcAmount;
    mapping(uint256 => uint256) public pledgeTotalDebt;
    mapping(uint256 => uint256) public totalInterest;

    struct InvestorInfo {
        uint256 pledgeAmount;
        uint256 pledgeCalcAmount;
        uint256 interestDebt;
        uint256 withdrawAmount;
    }
    mapping(uint256 => mapping(address => InvestorInfo)) public investorInfo;

    mapping(uint256 => uint256) public toSealAmount;
    mapping(uint256 => uint256) public sealedAmount;
    mapping(uint256 => uint256) public gotRaiserReward;
    mapping(uint256 => uint256) public gotSpReward;
    mapping(uint256 => uint256) public gotFilFiReward;
    mapping(uint256 => uint256) public gotSpFundReward;

    mapping(uint256 => uint256) public spFine;
    mapping(uint256 => uint256) public spRemainFine;
    mapping(uint256 => uint256) public spRewardLock;

    mapping(uint256 => uint256) public spRewardFine;
    mapping(uint256 => uint256) public spFundFine;
    mapping(uint256 => uint256) public spFundRewardFine;
    mapping(uint256 => uint256) public raiserFine;
    mapping(uint256 => uint256) public investorFine;

    mapping(uint256 => uint256) public pledgeReleased;
    mapping(uint256 => uint256) public returnAmount;

    mapping(uint256 => uint256) public securityFundRemain;
    mapping(uint256 => uint256) public opsSecurityFundRemain;
    mapping(uint256 => uint256) public opsCalcFund;

    mapping(uint256 => uint256) public raiseStartTime;
    mapping(uint256 => uint256) public raiseCloseTime;
    mapping(uint256 => uint256) public startSealTime;
    mapping(uint256 => uint256) public sealEndTime;

    //api manager
    uint64 public minerId;
    address public sp;  //service provider
    address public raiser;
    bool public gotMiner;
    address private constant _toolAddr = address(0x189a5BD936b64Caa4EbEbb27c1A46F8bCD47f50c); //Mainnet
    address private constant _minerToolAddr = address(0x098d92284597639c35e44819319eb33857Be6762); //Mainnet
    address private constant _processAddr = address(0x098d92284597639c35e44819319eb33857Be6762); //Mainnet
    address private constant _processSecond = address(0x098d92284597639c35e44819319eb33857Be6762); //Mainnet

    uint256 public constant PLEDGE_MIN_AMOUNT = 10**16;
    //Network base annual interest rate for calculating fine
    uint256 private constant networkAnnual = 100;
    //uint256 private constant rateBase = 10000;
    uint256 private constant rateBase = 10000;
    uint256 private constant fineCoeff = 30000;
    //Successfully to entered the delay period
    uint256 private constant sealMinCoeff = 5000;
    //to set the seal delay days
    uint256 private constant sealDelayCoeff = 5000;
    uint256 private constant protocolSealFineCoeff = 10;
    //raise plan's commission coefficient
    uint256 private constant feeCoeff = 30;

    uint256 private constant spSafeSealFund = 300*10**18;

    bytes private mOwner; //miner's old owner
    bool private mOwnerBack;

    //sector package
    mapping(uint256 => uint256) public secPack;
    //sealed opsSecurityFund
    mapping(uint256 => uint256) public fundSealed;
    //fine reduced by adding opsSecurityFund
    mapping(uint256 => uint256) public subFine;
    mapping(uint256 => uint256) public safeSealFund;
    mapping(uint256 => uint256) public fundBack;
    mapping(uint256 => uint256) public safeFundFine;
    mapping(uint256 => bool) public progressEnd;
    mapping(uint256 => uint256) public safeSealedFund;

    mapping(uint256 => bool) public mountOrNot;
    mapping(uint256 => uint256) public sponsorNo; //number of sponsors
    mapping(uint256 => uint256) public sponsorAckNo; //number of sponsors who acknowledged
    mapping(uint256 => mapping(address => uint256)) public sponsorPower;
    mapping(uint256 => mapping(address => bool)) public sponsorAck; //sponsor acknowledge
    mapping(uint256 => uint256) public investorNo; //number of investors
    mapping(uint256 => uint256) public investorAckNo; //number of investors who acknowledged
    mapping(uint256 => mapping(address => uint256)) public investorPower;
    mapping(uint256 => mapping(address => bool)) public investorAck; //investor acknowledge

    mapping(uint256 => mapping(address => uint256)) public gotSponsorReward;

    mapping(uint256 => bool) public privateOrNot;
    mapping(uint256 => mapping(address => uint256)) public investorMaxPledge;

    mapping(uint256 => bool) public timedOrNot;

    // events
    event RaiseStateChange(uint256 indexed id, RaiseState state);
    event NodeStateChange(uint256 indexed id, NodeState state);
    event SpSignWithMiner(address indexed sp, uint64 indexed minerId, address contractAddr);
    event DepositSecurityFund(uint256 indexed id, address indexed sponsorAddr, uint256 amount);
    event DepositOpsSecurityFund(uint256 indexed id, address indexed sender, uint256 amount);
    event AddOpsSecurityFund(uint256 indexed id, address indexed sender, uint256 amount);
    event StartRaisePlan(uint256 indexed id, address indexed sponsorAddr, uint256 startTime);
    event CloseRaisePlan(uint256 indexed id, address indexed sponsorAddr, uint256 closeTime);
    event ClosePlanToSeal(uint256 indexed id, address indexed sponsorAddr, uint256 closeTime, uint256 toSealAmount);
    event WithdrawSecurityFund(uint256 indexed id, address indexed caller, uint256 amount);
    event WithdrawOpsSecurityFund(uint256 indexed id, address indexed caller, uint256 amount, uint256 interest, uint256 reward, uint256 fine);
    event Staking(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);
    event RaiseSuccess(uint256 indexed raiseID, uint256 pledgeAmount);
    event RaiseFailed(uint256 indexed raiseID);
    event StartSeal(uint256 indexed id, address indexed caller, uint256 startTime);
    event StartPreSeal(uint256 indexed id, address indexed caller);
    event SendToMiner(uint256 indexed id, address indexed caller, uint256 amount);
    event PushOldAssetPackValue(uint256 id, address caller, uint256 totalPledge, uint256 released, uint256 willRelease);
    event PushSealProgress(uint256 indexed id, uint256 amount, NodeState state);
    event PushFinalProgress(uint256 indexed id, uint256 amount, NodeState state);
    event SealEnd(uint256 indexed id, uint256 amount);
    event PushBlockReward(uint256 indexed id, uint256 released, uint256 willRelease);
    event PushSpFine(uint256 indexed id, uint256 fineAmount);
    event PushPledgeReleased(uint256 indexed id, uint256 released);
    event Unstaking(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount, uint256 interest);
    event DestroyNode(uint256 indexed raiseID, NodeState state);
    event InvestorWithdraw(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);
    event RaiseWithdraw(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);
    event SpWithdraw(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);

    function initialize(uint256 _raiseID, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo, ExtendInfo memory _extendInfo) public {
        require(!initialized ,"Ctrl: already initialized.");
        initialized = true;

        raiseInfo[_raiseID] = _raiseInfo;
        nodeInfo[_raiseID] = _nodeInfo;
        extendInfo[_raiseID] = _extendInfo;

        minerId = _nodeInfo.minerId;
        raiser = _raiseInfo.sponsor;
        sp = _nodeInfo.spAddr;

        if(_extendInfo.oldId != 0) {
            secPack[0] = _extendInfo.oldId;
        }
        secPack[1] = _raiseInfo.id;
    }

    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    fallback() external payable {
        _delegate(_processSecond);
    }
    receive() external payable {}

    modifier onlyManager() {
        require(msg.sender == ITools(_toolAddr).manager() ,"Ctrl: not manager.");
        _;
    }

    modifier onlyRaiser() {
        require(msg.sender == raiser ,"Ctrl: not raiser.");
        _;
    }

    modifier onlySp() {
        require(msg.sender == sp ,"Ctrl: not service provider.");
        _;
    }

    function spSignWithMiner() public onlySp {
        require(!mOwnerBack, "Ctrl: already changed back.");

        uint256 id = secPack[1];
        if(timedOrNot[id]) {
            require(block.timestamp < raiseStartTime[id], "Ctrl: expired.");
        }

        //Verify that the node owner is this contract address
        mOwner = IFilMiner(_minerToolAddr).getOwner(minerId);
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("spSignWithMiner(uint64)", minerId));
        require(success && result.length >= 0, "Ctrl: sign err.");

        gotMiner = true;
        emit SpSignWithMiner(msg.sender, minerId, address(this));
    }

    function setMinerBackOwner(bytes memory minerOwner) public onlySp {
        mOwner = minerOwner;
    }

    function paySecurityFund(uint256 id) public payable onlyRaiser {
        require(raiseState[id] == RaiseState.WaitingStart, "Ctrl: state err.");
        require(msg.value > 0, "Ctrl: value is 0.");
        require(msg.value == raiseInfo[id].securityFund && securityFundRemain[id] == 0, "Ctrl: value incorrect.");
        if(timedOrNot[id]) {
            require(block.timestamp < raiseStartTime[id], "Ctrl: expired.");
        }

        securityFundRemain[id] = msg.value;
        emit DepositSecurityFund(id, msg.sender, msg.value);
    }

    //pay second ops security fund
    function payOpsSecurityFund(uint256 id) public payable onlySp {
        require(raiseState[id] == RaiseState.WaitingStart, "Ctrl: state err.");
        require(msg.value > 0, "Ctrl: value is 0.");
        require(msg.value == nodeInfo[id].opsSecurityFund + spSafeSealFund && opsSecurityFundRemain[id] == 0, "Ctrl: value incorrect.");
        if(timedOrNot[id]) {
            require(block.timestamp < raiseStartTime[id], "Ctrl: expired.");
        }

        opsSecurityFundRemain[id] = nodeInfo[id].opsSecurityFund;
        opsCalcFund[id] = nodeInfo[id].opsSecurityFund;
        safeSealFund[id] = spSafeSealFund;

        emit DepositOpsSecurityFund(id, msg.sender, msg.value);
    }

    function startRaisePlan(uint256 id) public onlyRaiser {
        require(raiseState[id] == RaiseState.WaitingStart, "RaisePlan: raising is already started.");
        require(securityFundRemain[id] == raiseInfo[id].securityFund && opsSecurityFundRemain[id] == nodeInfo[id].opsSecurityFund, "RaisePlan: no pay securityFund.");
        require(gotMiner, "RaisePlan: miner's owner is not this contract.");
        require(!timedOrNot[id], "Ctrl: timed plan.");

        raiseState[id] = RaiseState.Raising;
        raiseStartTime[id] = block.timestamp;
        raiseCloseTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
        startSealTime[id] = raiseCloseTime[id];
        sealEndTime[id] = raiseCloseTime[id] + nodeInfo[id].sealDays * 1 days;
        emit RaiseStateChange(id, raiseState[id]);
        emit StartRaisePlan(id, msg.sender, raiseStartTime[id]);
    }

    function timedPlanState(uint256 id) public view returns (uint256) {
        if( timedOrNot[id] && raiseState[id] == RaiseState.WaitingStart && block.timestamp > raiseStartTime[id] &&
            securityFundRemain[id] == raiseInfo[id].securityFund && opsSecurityFundRemain[id] == nodeInfo[id].opsSecurityFund && gotMiner ) {
            return 1;
        } else if( timedOrNot[id] && raiseState[id] == RaiseState.WaitingStart && block.timestamp > raiseStartTime[id] &&
                   ( securityFundRemain[id] != raiseInfo[id].securityFund || opsSecurityFundRemain[id] != nodeInfo[id].opsSecurityFund || (!gotMiner) ) ) {
            return 4;
        } else if(nodeState[id] == NodeState.Destroy) {
            return 9;
        } else {
            return uint256(raiseState[id]);
        }
    }

    function backOwner() public {
        uint256 planId = secPack[1];
        if(raiseState[planId] == RaiseState.WaitingStart && timedPlanState(planId) == 4) {
            raiseState[planId] = RaiseState.Failure;
            emit RaiseStateChange(planId, raiseState[planId]);
            emit RaiseFailed(planId);
        }
        require(raiseState[planId] == RaiseState.Closed || raiseState[planId] == RaiseState.Failure || nodeState[planId] == NodeState.Destroy, "Ctrl: state err.");

        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("backOwner(uint64,bytes)", minerId, mOwner));
        require(success && result.length >= 0, "Ctrl: back owner err.");

        mOwnerBack = true;
        gotMiner = false;
    }

    function closeRaisePlan(uint256 id) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("closeRaisePlan(uint256)", id));
        require(success && result.length >= 0, "Ctrl: close plan err.");
    }

    function withdrawSecurityFund(uint256 id) public onlyRaiser {
        require(securityFundRemain[id] != 0, "Ctrl: securityFund null.");

        if(raiseState[id] == RaiseState.WaitingStart && timedPlanState(id) == 4) {
            raiseState[id] = RaiseState.Failure;
            emit RaiseStateChange(id, raiseState[id]);
            emit RaiseFailed(id);
        }
        if(raiseState[id] != RaiseState.Closed && raiseState[id] != RaiseState.Failure) {
            require(progressEnd[id], "Ctrl: seal state err.");
        }

        uint256 transAmount = 0;
        if(securityFundRemain[id] > raiserFine[id]) { 
            transAmount = securityFundRemain[id] - raiserFine[id];
            raiserFine[id] = 0;
            payable(msg.sender).transfer(transAmount);
        } else {
            raiserFine[id] -= securityFundRemain[id];
        }
        securityFundRemain[id] = 0;

        emit WithdrawSecurityFund(id, msg.sender, transAmount);
    }

    function withdrawOpsSecurityFund(uint256 id) public onlySp {
        require(opsSecurityFundRemain[id] != 0, "Process: opsSecurityFund null.");
        if(raiseState[id] == RaiseState.WaitingStart && timedPlanState(id) == 4) {
            raiseState[id] = RaiseState.Failure;
            emit RaiseStateChange(id, raiseState[id]);
            emit RaiseFailed(id);
        }
        //Closing, failure, and node runtime expiration can all be extracted.  or all token(include reward) is back
        require(raiseState[id] == RaiseState.Closed || raiseState[id] == RaiseState.Failure || nodeState[id] == NodeState.Destroy, "Process: plan or node state error.");

        uint256 interest = 0;
        if(raiseState[id] == RaiseState.Closed && totalInterest[id] > 0) {
            interest = (opsCalcFund[id] + safeSealFund[id]) * (raiseCloseTime[id] - raiseStartTime[id]) * networkAnnual / (rateBase * 365 days);
        } else if(raiseState[id] == RaiseState.Failure && totalInterest[id] > 0) {
            interest = (opsCalcFund[id] + safeSealFund[id]) * raiseInfo[id].raiseDays * networkAnnual / (rateBase * 365);
        }

        uint256 reward = opsFundReward(id);

        uint256 transAmount = opsSecurityFundRemain[id] + safeSealFund[id] + interest + reward - spFundFine[id];
        payable(msg.sender).transfer(transAmount);

        emit WithdrawOpsSecurityFund(id, msg.sender, opsSecurityFundRemain[id] + safeSealFund[id], interest, reward, spFundFine[id]);
        opsSecurityFundRemain[id] = 0;
        safeSealFund[id] = 0;
    }

    function opsFundReward(uint256 id) public view returns(uint256) {
        if(raiseState[id] == RaiseState.Failure) return 0;
        uint256 reward = 0;
        uint256 calcReward = totalRewardAmount[id] * (raiseInfo[id].investorShare + raiseInfo[id].spFundShare) / rateBase;
        if(sealedAmount[id] <= pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
            reward = calcReward * opsCalcFund[id] / (opsCalcFund[id] + raiseInfo[id].targetAmount);
        } else {
            reward = calcReward * fundSealed[id] / sealedAmount[id];
        }
        if(opsSecurityFundRemain[id] == 0) reward = 0;
        return reward;
    }

    function staking(uint256 id) public payable {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("staking(uint256)", id));
        require(success && result.length >= 0, "Ctrl: staking err.");
    }

    function raiseExpire(uint256 id) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("raiseExpire(uint256)", id));
        require(success && result.length >= 0, "Ctrl: raiseExpire err.");
    }

    //Enter the preparation period of sealing.
    function startPreSeal(uint256 id) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("startPreSeal(uint256)", id));
        require(success && result.length >= 0, "Ctrl: startPreSeal err.");
    }

    function getBack(uint256 id, address account) public view returns (uint256, uint256) {
        uint256 pledge = investorInfo[id][account].pledgeAmount;
        uint256 calc = investorInfo[id][account].pledgeCalcAmount;
        uint256 tCalc = pledgeTotalCalcAmount[id];
        uint256 amountBack = 0;
        uint256 interestBack = 0;
        uint256 freeCalc = pledgeReleased[id];

        if(mountOrNot[id]) {
            amountBack = pledge - calc * (tCalc - freeCalc) / tCalc;
            return(amountBack, interestBack);
        }

        if(raiseInfo[id].targetAmount > 0) tCalc += opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount;
        if(raiseState[id] == RaiseState.Closed || raiseState[id] == RaiseState.Failure) {
            amountBack = pledge;
            if(raiseCloseTime[id] > raiseStartTime[id] && pledge * (raiseCloseTime[id] - raiseStartTime[id]) > investorInfo[id][account].interestDebt) {
                interestBack = (pledge * (raiseCloseTime[id] - raiseStartTime[id]) - investorInfo[id][account].interestDebt) * networkAnnual / (rateBase * 365 days);
            }
            return(amountBack, interestBack);
        }

        if(progressEnd[id] && sealedAmount[id] < tCalc) {
            if(pledge > calc * sealedAmount[id] / tCalc) {
                amountBack = pledge - calc * sealedAmount[id] / tCalc;
                interestBack = amountBack * (calc * (sealEndTime[id] - raiseStartTime[id]) - investorInfo[id][account].interestDebt) * networkAnnual / (rateBase * 365 days * calc);
            }
            if(freeCalc > 0) {
                if(freeCalc > sealedAmount[id]) freeCalc = sealedAmount[id];
                amountBack = pledge - calc * (sealedAmount[id] - freeCalc) / tCalc;
            }
        } else if(freeCalc > 0 && progressEnd[id]) {
            if(freeCalc > sealedAmount[id]) freeCalc = sealedAmount[id];
            amountBack = pledge - calc * (sealedAmount[id] - freeCalc) / sealedAmount[id];
        }
        return(amountBack, interestBack);
    }

    function unStaking(uint256 id) public {
        (uint256 backAmount, uint256 backInterest) = getBack(id, msg.sender);
        require(backAmount + backInterest > 0, "Ctrl: no asset.");

        investorInfo[id][msg.sender].pledgeAmount -= backAmount;
        pledgeTotalAmount[id] -= backAmount;

        payable(msg.sender).transfer(backAmount + backInterest);

        emit Unstaking(id, address(this), msg.sender, backAmount, backInterest);
    }

    // investor withdraw reward
    function investorWithdraw(uint256 id) public {
        if(mountOrNot[id]) {
            require(raiseState[id] == RaiseState.Success, "Ctrl: state err when mount.");
        } else {
            require(nodeState[id] != NodeState.WaitingStart, "Ctrl: nodeState error.");
        }
        uint256 _amount = availableRewardOf(id, msg.sender);
        require(_amount > 0, "RaisePlan: param error.");

        investorInfo[id][msg.sender].withdrawAmount += _amount;

        payable(msg.sender).transfer(_amount);

        emit InvestorWithdraw(id, address(this), msg.sender, _amount);
    }

    // raiser withdraw reward
    function raiserWithdraw(uint256 id) public onlyRaiser {
        uint256 _amount = raiserRewardAvailableLeft(id);
        require(_amount != 0, "Ctrl: no reward.");
        require(sponsorNo[id] == 0, "Ctrl: old method.");
        if(mountOrNot[id]) {
            require(raiseState[id] == RaiseState.Success, "Ctrl: state err when mount.");
        } else {
            require(nodeState[id] != NodeState.WaitingStart, "Ctrl: state err.");
        }

        gotRaiserReward[id] += _amount;
        payable(msg.sender).transfer(_amount);

        emit RaiseWithdraw(id, address(this), msg.sender, _amount);
    }

    function raiserWillReleaseReward(uint256 id) public view returns (uint256) {
        return (totalRewardAmount[id] - totalReleasedRewardAmount[id]) * raiseInfo[id].raiserShare / rateBase;
    }

    function raiserRewardAvailableLeft(uint256 id) public view returns (uint256) {
        return totalReleasedRewardAmount[id] * raiseInfo[id].raiserShare / rateBase - gotRaiserReward[id];
    }

    // sp withdraw reward
    function spWithdraw(uint256 id) public onlySp {
        uint256 _amount = spRewardAvailableLeft(id);
        require(_amount > 0, "RaisePlan: param error.");

        if(mountOrNot[id]) {
            require(raiseState[id] == RaiseState.Success, "Ctrl: state err when mount.");
        } else {
            require(nodeState[id] != NodeState.WaitingStart, "Ctrl: nodeState err.");
        }

        gotSpReward[id] += _amount;
        payable(msg.sender).transfer(_amount);

        emit SpWithdraw(id, address(this), msg.sender, _amount);
    }

    function spWillReleaseReward(uint256 id) public view returns (uint256) {
        return (totalRewardAmount[id] - totalReleasedRewardAmount[id]) * raiseInfo[id].servicerShare / rateBase;
    }

    function spRewardAvailableLeft(uint256 id) public view returns (uint256 amountReturn) {
        amountReturn = 0;
        uint256 totalReward = totalReleasedRewardAmount[id] * raiseInfo[id].servicerShare / rateBase;

        if(totalReward > spRewardLock[id] + gotSpReward[id] + spRewardFine[id]) {
            amountReturn = totalReward - spRewardLock[id] - gotSpReward[id] - spRewardFine[id];
        }
    }

    // ########################## job api ############################

    function pushOldAssetPackValue(uint256 id, uint256 totalPledge, uint256 released, uint256 willRelease) public onlyManager {//todo...
        require(id == extendInfo[id].oldId, "old err");
        pledgeTotalAmount[id] = totalPledge;
        pledgeTotalCalcAmount[id] = totalPledge;

        emit PushOldAssetPackValue(id, msg.sender, totalPledge, released, willRelease);
    }

    function pushSealProgress(uint256 id, uint256 amount) public {
        (bool success, bytes memory result) = _processSecond.delegatecall(abi.encodeWithSignature("pushSealProgress(uint256,uint256)", id, amount));
        require(success && result.length >= 0, "Ctrl: progress err.");
    }

    function pushFinalProgress(uint256 id, uint256 amount) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("pushFinalProgress(uint256,uint256)", id, amount));
        require(success && result.length >= 0, "Ctrl: final progress err.");
    }

    function destroyNode(uint256 id) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("destroyNode(uint256)", id));
        require(success && result.length >= 0, "Ctrl: destroy err.");
    }

    function pushSpFine(uint256 id, uint256 fineAmount) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("pushSpFine(uint256,uint256)", id, fineAmount));
        require(success && result.length >= 0, "Ctrl: push fine err.");
    }

    function pushPledgeReleased(uint256 id, uint256 released) public {
        (bool success, bytes memory result) = _processAddr.delegatecall(abi.encodeWithSignature("pushPledgeReleased(uint256,uint256)", id, released));
        require(success && result.length >= 0, "Ctrl: push pledge err.");
    }

    // ########################## job api end ############################

    function availableRewardOf(uint256 id, address addr) public view returns (uint256) {
        uint256 amount = 0;
        if(pledgeTotalCalcAmount[id] == 0) return 0;
        uint256 released = _getReward(id, addr, totalReleasedRewardAmount[id]);
        if(released > investorInfo[id][addr].withdrawAmount) amount = released - investorInfo[id][addr].withdrawAmount;
        return amount;
    }

    function totalRewardOf(uint256 id, address addr) public view returns (uint256) {
        uint256 reward = _getReward(id, addr, totalRewardAmount[id]);
        return reward;
    }

    function willReleaseOf(uint256 id, address addr) public view returns (uint256) {
        uint256 reward = _getReward(id, addr, totalRewardAmount[id] - totalReleasedRewardAmount[id]);
        return reward;
    }

    function _getReward(uint256 id, address addr, uint256 clacAmount) private view returns (uint256) {
        uint256 calcReturn = 0;
        if(mountOrNot[id]) {
            calcReturn = clacAmount * investorPower[id][addr] / 10**7;
            return calcReturn;
        }
        if(pledgeTotalCalcAmount[id] == 0) return 0;
        uint256 calcReward = clacAmount * (raiseInfo[id].investorShare + raiseInfo[id].spFundShare) / rateBase;
        if(sealedAmount[id] <= pledgeTotalCalcAmount[id] + opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount) {
            calcReturn = investorInfo[id][addr].pledgeCalcAmount * calcReward * raiseInfo[id].targetAmount / ((opsCalcFund[id] + raiseInfo[id].targetAmount) * pledgeTotalCalcAmount[id]);
        } else {
            calcReturn = investorInfo[id][addr].pledgeCalcAmount * calcReward * pledgeTotalCalcAmount[id] / (sealedAmount[id] * pledgeTotalCalcAmount[id]);
        }
        return calcReturn;
    }

    function getToolAddr() public pure returns (address tool, address miner, address process, address processSecond) {
        tool = _toolAddr;
        miner = _minerToolAddr;
        process = _processAddr;
        processSecond = _processSecond;
    }

}