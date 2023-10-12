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

contract LetsFilProcess is ILetsFilPackInfo {
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

    function closeRaisePlan(uint256 id) public onlyRaiser {
        require(raiseState[id] < RaiseState.Closed, "Process: state err.");

        if(raiseCloseTime[id] == 0 || block.timestamp < raiseCloseTime[id]) {
            raiseCloseTime[id] = block.timestamp;
        }

        if(mountOrNot[id]) {
            emit CloseRaisePlan(id, msg.sender, raiseCloseTime[id]);
            raiseState[id] = RaiseState.Closed;
            emit RaiseStateChange(id, raiseState[id]);
            return;
        }

        if(timedOrNot[id] && raiseState[id] == RaiseState.WaitingStart) { 
            if( block.timestamp < raiseStartTime[id] || 
                securityFundRemain[id] == 0 || 
                opsSecurityFundRemain[id] == 0 || 
                (!gotMiner) ){
                emit CloseRaisePlan(id, msg.sender, raiseCloseTime[id]);
                raiseState[id] = RaiseState.Closed;
                emit RaiseStateChange(id, raiseState[id]);
                return;
            }
        }

        if(raiseStartTime[id] != 0 && pledgeTotalAmount[id] >= raiseInfo[id].targetAmount * raiseInfo[id].minRaiseRate / rateBase) {
            if(pledgeTotalAmount[id] < raiseInfo[id].targetAmount && securityFundRemain[id] > raiseInfo[id].securityFund * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
                uint256 back_sFund = securityFundRemain[id] - raiseInfo[id].securityFund * pledgeTotalAmount[id] / raiseInfo[id].targetAmount;
                securityFundRemain[id] -= back_sFund;
                payable(raiser).transfer(back_sFund);
                emit WithdrawSecurityFund(id, msg.sender, back_sFund);
            }
            _raiseSuc(id);

            if(startSealTime[id] == 0) startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            if(sealEndTime[id] == 0) sealEndTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days + nodeInfo[id].sealDays * 1 days;

            uint256 nowToSeal = pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id];
            uint256 amount = 0;
            if(nowToSeal > toSealAmount[id]) {
                amount = nowToSeal - toSealAmount[id];
                toSealAmount[id] = nowToSeal;
                _sendToMiner(amount);
                emit SendToMiner(id, msg.sender, amount);
            }
            if(nodeState[id] == NodeState.WaitingStart) {
                if(startSealTime[id] == 0 || startSealTime[id] > raiseCloseTime[id]) startSealTime[id] = raiseCloseTime[id];
                nodeState[id] = NodeState.Started;
                emit NodeStateChange(id, nodeState[id]);
                emit StartSeal(id, msg.sender, startSealTime[id]);
            }
            emit ClosePlanToSeal(id, msg.sender, raiseCloseTime[id], toSealAmount[id]);
        } else if(raiseStartTime[id] != 0 && raiseCloseTime[id] > raiseStartTime[id]) {
            totalInterest[id] = (pledgeTotalAmount[id] * (raiseCloseTime[id] - raiseStartTime[id]) - pledgeTotalDebt[id]) * networkAnnual / (rateBase * 365 days);
            totalInterest[id] += (opsCalcFund[id] + safeSealFund[id]) * (raiseCloseTime[id] - raiseStartTime[id]) * networkAnnual / (rateBase * 365 days);
            securityFundRemain[id] -= totalInterest[id];

            emit CloseRaisePlan(id, msg.sender, raiseCloseTime[id]);
            raiseState[id] = RaiseState.Closed;
            emit RaiseStateChange(id, raiseState[id]);
        } else {
            raiseStartTime[id] = raiseCloseTime[id];

            emit CloseRaisePlan(id, msg.sender, raiseCloseTime[id]);
            raiseState[id] = RaiseState.Closed;
            emit RaiseStateChange(id, raiseState[id]);
        }
    }

    function _withdrawMinerBalance(uint256 _withdrawAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("withdrawMinerBalance(uint64,uint256)", minerId, _withdrawAmount));
        require(success && result.length >= 0, "Process: withdraw err.");
    }

    function staking(uint256 id) public payable {
        require(block.timestamp < raiseCloseTime[id], "Process: raise plan has expired.");
        require(pledgeTotalAmount[id] + msg.value <= raiseInfo[id].targetAmount, "Process: more than the number raised.");

        if(msg.value < PLEDGE_MIN_AMOUNT) {
            require(msg.value == raiseInfo[id].targetAmount - pledgeTotalAmount[id], "Process: amount is less than PLEDGE_MIN_AMOUNT");
        }

        if(privateOrNot[id]) {
            require(msg.value + investorInfo[id][msg.sender].pledgeCalcAmount <= investorMaxPledge[id][msg.sender], "Process: private plan limit.");
        }

        if(timedOrNot[id] && raiseState[id] == RaiseState.WaitingStart && block.timestamp >= raiseStartTime[id]) {
            require(securityFundRemain[id] == raiseInfo[id].securityFund && opsSecurityFundRemain[id] == nodeInfo[id].opsSecurityFund, "Ctrl: no pay securityFund.");
            require(gotMiner, "Ctrl: miner's owner is not this contract.");
            //require(sponsorNo[id] == sponsorAckNo[id], "Ctrl: not all sponsors acknowledged.");
            raiseState[id] = RaiseState.Raising;
            emit RaiseStateChange(id, raiseState[id]);
            emit StartRaisePlan(id, msg.sender, raiseStartTime[id]);
        } else {
            require(raiseState[id] == RaiseState.Raising, "Process: raiseState is not Raising.");
        }

        uint256 nowTime = block.timestamp;
        investorInfo[id][msg.sender].pledgeAmount += msg.value;
        investorInfo[id][msg.sender].pledgeCalcAmount += msg.value;
        investorInfo[id][msg.sender].interestDebt += msg.value * (nowTime - raiseStartTime[id]);
        pledgeTotalAmount[id] += msg.value;
        pledgeTotalCalcAmount[id] += msg.value;
        pledgeTotalDebt[id] += msg.value * (nowTime - raiseStartTime[id]);

        if(pledgeTotalAmount[id] == raiseInfo[id].targetAmount) {
            _raiseSuc(id);
            if(startSealTime[id] == 0) startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            if(sealEndTime[id] == 0) sealEndTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days + nodeInfo[id].sealDays * 1 days;
            if(nodeState[id] == NodeState.WaitingStart) {
                if(block.timestamp < startSealTime[id]) startSealTime[id] = block.timestamp;
                nodeState[id] = NodeState.Started;
                emit NodeStateChange(id, nodeState[id]);
                emit StartSeal(id, msg.sender, startSealTime[id]);
            }
            uint256 amount = pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id] - toSealAmount[id];
            toSealAmount[id] = pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id];
            _sendWithValue(amount);
            emit SendToMiner(id, msg.sender, amount);
        }

        emit Staking(id, msg.sender, address(this), msg.value);
    }

    function raiseExpire(uint256 id) public {
        require(raiseState[id] == RaiseState.Raising || raiseState[id] == RaiseState.Success, "raise state error");
        // require(nodeState[id] == NodeState.WaitingStart || raiseState[id] == RaiseState.Raising, "node state error");
        require(block.timestamp >= raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days, "plan is not expired");
        if(pledgeTotalAmount[id]  < raiseInfo[id].targetAmount * raiseInfo[id].minRaiseRate / rateBase) {
            totalInterest[id] = (pledgeTotalAmount[id] * raiseInfo[id].raiseDays * 1 days - pledgeTotalDebt[id]) * networkAnnual / (rateBase * 365 days);
            totalInterest[id] += (opsCalcFund[id] + safeSealFund[id]) * raiseInfo[id].raiseDays * networkAnnual / (rateBase * 365);
            securityFundRemain[id] -= totalInterest[id];
            raiseState[id] = RaiseState.Failure;
            //raiseCloseTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            emit RaiseStateChange(id, raiseState[id]);
            emit RaiseFailed(id);
        } else {
            if(startSealTime[id] == 0) startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            if(sealEndTime[id] == 0) sealEndTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days + nodeInfo[id].sealDays * 1 days;

            if(pledgeTotalAmount[id] < raiseInfo[id].targetAmount && securityFundRemain[id] > raiseInfo[id].securityFund * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
                uint256 back_sFund = securityFundRemain[id] - raiseInfo[id].securityFund * pledgeTotalAmount[id] / raiseInfo[id].targetAmount;
                securityFundRemain[id] -= back_sFund;
                payable(raiser).transfer(back_sFund);
                emit WithdrawSecurityFund(id, msg.sender, back_sFund);
            }
            if(raiseState[id] == RaiseState.Raising && pledgeTotalAmount[id] < raiseInfo[id].targetAmount) {
                // uint256 backOpsFund = nodeInfo[id].opsSecurityFund - nodeInfo[id].opsSecurityFund * pledgeTotalAmount[id] / raiseInfo[id].targetAmount;
                // opsSecurityFundRemain[id] -= backOpsFund;
                // opsCalcFund[id] -= backOpsFund;
                // payable(sp).transfer(backOpsFund);
                // emit WithdrawOpsSecurityFund(id, msg.sender, backOpsFund, 0, 0, 0);

                _raiseSuc(id);
            }
            if(nodeState[id] == NodeState.WaitingStart) {
                //if(startSealTime[id] == 0) startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
                nodeState[id] = NodeState.Started;
                emit NodeStateChange(id, nodeState[id]);
                emit StartSeal(id, msg.sender, startSealTime[id]);
            }
            if(toSealAmount[id] < pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id]) {
                uint256 amount = pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id] - toSealAmount[id];
                toSealAmount[id] = pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id];
                _sendToMiner(amount);
                emit SendToMiner(id, msg.sender, amount);
            }
        }
    }

    function _raiseSuc(uint256 id) internal {
        uint256 fee = pledgeTotalAmount[id] * feeCoeff / rateBase;
        securityFundRemain[id] -= fee;
        payable(ITools(_toolAddr).receiver()).transfer(fee);

        raiseState[id] = RaiseState.Success;
        emit RaiseStateChange(id, raiseState[id]);
        emit RaiseSuccess(id, pledgeTotalAmount[id]);
    }

    function _sendToMiner(uint256 sendAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("send(uint64,uint256)", minerId, sendAmount));
        require(success && result.length >= 0, "Process: send err.");
    }

    function _sendWithValue(uint256 sendAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("sendWithValue(uint64,uint256)", minerId, sendAmount));
        require(success && result.length >= 0, "Process: send with value err.");
    }

    //Enter the preparation period of sealing.
    function startPreSeal(uint256 id) public onlyRaiser {
        require(raiseState[id] == RaiseState.Raising, "Process: state err.");
        require(pledgeTotalAmount[id] >= raiseInfo[id].targetAmount * raiseInfo[id].minRaiseRate / rateBase, "Process: not reach the standard.");

        uint256 nowToSeal = pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id];
        require(nowToSeal > toSealAmount[id], "Process: no asset to send.");

        uint256 amount = nowToSeal - toSealAmount[id];
        toSealAmount[id] = nowToSeal;
        _sendToMiner(amount);
        emit SendToMiner(id, msg.sender, amount);

        if(nodeState[id] == NodeState.WaitingStart) {
            //startSealTime[id] = raiseStartTime[id] + raiseInfo[id].raiseDays * 1 days;
            if(block.timestamp < startSealTime[id]) startSealTime[id] = block.timestamp;
            nodeState[id] = NodeState.Started;
            emit NodeStateChange(id, nodeState[id]);
            emit StartSeal(id, msg.sender, startSealTime[id]);
        }

        emit StartPreSeal(id, msg.sender);
    }

    // ########################## job api ############################

    function pushOldAssetPackValue(uint256 id, uint256 totalPledge, uint256 released, uint256 willRelease) public onlyManager {//todo...
        require(id == extendInfo[id].oldId, "old err");
        pledgeTotalAmount[id] = totalPledge;
        pledgeTotalCalcAmount[id] = totalPledge;

        emit PushOldAssetPackValue(id, msg.sender, totalPledge, released, willRelease);
    }

    function pushFinalProgress(uint256 id, uint256 amount) public onlyManager {
        require(!progressEnd[id], "Final progress already pushed");
        require(nodeState[id] >= NodeState.Started, "state error");
        require(block.timestamp >= sealEndTime[id] + 2 days, "time err");
        if(amount > pledgeTotalCalcAmount[id] + opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount + safeSealFund[id] + safeSealedFund[id]) {
            amount = pledgeTotalCalcAmount[id] + opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount + safeSealFund[id] + safeSealedFund[id];
        }

        _pushFinalProgress(id, amount);
    }

    function _pushFinalProgress(uint256 id, uint256 amount) internal {
        require(sealedAmount[id] <= amount, "sealedAmount error");
        sealedAmount[id] = amount;
        progressEnd[id] = true;

        if(amount < pledgeTotalCalcAmount[id] + opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount) {
            fundSealed[id] = amount * opsCalcFund[id] / (opsCalcFund[id] + raiseInfo[id].targetAmount);
            if(safeSealedFund[id] > 0) {
                safeSealFund[id] += safeSealedFund[id];
                safeSealedFund[id] = 0;
            }
        } else {
            fundSealed[id] = amount - pledgeTotalCalcAmount[id];
            uint256 safeFund = safeSealFund[id] + safeSealedFund[id];
            safeSealedFund[id] = fundSealed[id] - opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount;
            safeSealFund[id] = safeFund - safeSealedFund[id];
        }

        if(nodeState[id] == NodeState.Started) {
            nodeState[id] = NodeState.End;
            emit NodeStateChange(id, nodeState[id]);
            emit SealEnd(id, amount);
        }
        if(amount < pledgeTotalAmount[id] + opsCalcFund[id] + safeSealFund[id] + safeSealedFund[id]) {
            require(fundBack[id] == 0, "already back");

            if(toSealAmount[id] > amount) _withdrawMinerBalance(toSealAmount[id] - amount);

            if(amount - fundSealed[id] < pledgeTotalAmount[id]) {
                uint256 interest = (pledgeTotalAmount[id] * (sealEndTime[id] - raiseStartTime[id]) - pledgeTotalDebt[id]) * networkAnnual / (rateBase * 365 days);
                interest = interest * (pledgeTotalAmount[id] + fundSealed[id] - amount) / pledgeTotalAmount[id];
                totalInterest[id] += interest;

                uint256 fee = securityFundRemain[id] * (pledgeTotalAmount[id] + fundSealed[id] - amount) / pledgeTotalAmount[id];
                if(fee > interest) {
                    payable(ITools(_toolAddr).receiver()).transfer(fee - interest);
                } else {
                    fee = interest;
                }
                securityFundRemain[id] -= fee;
            }

            if(amount < pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
                fundBack[id] = opsCalcFund[id] - opsCalcFund[id] * amount / (raiseInfo[id].targetAmount + opsCalcFund[id]) + safeSealFund[id];
                safeSealFund[id] = 0;
                opsSecurityFundRemain[id] = opsCalcFund[id] * amount / (raiseInfo[id].targetAmount + opsCalcFund[id]);
            } else {
                fundBack[id] = opsCalcFund[id] - opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount + safeSealFund[id];
                safeSealFund[id] = 0;
            }

            payable(sp).transfer(fundBack[id]);
            emit WithdrawOpsSecurityFund(id, msg.sender, fundBack[id], 0, 0, 0);
        }
        emit PushFinalProgress(id, amount, nodeState[id]);
    }

    function destroyNode(uint256 id) public onlyManager {
        if(mountOrNot[id]) {
            require(raiseState[id] == RaiseState.Success, "Process: state err.");
            require(pledgeTotalCalcAmount[id] <= pledgeReleased[id] + spFine[id] - subFine[id], "Process: pledge not all released.");
        } else {
            require(nodeState[id] >= NodeState.End && progressEnd[id] == true, "Process: state err.");
            require(sealedAmount[id] <= pledgeReleased[id] + spFine[id] - subFine[id], "Process: pledge not all released.");
        }

        require(totalRewardAmount[id] <= totalReleasedRewardAmount[id] + spFine[id] - subFine[id], "Process: reward not all released.");

        uint256 beforeWithdraw = address(this).balance;
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("withdrawAllBalance(uint64)", minerId));
        require(success && result.length >= 0, "Process: miner transfer err.");
        returnAmount[id] += address(this).balance - beforeWithdraw;

        spRewardLock[id] = 0;
        nodeState[id] = NodeState.Destroy;
        emit NodeStateChange(id, nodeState[id]);
        emit DestroyNode(id, nodeState[id]);
    }

    function pushSpFine(uint256 id, uint256 fineAmount) external onlyManager {
        require(nodeState[id] >= NodeState.Started || mountOrNot[id], "Controler: state error.");

        spFine[id] = fineAmount;
        if(mountOrNot[id]) {
            _pushMountSpFine(id);
        } else {
            _pushSpFine(id);
        }

        emit PushSpFine(id, fineAmount);
    }

    function _pushSpFine(uint256 id) private {
        uint256 fineRemain = spFine[id] - subFine[id] - safeFundFine[id];
        uint256 spReward = totalReleasedRewardAmount[id] * raiseInfo[id].servicerShare / rateBase - gotSpReward[id];
        if(spReward >= fineRemain) {
            spRewardFine[id] = fineRemain;
        } else if(spReward > 0) {
            spRewardFine[id] = spReward;
        } else {
            spRewardFine[id] = 0;
        }
        fineRemain -= spRewardFine[id];

        //uint256 spFundReward = totalReleasedRewardAmount[id] * raiseInfo[id].spFundShare / rateBase;
        uint256 calcReleased = totalReleasedRewardAmount[id] * (raiseInfo[id].investorShare + raiseInfo[id].spFundShare) / rateBase;
        uint256 spFundReward = 0;
        if(sealedAmount[id] <= pledgeTotalCalcAmount[id] + opsCalcFund[id] * pledgeTotalCalcAmount[id] / raiseInfo[id].targetAmount) {
            spFundReward = calcReleased * opsCalcFund[id] / (opsCalcFund[id] + raiseInfo[id].targetAmount);
        } else {
            spFundReward = calcReleased * fundSealed[id] / sealedAmount[id];
        }

        if(fineRemain > 0 && spFundReward > 0) {
            if(spFundReward >= fineRemain) {
                spFundRewardFine[id] = fineRemain;
            } else {
                spFundRewardFine[id] = spFundReward;
            }
            fineRemain -= spFundRewardFine[id];
        } else if(spFundRewardFine[id] > 0) {
            spFundRewardFine[id] = 0;
        }

        if(fineRemain > 0 && safeSealFund[id] > 0) {
            if(safeSealFund[id] >= fineRemain) {
                safeSealFund[id] -= fineRemain;
                safeFundFine[id] += fineRemain;
                fineRemain = 0;
            } else {
                fineRemain -= safeSealFund[id];
                safeFundFine[id] += safeSealFund[id];
                safeSealFund[id] = 0;
            }
        }

        if(fineRemain > 0 && opsSecurityFundRemain[id] > 0) {
            if(opsSecurityFundRemain[id] >= fineRemain) {
                spFundFine[id] = fineRemain;
            } else {
                spFundFine[id] = opsSecurityFundRemain[id];
            }
            fineRemain -= spFundFine[id];
        } else if(spFundFine[id] > 0) {
            spFundFine[id] = 0;
        }

        uint256 tCalc = pledgeTotalCalcAmount[id];
        if(pledgeTotalCalcAmount[id] > sealedAmount[id]) tCalc = sealedAmount[id];
        if(fineRemain > 0 && tCalc > 0) {
            if(tCalc >= fineRemain) {
                investorFine[id] = fineRemain;
            } else {
                investorFine[id] = tCalc;
            }
            fineRemain -= investorFine[id];
        } else if(investorFine[id] > 0) {
            investorFine[id] = 0;
        }

        spRemainFine[id] = fineRemain;
    }

    function _pushMountSpFine(uint256 id) private {
        uint256 fineRemain = spFine[id] - subFine[id];
        uint256 spReward = totalReleasedRewardAmount[id] * raiseInfo[id].servicerShare / rateBase - gotSpReward[id];
        if(spReward >= fineRemain) {
            spRewardFine[id] = fineRemain;
        } else if(spReward > 0) {
            spRewardFine[id] = spReward;
        } else {
            spRewardFine[id] = 0;
        }
        fineRemain -= spRewardFine[id];

        uint256 tCalc = pledgeTotalAmount[id];
        if(fineRemain > 0 && tCalc > 0) {
            if(tCalc >= fineRemain) {
                investorFine[id] = fineRemain;
            } else {
                investorFine[id] = tCalc;
            }
            fineRemain -= investorFine[id];
        } else if(investorFine[id] > 0) {
            investorFine[id] = 0;
        }

        spRemainFine[id] = fineRemain;
    }

    function pushPledgeReleased(uint256 id, uint256 released) external onlyManager {
        if(mountOrNot[id]) {
            require(raiseState[id] == RaiseState.Success, "Controler: state error.");
        } else{
            require(nodeState[id] >= NodeState.End || extendInfo[id].oldId == id, "Controler: state error.");
        }
        pledgeReleased[id] = released;
        if(released > pledgeTotalCalcAmount[id]) pledgeReleased[id] = pledgeTotalCalcAmount[id];

        if(nodeState[id] < NodeState.Destroy) {
            uint256 amountFromMiner = released + totalReleasedRewardAmount[id];
            if(spRewardFine[id] > spRewardLock[id]) {
                amountFromMiner -= spRewardFine[id];
            } else {
                amountFromMiner -= spRewardLock[id];
            }

            if(!mountOrNot[id]) {
                uint256 releasedFund = 0;
                if(sealedAmount[id] <= pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
                    releasedFund = released * opsCalcFund[id] / (opsCalcFund[id] + raiseInfo[id].targetAmount);
                } else {
                    releasedFund = released * fundSealed[id] / sealedAmount[id];
                }
                amountFromMiner -= releasedFund;
            }

            if(amountFromMiner > returnAmount[id]) {
                amountFromMiner -= returnAmount[id];
                uint256 beforeWithdraw = address(this).balance;
                _withdrawMinerBalance(amountFromMiner);
                returnAmount[id] += address(this).balance - beforeWithdraw;
            }
        }

        emit PushPledgeReleased(id, released);
    }

    // ########################## job api end ############################

}
