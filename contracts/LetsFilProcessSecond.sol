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

contract LetsFilProcessSecond is ILetsFilPackInfo {
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
    event SponsorWithdraw(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);
    event SpWithdraw(uint256 indexed raiseID, address indexed from, address indexed to, uint256 amount);
    event SponsorSign(uint256 indexed id, address sponsorAddr);
    event InvestorSign(uint256 indexed id, address sponsorAddr);
    event PushPledgeAmount(uint256 indexed id, uint256 amount);
    event MountSuccess(uint256 indexed id, uint256 pledgeAmount);
    event MountFailed(uint256 indexed id);
    event PushRaiserPenalty(uint256 indexed id, uint256 amount);

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

    function _withdrawMinerBalance(uint256 _withdrawAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("withdrawMinerBalance(uint64,uint256)", minerId, _withdrawAmount));
        require(success && result.length >= 0, "Process: withdraw err.");
    }

    function _sendToMiner(uint256 sendAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("send(uint64,uint256)", minerId, sendAmount));
        require(success && result.length >= 0, "Process: send err.");
    }

    function _sendWithValue(uint256 sendAmount) internal {
        (bool success, bytes memory result) = _minerToolAddr.delegatecall(abi.encodeWithSignature("sendWithValue(uint64,uint256)", minerId, sendAmount));
        require(success && result.length >= 0, "Process: send with value err.");
    }


    function createPlan( uint256 id, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                         address[] memory sponsorList, uint256[] memory sponsorPPL,
                         uint256 startTime
                       ) public {
        require(!initialized, "ProcessS: already initialized.");
        initialized = true;

        raiseInfo[id] = _raiseInfo;
        nodeInfo[id] = _nodeInfo;

        minerId = _nodeInfo.minerId;
        raiser = _raiseInfo.sponsor;
        sp = _nodeInfo.spAddr;

        secPack[1] = id;
        if(startTime > 0) {
            timedOrNot[id] = true;

            raiseStartTime[id] = startTime;
            raiseCloseTime[id] = startTime + raiseInfo[id].raiseDays * 1 days;
            startSealTime[id] = startTime + raiseInfo[id].raiseDays * 1 days;
            sealEndTime[id] = startTime + raiseInfo[id].raiseDays * 1 days + nodeInfo[id].sealDays * 1 days;
        }

        require(sponsorList.length == sponsorPPL.length, "ProcessS: sponsor list err.");

        uint256 sponsorTotalPower = _raiseInfo.raiserShare * 1000;
        sponsorNo[id] = sponsorList.length;
        for(uint256 i = 0; i < sponsorList.length; i++) {
            require(sponsorPPL[i] > 0, "ProcessS: power proportion is 0.");
            address addr = sponsorList[i];
            sponsorPower[id][addr] = sponsorPPL[i];
            sponsorTotalPower -= sponsorPPL[i];
            if(raiser == addr) {
                sponsorAck[id][raiser] = true;
                sponsorAckNo[id] = 1;
            }
        }
        require(sponsorTotalPower == 0, "ProcessS: sponsor power err when create plan.");
    }

    function createPrivatePlan( uint256 id, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                                address[] memory sponsorList, uint256[] memory sponsorPPL,
                                address[] memory investorList, uint256[] memory maxPledge,
                                uint256 startTime
                              ) public {
        require(!initialized, "ProcessS: already initialized.");
        initialized = true;

        raiseInfo[id] = _raiseInfo;
        nodeInfo[id] = _nodeInfo;

        minerId = _nodeInfo.minerId;
        raiser = _raiseInfo.sponsor;
        sp = _nodeInfo.spAddr;

        secPack[1] = id;
        privateOrNot[id] = true;
        if(startTime > 0) {
            timedOrNot[id] = true;

            raiseStartTime[id] = startTime;
            raiseCloseTime[id] = startTime + raiseInfo[id].raiseDays * 1 days;
            startSealTime[id] = startTime + raiseInfo[id].raiseDays * 1 days;
            sealEndTime[id] = startTime + raiseInfo[id].raiseDays * 1 days + nodeInfo[id].sealDays * 1 days;
        }

        require(sponsorList.length == sponsorPPL.length, "ProcessS: sponsor list err.");
        require(investorList.length == maxPledge.length, "ProcessS: investor list err.");

        uint256 sponsorTotalPower = _raiseInfo.raiserShare * 1000;
        sponsorNo[id] = sponsorList.length;
        for(uint256 i = 0; i < sponsorList.length; i++) {
            require(sponsorPPL[i] > 0, "ProcessS: power proportion is 0.");
            address addr = sponsorList[i];
            sponsorPower[id][addr] = sponsorPPL[i];
            sponsorTotalPower -= sponsorPPL[i];
            if(raiser == addr) {
                sponsorAck[id][raiser] = true;
                sponsorAckNo[id] = 1;
            }
        }
        require(sponsorTotalPower == 0, "ProcessS: sponsor power err when create plan.");

        for(uint256 i = 0; i < investorList.length; i++) {
            address addr = investorList[i];

            if(maxPledge[i] == 0) {
                investorMaxPledge[id][addr] = 10**36;
            } else {
                investorMaxPledge[id][addr] = maxPledge[i];
            }
        }
    }

    //sponsorPPL: sponsor power proportion list
    //investorPL: investor pledge list
    //investorPPL: investor power proportion list
    function mountNode( uint256 id, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                        address[] memory sponsorList, uint256[] memory sponsorPPL,
                        address[] memory investorList, uint256[] memory investorPL, uint256[] memory investorPPL,
                        uint256 totalPledge
                      ) public {
        require(!initialized, "ProcessS: already initialized.");
        initialized = true;

        raiseInfo[id] = _raiseInfo;
        nodeInfo[id] = _nodeInfo;

        minerId = _nodeInfo.minerId;
        raiser = _raiseInfo.sponsor;
        sp = _nodeInfo.spAddr;

        secPack[1] = id;
        mountOrNot[id] = true;

        require(sponsorList.length == sponsorPPL.length, "ProcessS: sponsor list err.");
        require( investorList.length == investorPL.length &&
                 investorList.length == investorPPL.length, "ProcessS: investor list err.");

        uint256 sponsorTotalPower = _raiseInfo.raiserShare * 1000;
        sponsorNo[id] = sponsorList.length;
        for(uint256 i = 0; i < sponsorList.length; i++) {
            address addr = sponsorList[i];
            sponsorPower[id][addr] = sponsorPPL[i];
            sponsorTotalPower -= sponsorPPL[i];
            if(raiser == addr) {
                sponsorAck[id][raiser] = true;
                sponsorAckNo[id] = 1;
            }
        }
        require(sponsorTotalPower == 0, "ProcessS: sponsor power err when mount node.");

        uint256 investorTotalPower = _raiseInfo.investorShare * 1000;
        investorNo[id] = investorList.length;
        for(uint256 i = 0; i < investorList.length; i++) {
            address addr = investorList[i];
            investorPower[id][addr] = investorPPL[i];
            investorTotalPower -= investorPPL[i];

            investorInfo[id][addr].pledgeAmount = investorPL[i];
            investorInfo[id][addr].pledgeCalcAmount = investorPL[i];

            pledgeTotalAmount[id] += investorPL[i];
            //pledgeTotalCalcAmount[id] += investorPL[i];
        }
        require(investorTotalPower == 0, "ProcessS: investor power err when mount node.");
        require(totalPledge == pledgeTotalAmount[id], "ProcessS: total pledge amount err when mount node.");
    }

    function sponsorSign(uint256 id) public {
        require(sponsorPower[id][msg.sender] > 0, "ProcessS: not sponsor.");
        require(!sponsorAck[id][msg.sender], "ProcessS: already signed.");
        sponsorAck[id][msg.sender] = true;
        sponsorAckNo[id]++;

        emit SponsorSign(id, msg.sender);

        if( mountOrNot[id] &&
            (sponsorNo[id] == sponsorAckNo[id]) &&
            (investorAckNo[id] == investorNo[id]) &&
            (pledgeTotalCalcAmount[id] > 0)
          ) {
            sealEndTime[id] = block.timestamp;
            raiseState[id] = RaiseState.Success;
            emit MountSuccess(id, pledgeTotalCalcAmount[id]);
        }
    }

    function investorSign(uint256 id) public {
        require(investorPower[id][msg.sender] > 0, "ProcessS: not sponsor.");
        require(!investorAck[id][msg.sender], "ProcessS: already signed.");
        investorAck[id][msg.sender] = true;
        investorAckNo[id]++;

        emit InvestorSign(id, msg.sender);

        if( (sponsorNo[id] == sponsorAckNo[id]) && 
            (investorAckNo[id] == investorNo[id]) &&
            (pledgeTotalCalcAmount[id] > 0)
          ) {
            sealEndTime[id] = block.timestamp;
            raiseState[id] = RaiseState.Success;
            emit MountSuccess(id, pledgeTotalCalcAmount[id]);
        }
    }

    // judge node's current state
    function pushSealProgress(uint256 id, uint256 amount) public onlyManager {
        require(nodeState[id] >= NodeState.Started, "Ctrl: state error.");
        require(block.timestamp < sealEndTime[id] + 2 days, "Ctrl: time err.");
        if(amount > pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount + safeSealFund[id] + safeSealedFund[id]) {
            amount = pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount + safeSealFund[id] + safeSealedFund[id];
        }

        require(sealedAmount[id] <= amount, "Ctrl: sealedAmount error.");
        sealedAmount[id] = amount;

        if(amount < pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
            fundSealed[id] = amount * opsCalcFund[id] / (opsCalcFund[id] + raiseInfo[id].targetAmount);
            if(safeSealedFund[id] > 0) {
                safeSealFund[id] += safeSealedFund[id];
                safeSealedFund[id] = 0;
            }
        } else {
            fundSealed[id] = amount - pledgeTotalAmount[id];
            uint256 safeFund = safeSealFund[id] + safeSealedFund[id];
            safeSealedFund[id] = fundSealed[id] - opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount;
            safeSealFund[id] = safeFund - safeSealedFund[id];
            if(raiseState[id] == RaiseState.Success && nodeState[id] < NodeState.End) {
                if(sealEndTime[id] > block.timestamp) sealEndTime[id] = block.timestamp;
                nodeState[id] = NodeState.End;
                emit NodeStateChange(id, nodeState[id]);
                emit SealEnd(id, amount);
            }
        }

        if(nodeState[id] == NodeState.Started && block.timestamp >= sealEndTime[id]) {
            nodeState[id] = NodeState.End;
            emit NodeStateChange(id, nodeState[id]);
            emit SealEnd(id, amount);
        }
        emit PushSealProgress(id, amount, nodeState[id]);
    }

    function securityNeed(uint256 id) public view returns(uint256) {
        if(mountOrNot[id]) {
            return (spFine[id] - subFine[id]);
        } else if(raiseState[id] == RaiseState.WaitingStart) {
            return 0;
        }

        uint256 addAmount = 0;
        if(spFine[id] >= subFine[id] + safeFundFine[id]) {
            addAmount = spFine[id] - subFine[id] - safeFundFine[id];
        }

        if( nodeState[id] < NodeState.End &&
            block.timestamp < sealEndTime[id] &&
            safeSealFund[id] + safeSealedFund[id] < spSafeSealFund
        ) {
            addAmount = addAmount + spSafeSealFund - safeSealFund[id] - safeSealedFund[id];
        }
        return addAmount;
    }

    function addOpsSecurityFund(uint256 id) public payable onlySp {
        uint256 addAmount = msg.value;
        require(addAmount != 0, "ProcessS: not need add.");
        require(addAmount == (securityNeed(id)), "ProcessS: msg.value err.");

        _sendWithValue(addAmount);
        emit SendToMiner(id, msg.sender, addAmount);

        if(mountOrNot[id]) {
            subFine[id] = spFine[id];
            emit AddOpsSecurityFund(id, msg.sender, msg.value);
            return;
        }

        subFine[id] = spFine[id] - safeFundFine[id];
        if( nodeState[id] < NodeState.End &&
            block.timestamp < sealEndTime[id] &&
            safeSealFund[id] + safeSealedFund[id] < spSafeSealFund
        ) {
            if(safeSealFund[id] + safeSealedFund[id] + safeFundFine[id] == 0) {
                toSealAmount[id] += spSafeSealFund;
            }
            safeSealFund[id] = spSafeSealFund - safeSealedFund[id];
        }

        if(spRewardFine[id] > 0) spRewardFine[id] = 0;
        if(spFundRewardFine[id] > 0) spFundRewardFine[id] = 0;
        if(spFundFine[id] > 0) spFundFine[id] = 0;
        if(investorFine[id] > 0) investorFine[id] = 0;

        emit AddOpsSecurityFund(id, msg.sender, msg.value);
    }

    function pushBlockReward(uint256 id, uint256 released, uint256 willRelease) external onlyManager {
        require(released >= totalReleasedRewardAmount[id] && willRelease + released >= totalRewardAmount[id], "Ctrl: param error.");
        totalRewardAmount[id] = released + willRelease;
        totalReleasedRewardAmount[id] = released;

        if(extendInfo[id].oldId != id) {
            if(nodeState[id] == NodeState.Destroy) {
                spRewardLock[id] = 0;
            } else if(sealEndTime[id] == 0 || block.timestamp < sealEndTime[id] + 30 days) {
                spRewardLock[id] = released * raiseInfo[id].servicerShare / rateBase;
            }
        }

        if(nodeState[id] < NodeState.Destroy) {
            uint256 amountFromMiner = released + pledgeReleased[id];
            if(spRewardFine[id] > spRewardLock[id]) {
                amountFromMiner -= spRewardFine[id];
            } else {
                amountFromMiner -= spRewardLock[id];
            }

            //amountFromMiner -= released * raiseInfo[id].spFundShare / rateBase; //sub sp fund's reward
            //sub sp fund's reward
            if(!mountOrNot[id]) {
                uint256 calcReleased = released * (raiseInfo[id].investorShare + raiseInfo[id].spFundShare) / rateBase;
                uint256 releasedFund = 0;
                if(sealedAmount[id] <= pledgeTotalAmount[id] + opsCalcFund[id] * pledgeTotalAmount[id] / raiseInfo[id].targetAmount) {
                    releasedFund = calcReleased * opsCalcFund[id] / (opsCalcFund[id] + raiseInfo[id].targetAmount);
                } else {
                    releasedFund = calcReleased * fundSealed[id] / sealedAmount[id];
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

        uint256 transAmount = released * raiseInfo[id].filFiShare / rateBase - gotFilFiReward[id];
        if(transAmount > 0 && transAmount <= address(this).balance) {
            payable(ITools(_toolAddr).receiver()).transfer(transAmount);
            gotFilFiReward[id] += transAmount;
        }

        emit PushBlockReward(id, released, willRelease);
    }

    function pushPledgeAmount(uint256 id, uint256 amount) public onlyManager {
        require(mountOrNot[id] && (raiseState[id] == RaiseState.WaitingStart), "ProcessS: state err.");
        //require(amount >= pledgeTotalAmount[id], "ProcessS: amount err.");
        require(pledgeTotalCalcAmount[id] == 0, "ProcessS: already pushed.");

        emit PushPledgeAmount(id, amount);

        if(amount < pledgeTotalAmount[id]) {
            raiseState[id] = RaiseState.Failure;
            emit MountFailed(id);
            return;
        }
        pledgeTotalCalcAmount[id] = pledgeTotalAmount[id];

        if((sponsorNo[id] == sponsorAckNo[id]) && (investorAckNo[id] == investorNo[id])) {
            sealEndTime[id] = block.timestamp;
            raiseState[id] = RaiseState.Success;
            emit MountSuccess(id, pledgeTotalAmount[id]);
        }
    }

    function pushRaiserPenalty(uint256 id, uint256 amount) public onlyManager {
        require(nodeState[id] >= NodeState.Started, "ProcessS: state error.");
        require(raiserFine[id] < amount, "ProcessS: amount err.");

        raiserFine[id] = amount;

        emit PushRaiserPenalty(id, amount);
    }

    function sponsorWithdraw(uint256 id, address addr) public {
        uint256 _amount = sponsorRewardAvailableLeft(id, addr);
        require(_amount != 0, "ProcessS: no reward.");

        if(mountOrNot[id]) {
            require(raiseState[id] == RaiseState.Success, "ProcessS: state err when mount.");
        } else {
            require(nodeState[id] != NodeState.WaitingStart, "ProcessS: state err.");
        }

        gotRaiserReward[id] += _amount;
        gotSponsorReward[id][addr] += _amount;
        payable(addr).transfer(_amount);

        emit SponsorWithdraw(id, address(this), addr, _amount);
    }

    function sponsorWillReleaseReward(uint256 id, address addr) public view returns (uint256) {
        return (totalRewardAmount[id] - totalReleasedRewardAmount[id]) * sponsorPower[id][addr] / 10**7;
    }

    function sponsorRewardAvailableLeft(uint256 id, address addr) public view returns (uint256) {
        return totalReleasedRewardAmount[id] * sponsorPower[id][addr] / 10**7 - gotSponsorReward[id][addr];
    }
}