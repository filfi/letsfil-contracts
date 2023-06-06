// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/ILetsFilPackInfo.sol";

interface ITools {
    function manager() external view returns (address);
    function receiver() external view returns (address);
}

interface IFilMiner {
    function spSignWithMiner(uint64 minerId) external;
    function changeOwnerById(uint64 minerId, uint64 actorId) external;
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
    mapping(uint256 => uint256) public raiserFine;
    mapping(uint256 => uint256) public investorRewardFine;
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
    address private constant _minerToolAddr = address(0x4d3179069927537CBe8fa4803Ca0968A620B9766); //Mainnet

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
    
    bytes private rrr;
    //bytes public mOwner;

    // events
    event RaiseStateChange(uint256 indexed id, RaiseState state);
    event NodeStateChange(uint256 indexed id, NodeState state);
    event SpSignWithMiner(address indexed sp, uint64 indexed minerId, address contractAddr);
    event DepositSecurityFund(uint256 indexed id, address indexed sponsorAddr, uint256 amount);
    event DepositOpsSecurityFund(uint256 indexed id, address indexed sender, uint256 amount);
    event StartRaisePlan(uint256 indexed id, address indexed sponsorAddr, uint256 startTime);
    event CloseRaisePlan(uint256 indexed id, address indexed sponsorAddr, uint256 closeTime);
    event WithdrawSecurityFund(uint256 indexed id, address indexed caller, uint256 amount);
    event WithdrawOpsSecurityFund(uint256 indexed id, address indexed caller, uint256 amount, uint256 interest, uint256 reward, uint256 fine);
    event Staking(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);
    event RaiseSuccess(uint256 indexed raiseID, uint256 pledgeAmount);
    event RaiseFailed(uint256 indexed raiseID);
    event StartSeal(uint256 indexed id, address indexed caller, uint256 startTime);
    event StartPreSeal(uint256 indexed id, address indexed caller);
    event PushOldAssetPackValue(uint256 id, address caller, uint256 totalPledge, uint256 released, uint256 willRelease);
    event PushSealProgress(uint256 indexed id, uint256 amount, NodeState state);
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
        require(!initialized ,"RaisePlan: already initialized.");
        initialized = true;
        raiseInfo[_raiseID] = _raiseInfo;
        nodeInfo[_raiseID] = _nodeInfo;
        extendInfo[_raiseID] = _extendInfo;
        minerId = _nodeInfo.minerId;
        raiser = _raiseInfo.sponsor;
        sp = _nodeInfo.spAddr;
        raiseState[_raiseID] = RaiseState.WaitingStart;
    }

    fallback() external payable {}
    receive() external payable {}

    modifier onlyManager() {
        require(msg.sender == ITools(_toolAddr).manager() ,"RaisePlan: not manager");
        _;
    }

    modifier onlyRaiser() {
        require(msg.sender == raiser ,"RaisePlan: not raiser.");
        _;
    }

    modifier onlySp() {
        require(msg.sender == sp ,"RaisePlan: not service provider.");
        _;
    }

    function spSignWithMiner() public onlySp {
        //Verify that the node owner is this contract address
        //IFilMiner(_minerToolAddr).spSignWithMiner(minerId);
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("spSignWithMiner(uint64)", minerId));
        require(success, "Controler: sign err.");

        rrr = result;
        gotMiner = true;
        emit SpSignWithMiner(msg.sender, minerId, address(this));

        // 变更受益人为合约 getBeneficiary   changeBeneficiary
    }

    function paySecurityFund(uint256 id) public payable onlyRaiser {
        require(raiseState[id] == RaiseState.WaitingStart, "RaisePlan: raising is already started.");
        //raiseStates
        require(msg.value == raiseInfo[id].securityFund && securityFundRemain[id] == 0, "RaisePlan: value incorrect.");

        securityFundRemain[id] = msg.value;
        emit DepositSecurityFund(id, msg.sender, msg.value);
    }

    //pay second ops security fund
    function payOpsSecurityFund(uint256 id) public payable onlySp {
        require(raiseState[id] == RaiseState.WaitingStart, "RaisePlan: raising is already started.");
        require(msg.value == nodeInfo[id].opsSecurityFund && opsSecurityFundRemain[id] == 0, "RaisePlan: value incorrect");

        opsSecurityFundRemain[id] = msg.value;
        opsCalcFund[id] = msg.value;

        emit DepositOpsSecurityFund(id, msg.sender, msg.value);
    }

    function startRaisePlan(uint256 id) public onlyRaiser {
        require(raiseState[id] == RaiseState.WaitingStart, "RaisePlan: raising is already started.");
        require(securityFundRemain[id] == raiseInfo[id].securityFund && opsSecurityFundRemain[id] == nodeInfo[id].opsSecurityFund, "RaisePlan: no pay securityFund.");
        require(gotMiner, "RaisePlan: miner's owner is not this contract.");

        raiseState[id] = RaiseState.Raising;
        raiseStartTime[id] = block.timestamp;
        emit RaiseStateChange(id, raiseState[id]);
        emit StartRaisePlan(id, msg.sender, raiseStartTime[id]);
    }

    //todo...
    // function changeOwner(CommonTypes.FilActorId _minerId, uint64 _actorId) public onlySp {
    //     //all plans is closed. or all token(include reward) is back
    //     require(raiseState == RaiseState.Closed || raiseState == RaiseState.Failure || (nodeState == NodeState.Destroy && true), "...");
    //     MinerAPI.changeOwnerAddress(_minerId, FilAddresses.fromActorID(_actorId));
    // }

    // only ForTest
    function changeOwnerById(uint64 _minerId, uint64 _actorId) public onlySp {
        //require(msg.sender == sp || msg.sender == raiser || msg.sender == ITools(_toolAddr).manager(), "Not server signer");
        //IFilMiner(_minerToolAddr).changeOwnerById(_minerId, _actorId);
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("changeOwnerById(uint64,uint64)", _minerId, _actorId));
        if(success) {
            rrr = result;
        }
    }

    // // // only ForTest
    // function backOwner(uint64 _minerId) public {
    //     //require(msg.sender == sp || msg.sender == raiser || msg.sender == ITools(_toolAddr).manager(), "Not server signer");
    //     (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("backOwner(uint64,bytes memory)", _minerId, mOwner));
    //     if(success) {
    //         rrr = result;
    //     }
    // }

    // only ForTest
    // function withdrawMinerBalanceTest(uint64 _minerId) public {
    //     (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("getBalance(uint64)", _minerId));
    //     if(success) {
    //         rrr = result;
    //     }
    // }

    // only ForTest
    // function setTime(uint256 id, uint256 _raiseStartTime, uint256 _startSealTime) public {
    //     raiseStartTime[id] = _raiseStartTime;
    //     startSealTime[id] = _startSealTime;
    // }

    function closeRaisePlan(uint256 id) public onlyRaiser {
        require(raiseState[id] < RaiseState.Closed, "RaisePlan: raiseState error.");
        raiseState[id] = RaiseState.Closed;

        raiseCloseTime[id] = block.timestamp;
        if(raiseStartTime[id] > 0 && raiseCloseTime[id] > raiseStartTime[id]) {
            totalInterest[id] = (pledgeTotalAmount[id] * (raiseCloseTime[id] - raiseStartTime[id]) - pledgeTotalDebt[id]) * networkAnnual / (rateBase * 365 days);
            totalInterest[id] += opsSecurityFundRemain[id] * (raiseCloseTime[id] - raiseStartTime[id]) * networkAnnual / (rateBase * 365 days);
            securityFundRemain[id] -= totalInterest[id];
        }
        emit RaiseStateChange(id, raiseState[id]);
        emit CloseRaisePlan(id, msg.sender, raiseCloseTime[id]);
    }

    function withdrawSecurityFund(uint256 id) public onlyRaiser {
        require(securityFundRemain[id] > 0, "RaisePlan: securityFund is null.");
        require(raiseState[id] == RaiseState.Closed || raiseState[id] == RaiseState.Failure || nodeState[id] >= NodeState.End, "RaisePlan: plan or node state error.");

        uint256 transAmount = securityFundRemain[id];
        securityFundRemain[id] = 0;
        payable(msg.sender).transfer(transAmount);
        emit WithdrawSecurityFund(id, msg.sender, transAmount);
    }

    function withdrawOpsSecurityFund(uint256 id) public onlySp {
        require(opsSecurityFundRemain[id] > 0, "opsSecurityFund Insufficient balance");
        //Closing, failure, and node runtime expiration can all be extracted.  or all token(include reward) is back
        require(raiseState[id] == RaiseState.Closed || raiseState[id] == RaiseState.Failure || nodeState[id] == NodeState.Destroy, "Controler: plan or node state error.");

        uint256 interest = 0;
        if(raiseState[id] == RaiseState.Closed && totalInterest[id] > 0) {
            interest = opsCalcFund[id] * (raiseCloseTime[id] - raiseStartTime[id]) * networkAnnual / (rateBase * 365 days);
        } else if(raiseState[id] == RaiseState.Failure) {
            interest = opsCalcFund[id] * raiseInfo[id].raiseDays * networkAnnual / (rateBase * 365);
        }

        uint256 reward = totalRewardAmount[id] * raiseInfo[id].spFundShare / rateBase;
        uint256 transAmount = opsSecurityFundRemain[id] + interest + reward - spFundFine[id];

        // if(transAmount > address(this).balance && nodeState[id] == NodeState.Destroy) {
        //     uint256 amountFromMiner = pledgeTotalCalcAmount[id] + totalReleasedRewardAmount[id] - returnAmount[id];// 
        //     if(amountFromMiner > 0) {
        //         uint256 beforeWithdraw = address(this).balance;
        //         _withdrawMinerBalance(amountFromMiner);
        //         returnAmount[id] += address(this).balance - beforeWithdraw;
        //     }
        // }

        // if(raiseState[id] == RaiseState.Closed) {
        //     amountBack = investorInfo[id][account].pledgeAmount;
        //     uint256 interestBack = (investorInfo[id][account].pledgeAmount * (raiseCloseTime[id] - raiseStartTime[id]) - investorInfo[id][account].interestDebt) * networkAnnual / (rateBase * 365 days);
        //     return(amountBack, interestBack);
        // }

        //if(transAmount > address(this).balance) transAmount = address(this).balance;

        payable(msg.sender).transfer(transAmount);

        emit WithdrawOpsSecurityFund(id, msg.sender, opsSecurityFundRemain[id], interest, reward, spFundFine[id]);
        opsSecurityFundRemain[id] = 0;
    }

    function _withdrawMinerBalance(uint256 _withdrawAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("withdrawMinerBalance(uint64,uint256)", minerId, _withdrawAmount));
        if(success) {
            rrr = result;
        }
    }

    function staking(uint256 id) public payable {
        require(block.timestamp < raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days, "Raise plan has expired");
        require(pledgeTotalAmount[id] + msg.value <= raiseInfo[id].targetAmount, "More than the number raised");
        require(raiseState[id] == RaiseState.Raising, "raiseState is not Raising");

        if(msg.value < PLEDGE_MIN_AMOUNT) {
            require(msg.value == raiseInfo[id].targetAmount - pledgeTotalAmount[id], "staking amount is less than PLEDGE_MIN_AMOUNT");
        }

        uint256 nowTime = block.timestamp;
        investorInfo[id][msg.sender].pledgeAmount += msg.value;
        investorInfo[id][msg.sender].pledgeCalcAmount += msg.value;
        investorInfo[id][msg.sender].interestDebt += msg.value * (nowTime - raiseStartTime[id]);
        pledgeTotalAmount[id] += msg.value;
        pledgeTotalCalcAmount[id] += msg.value;
        pledgeTotalDebt[id] += msg.value * (nowTime - raiseStartTime[id]);

        if(pledgeTotalAmount[id] == raiseInfo[id].targetAmount) {
            uint256 fee = pledgeTotalAmount[id] * feeCoeff / rateBase;
            securityFundRemain[id] -= fee;
            payable(ITools(_toolAddr).receiver()).transfer(fee);

            raiseState[id] = RaiseState.Success;
            emit RaiseSuccess(id, pledgeTotalAmount[id]);
        }

        emit Staking(id, msg.sender, address(this), msg.value);
    }

    function raiseExpire(uint256 id) public {
        require(raiseState[id] == RaiseState.Raising || raiseState[id] == RaiseState.Success, "raise state error");
        require(nodeState[id] == NodeState.WaitingStart, "node state error");
        require(block.timestamp >= raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days, "plan is not expired");
        if(pledgeTotalAmount[id]  < raiseInfo[id].targetAmount * raiseInfo[id].minRaiseRate / rateBase) {
            totalInterest[id] = (pledgeTotalAmount[id] * raiseInfo[id].raiseDays * 1 days - pledgeTotalDebt[id]) * networkAnnual / (rateBase * 365 days);
            totalInterest[id] += opsCalcFund[id] * raiseInfo[id].raiseDays * networkAnnual / (rateBase * 365);
            securityFundRemain[id] -= totalInterest[id];
            raiseState[id] = RaiseState.Failure;
            raiseCloseTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            emit RaiseStateChange(id, raiseState[id]);
            emit RaiseFailed(id);
        } else {
            if(pledgeTotalAmount[id] < raiseInfo[id].targetAmount) {
                uint256 backOpsFund = nodeInfo[id].opsSecurityFund - nodeInfo[id].opsSecurityFund * pledgeTotalAmount[id] / raiseInfo[id].targetAmount;
                opsSecurityFundRemain[id] -= backOpsFund;
                opsCalcFund[id] -= backOpsFund;
                payable(sp).transfer(backOpsFund);
                emit WithdrawOpsSecurityFund(id, msg.sender, backOpsFund, 0, 0, 0);

                uint256 fee = pledgeTotalAmount[id] * feeCoeff / rateBase;
                securityFundRemain[id] -= fee;
                payable(ITools(_toolAddr).receiver()).transfer(fee);

                raiseState[id] = RaiseState.Success;
                emit RaiseStateChange(id, raiseState[id]);
                emit RaiseSuccess(id, pledgeTotalAmount[id]);
            }
            startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            nodeState[id] = NodeState.Started;

            if(toSealAmount[id] == 0) {
                toSealAmount[id] = pledgeTotalAmount[id] + opsCalcFund[id];
                _sendToMiner(toSealAmount[id]);
            }

            emit NodeStateChange(id, nodeState[id]);
            emit StartSeal(id, msg.sender, startSealTime[id]);
        }
    }

    function _sendToMiner(uint256 sendAmount) internal {
        //uint256 beforeSend = address(this).balance;
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("send(uint64,uint256)", minerId, sendAmount));
        require(success, "Controler: send err.");
        rrr = result;
        //require(beforeSend - address(this).balance == sendAmount, "Controler: send failure.");
    }

    //Enter the preparation period of sealing.
    function startPreSeal(uint256 id) public onlyRaiser {
        require(raiseState[id] == RaiseState.Success && toSealAmount[id] == 0, "state error");
        // uint256 nowTime = block.timestamp;
        // if(nowTime <= raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days) {
        //     startSealTime[id] = nowTime;
        // } else {
        //     startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
        // }
 
        //nodeState[id] = NodeState.Started;

        toSealAmount[id] = pledgeTotalAmount[id] + opsCalcFund[id];
        _sendToMiner(toSealAmount[id]);

        //emit NodeStateChange(id, nodeState[id]);
        emit StartPreSeal(id, msg.sender);
    }

    function getBack(uint256 id, address account) public view returns (uint256, uint256) {
        uint256 pledge = investorInfo[id][account].pledgeAmount;
        uint256 calc = investorInfo[id][account].pledgeCalcAmount;
        uint256 tCalc = pledgeTotalCalcAmount[id];
        uint256 amountBack = 0;
        uint256 interestBack = 0;
        // if(id == extendInfo[id].oldId) {
        //     amountBack = pledge - calc * (tCalc - pledgeReleased[id]) / tCalc;
        //     return(amountBack, interestBack);
        // }
        if(raiseState[id] == RaiseState.Closed || raiseState[id] == RaiseState.Failure) {
            amountBack = pledge;
            if(raiseCloseTime[id] > raiseStartTime[id] && pledge * (raiseCloseTime[id] - raiseStartTime[id]) > investorInfo[id][account].interestDebt) {
                interestBack = (pledge * (raiseCloseTime[id] - raiseStartTime[id]) - investorInfo[id][account].interestDebt) * networkAnnual / (rateBase * 365 days);
            }
            return(amountBack, interestBack);
        }

        uint256 freeCalc = pledgeReleased[id];
        if(nodeState[id] >= NodeState.End && sealedAmount[id] < tCalc) {
            if(pledge > calc * sealedAmount[id] / tCalc) {
                amountBack = pledge - calc * sealedAmount[id] / tCalc;
                if(sealedAmount[id] < tCalc * sealMinCoeff / rateBase) { //no delay period
                    interestBack = amountBack * networkAnnual * fineCoeff * nodeInfo[id].sealDays / (rateBase * rateBase * 365);
                } else { //calculate with delay period
                    interestBack = amountBack * networkAnnual * fineCoeff * nodeInfo[id].sealDays * (rateBase + sealDelayCoeff) / (rateBase * rateBase * rateBase * 365);
                    interestBack += amountBack * protocolSealFineCoeff * nodeInfo[id].sealDays * sealDelayCoeff / (rateBase * rateBase);
                }
            }
            if(freeCalc > 0) {
                if(freeCalc > sealedAmount[id]) freeCalc = sealedAmount[id];
                if(sealedAmount[id] - freeCalc > investorFine[id] && pledge > calc * (sealedAmount[id] - freeCalc) / tCalc) {
                    amountBack = pledge - calc * (sealedAmount[id] - freeCalc) / tCalc;
                } else if(sealedAmount[id] > investorFine[id] && pledge > calc * investorFine[id] / tCalc) {
                    amountBack = pledge - calc * investorFine[id] / tCalc;
                }
            }
        } else if(freeCalc > 0 && nodeState[id] >= NodeState.End) {
            if(freeCalc > tCalc) freeCalc = tCalc;
            if(tCalc - freeCalc > investorFine[id] && pledge > calc * (tCalc - freeCalc) / tCalc) {
                amountBack = pledge - calc * (tCalc - freeCalc) / tCalc;
            } else if(tCalc > investorFine[id] && pledge > calc * investorFine[id] / tCalc) {
                amountBack = pledge - calc * investorFine[id] / tCalc;
            }
        }
        return(amountBack, interestBack);
    }

    function unStaking(uint256 id) public {
        (uint256 backAmount, uint256 backInterest) = getBack(id, msg.sender);
        require(backAmount + backInterest > 0, "Controler: no asset.");

        investorInfo[id][msg.sender].pledgeAmount -= backAmount;
        pledgeTotalAmount[id] -= backAmount;

        payable(msg.sender).transfer(backAmount + backInterest);

        emit Unstaking(id, address(this), msg.sender, backAmount, backInterest);
    }

    // investor withdraw reward
    function investorWithdraw(uint256 id) public {
        require(nodeState[id] > NodeState.WaitingStart, "RaisePlan: nodeState error.");
        uint256 _amount = availableRewardOf(id, msg.sender);
        require(_amount > 0, "RaisePlan: param error.");

        investorInfo[id][msg.sender].withdrawAmount += _amount;

        // if(address(this).balance < _amount) {
        //     uint256 amountFromMiner = totalReleasedRewardAmount[id] + pledgeReleased[id] - returnAmount[id];
        //     uint256 beforeWithdraw = address(this).balance;
        //     _withdrawMinerBalance(amountFromMiner);
        //     returnAmount[id] += address(this).balance - beforeWithdraw;
        // }
        payable(msg.sender).transfer(_amount);

        emit InvestorWithdraw(id, address(this), msg.sender, _amount);
    }

    // raiser withdraw reward
    function raiserWithdraw(uint256 id) public onlyRaiser {
        uint256 _amount = raiserRewardAvailableLeft(id);
        require(_amount > 0, "RaisePlan: param error.");
        require(nodeState[id] > NodeState.WaitingStart, "RaisePlan: nodeState error.");

        gotRaiserReward[id] += _amount;
        // if(address(this).balance < _amount) {
        //     uint256 amountFromMiner = totalReleasedRewardAmount[id] + pledgeReleased[id] - returnAmount[id];
        //     uint256 beforeWithdraw = address(this).balance;
        //     _withdrawMinerBalance(amountFromMiner);
        //     returnAmount[id] += address(this).balance - beforeWithdraw;
        // }
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
        require(nodeState[id] > NodeState.WaitingStart, "RaisePlan: nodeState error.");

        gotSpReward[id] += _amount;
        // if(address(this).balance < _amount) {
        //     uint256 amountFromMiner = totalReleasedRewardAmount[id] + pledgeReleased[id] - returnAmount[id];
        //     uint256 beforeWithdraw = address(this).balance;
        //     _withdrawMinerBalance(amountFromMiner);
        //     returnAmount[id] += address(this).balance - beforeWithdraw;
        // }
        payable(msg.sender).transfer(_amount);

        emit SpWithdraw(id, address(this), msg.sender, _amount);
    }

    function spWillReleaseReward(uint256 id) public view returns (uint256) {
        return (totalRewardAmount[id] - totalReleasedRewardAmount[id]) * raiseInfo[id].servicerShare / rateBase;
    }

    function spRewardAvailableLeft(uint256 id) public view returns (uint256 amountReturn) {
        amountReturn = 0;
        uint256 totalReward = totalReleasedRewardAmount[id] * raiseInfo[id].servicerShare / rateBase;
        //if(nodeState[id] < NodeState.Destroy) {
        if(totalReward > spRewardLock[id] + gotSpReward[id] + spRewardFine[id]) {
            amountReturn = totalReward - spRewardLock[id] - gotSpReward[id] - spRewardFine[id];
        }
        //}
    }

    // ########################## job api ############################

    function pushOldAssetPackValue(uint256 id, uint256 totalPledge, uint256 released, uint256 willRelease) public onlyManager {//todo...
        require(id == extendInfo[id].oldId, "old err");
        pledgeTotalAmount[id] = totalPledge;
        pledgeTotalCalcAmount[id] = totalPledge;

        emit PushOldAssetPackValue(id, msg.sender, totalPledge, released, willRelease);
    }

    // judge node's current state :
    // sealing: less 50% => End; greater 50% => Delay; greater 100% => End
    function pushSealProgress(uint256 id, uint256 amount) public {
        require(nodeState[id] == NodeState.Started || nodeState[id] == NodeState.Delayed, "state error");
        // if(amount == 0) {
        //     require(block.timestamp >= startSealTime[id] + nodeInfo[id].sealDays * 1 days * (1 + sealDelayCoeff / rateBase), "time error");
        //     sealEndTime[id] = block.timestamp;
        //     nodeState[id] = NodeState.End;
        //     emit NodeStateChange(id, nodeState[id]);
        //     emit SealEnd(id, amount);
        // } else {
        //     _pushSealProgress(id, amount);
        // }
        _pushSealProgress(id, amount);

        if(nodeState[id] == NodeState.End && amount < pledgeTotalAmount[id]) {
            uint256 backOpsFund = opsCalcFund[id] - opsCalcFund[id] * amount / pledgeTotalAmount[id];
            opsSecurityFundRemain[id] -= backOpsFund;
            payable(sp).transfer(backOpsFund);
            emit WithdrawOpsSecurityFund(id, msg.sender, backOpsFund, 0, 0, 0);
        }
    }

    function _pushSealProgress(uint256 id, uint256 amount) internal onlyManager {
        require(sealedAmount[id] <= amount, "sealedAmount error");
        sealedAmount[id] = amount;

        uint256 nowTime = block.timestamp;
        uint256 latestTime = startSealTime[id] + nodeInfo[id].sealDays * 1 days * (1 + sealDelayCoeff / rateBase);
        if (amount >= pledgeTotalCalcAmount[id]) {
            if(nowTime < latestTime) latestTime = nowTime;
            sealEndTime[id] = latestTime;
            nodeState[id] = NodeState.End;
            emit NodeStateChange(id, nodeState[id]);
            emit SealEnd(id, amount);
        } else if(nodeState[id] == NodeState.Started) {
            if(nowTime >= startSealTime[id] + nodeInfo[id].sealDays * 1 days) {
                if(amount < pledgeTotalCalcAmount[id] * sealMinCoeff / rateBase) {
                    _withdrawMinerBalance(toSealAmount[id] - toSealAmount[id] * amount / pledgeTotalCalcAmount[id]);

                    uint256 interest = (pledgeTotalCalcAmount[id] - amount) * networkAnnual * fineCoeff * nodeInfo[id].sealDays / (rateBase * rateBase * 365);
                    totalInterest[id] += interest;
                    securityFundRemain[id] -= interest;

                    sealEndTime[id] = startSealTime[id] + nodeInfo[id].sealDays * 1 days;
                    nodeState[id] = NodeState.End;
                    emit NodeStateChange(id, nodeState[id]);
                    emit SealEnd(id, amount);
                } else {
                    nodeState[id] = NodeState.Delayed;
                    emit NodeStateChange(id, nodeState[id]);
                }
            }
        } else {
            if(nowTime >= latestTime) {
                if(amount < pledgeTotalCalcAmount[id]) {
                    _withdrawMinerBalance(toSealAmount[id] - toSealAmount[id] * amount / pledgeTotalCalcAmount[id]);
                    uint256 interest = (pledgeTotalCalcAmount[id] - amount) * networkAnnual * fineCoeff * nodeInfo[id].sealDays * (rateBase + sealDelayCoeff) / (rateBase * rateBase * rateBase * 365);
                    interest += (pledgeTotalCalcAmount[id] - amount) * protocolSealFineCoeff * nodeInfo[id].sealDays * sealDelayCoeff / (rateBase * rateBase);
                    totalInterest[id] += interest;
                    securityFundRemain[id] -= interest;
                }
                sealEndTime[id] = latestTime;
                nodeState[id] = NodeState.End;
                emit NodeStateChange(id, nodeState[id]);
                emit SealEnd(id, amount);
            }
        }

        emit PushSealProgress(id, amount, nodeState[id]);
    }

    function destroyNode(uint256 id) public onlyManager {
        require(nodeState[id] >= NodeState.End, "RaisePlan: can destroy node only when after ending.");

        uint256 beforeWithdraw = address(this).balance;
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("getBalance(uint64)", minerId));
        if(success) {
            rrr = result;
        }
        returnAmount[id] += address(this).balance - beforeWithdraw;

        spRewardLock[id] = 0;
        nodeState[id] = NodeState.Destroy;
        emit NodeStateChange(id, nodeState[id]);
        emit DestroyNode(id, nodeState[id]);
    }

    function pushBlockReward(uint256 id, uint256 released, uint256 willRelease) external onlyManager {
        require(released > 0 && willRelease >= 0, "RaisePlan: param error.");
        totalRewardAmount[id] = released + willRelease;
        totalReleasedRewardAmount[id] = released;

        if(totalReleasedRewardAmount[id] + pledgeReleased[id] > returnAmount[id]) {
            uint256 amountFromMiner = totalReleasedRewardAmount[id] + pledgeReleased[id] - returnAmount[id];
            uint256 beforeWithdraw = address(this).balance;
            _withdrawMinerBalance(amountFromMiner);
            returnAmount[id] += address(this).balance - beforeWithdraw;
        }

        if(extendInfo[id].oldId != id) {
            if(nodeState[id] == NodeState.Destroy) {
                spRewardLock[id] = 0;
            } else if(sealEndTime[id] == 0 || block.timestamp < sealEndTime[id] + 30 days) {
                spRewardLock[id] = totalRewardAmount[id] * raiseInfo[id].servicerShare / rateBase;
            }
            uint256 transAmount = released * raiseInfo[id].filFiShare / rateBase - gotFilFiReward[id];
            if(transAmount > 0 && transAmount <= address(this).balance) {
                payable(ITools(_toolAddr).receiver()).transfer(transAmount);
                gotFilFiReward[id] += transAmount;
            }
        }

        emit PushBlockReward(id, released, willRelease);
    }

    //罚金推送 manager 总罚金的数量
    function pushSpFine(uint256 id, uint256 fineAmount) external onlyManager {
        require(nodeState[id] >= NodeState.Started || extendInfo[id].oldId == id, "Controler: state error.");

        spFine[id] = fineAmount;
        uint256 fineRemain = fineAmount;
        uint256 spReward = totalRewardAmount[id] * raiseInfo[id].servicerShare / rateBase - gotSpReward[id];
        if(spReward >= spFine[id]) {
            spRewardFine[id] = spFine[id];
        } else if(spReward > 0) {
            spRewardFine[id] = spReward;
        }
        fineRemain -= spRewardFine[id];

        uint256 _spFundAndReward = opsSecurityFundRemain[id] + totalRewardAmount[id] * raiseInfo[id].spFundShare / rateBase;
        if(fineRemain > 0 && _spFundAndReward > 0) {
            if(_spFundAndReward >= fineRemain) {
                spFundFine[id] = fineRemain;
            } else {
                spFundFine[id] = _spFundAndReward;
            }
            fineRemain -= spFundFine[id];
        }

        // uint256 raiserReward = totalRewardAmount[id] * raiseInfo[id].raiserShare / rateBase - gotRaiserReward[id];
        // if(fineRemain > 0 && raiserReward > 0) {
        //     if(raiserReward >= fineRemain) {
        //         raiserFine[id] = fineRemain;
        //     } else {
        //         raiserFine[id] = raiserReward;
        //     }
        //     fineRemain -= raiserFine[id];
        // }

        // uint256 filFiReward = totalRewardAmount[id] * raiseInfo[id].filFiShare / rateBase - gotFilFiReward[id];
        // if(fineRemain > 0 && filFiReward > 0) {
        //     if(filFiReward >= fineRemain) {
        //         gotFilFiReward[id] += fineRemain;
        //         fineRemain = 0;
        //     } else {
        //         gotFilFiReward[id] += filFiReward;
        //         fineRemain -= filFiReward;
        //     }
        // }

        uint256 tCalc = pledgeTotalCalcAmount[id];
        if(pledgeTotalCalcAmount[id] > sealedAmount[id]) tCalc = sealedAmount[id];
        if(fineRemain > 0 && tCalc > 0) {
            if(tCalc >= fineRemain) {
                investorFine[id] = fineRemain;
            } else {
                investorFine[id] = tCalc;
            }
            fineRemain -= investorFine[id];
        }

        spRemainFine[id] = fineRemain;

        emit PushSpFine(id, fineAmount);
    }

    //质押币释放推送 manager
    function pushPledgeReleased(uint256 id, uint256 released) external onlyManager {
        require(nodeState[id] >= NodeState.End || extendInfo[id].oldId == id, "Controler: state error.");
        pledgeReleased[id] = released;

        emit PushPledgeReleased(id, released);
    }

    // ########################## job api end ############################

    function availableRewardOf(uint256 id, address addr) public view returns (uint256) {
        if(pledgeTotalCalcAmount[id] == 0) return 0;
        return investorInfo[id][addr].pledgeCalcAmount * totalReleasedRewardAmount[id] * raiseInfo[id].investorShare / (pledgeTotalCalcAmount[id] * rateBase) - investorInfo[id][addr].withdrawAmount;
    }

    function totalRewardOf(uint256 id, address addr) public view returns (uint256) {
        if(pledgeTotalCalcAmount[id] == 0) return 0;
        return investorInfo[id][addr].pledgeCalcAmount * totalRewardAmount[id] * raiseInfo[id].investorShare / (pledgeTotalCalcAmount[id] * rateBase) ;
    }

    function willReleaseOf(uint256 id, address addr) public view returns (uint256) {
        if(pledgeTotalCalcAmount[id] == 0) return 0;
        return investorInfo[id][addr].pledgeCalcAmount  * ((totalRewardAmount[id] - totalReleasedRewardAmount[id]) * raiseInfo[id].investorShare) / (pledgeTotalCalcAmount[id] * rateBase);
    }

}
