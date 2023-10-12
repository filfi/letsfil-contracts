// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LetsFilProxy.sol";
import "./interfaces/ILetsFilPackInfo.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ILetsFilControler is ILetsFilPackInfo {
    function initialize(uint256 raiseID, RaiseInfo memory raiseInfo, NodeInfo memory nodeInfo, ExtendInfo memory extendInfo) external;
    function createPlan( uint256 id, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                         address[] memory sponsorList, uint256[] memory sponsorPPL,
                         uint256 startTime
                       ) external;
    function createPrivatePlan( uint256 id, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                                address[] memory sponsorList, uint256[] memory sponsorPPL,
                                address[] memory investorList, uint256[] memory maxPledge,
                                uint256 startTime
                              ) external;
    function mountNode( uint256 id, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                        address[] memory sponsorList, uint256[] memory sponsorPPL,
                        address[] memory investorList, uint256[] memory investorPL, uint256[] memory investorPPL,
                        uint256 totalPledge
                      ) external;
}

contract LetsFilFactory is ILetsFilPackInfo, Initializable, OwnableUpgradeable, UUPSUpgradeable {

    event CreateRaisePlan(uint256 id, address raisePool, address caller, RaiseInfo raiseInfo, NodeInfo nodeInfo, ExtendInfo extendInfo);
    event CreatePlan(uint256 id, address raisePool, address caller, RaiseInfo raiseInfo, NodeInfo nodeInfo);
    event CreatePrivatePlan(uint256 id, address raisePool, address caller, RaiseInfo raiseInfo, NodeInfo nodeInfo);
    event MountNode(uint256 id, address raisePool, address caller, RaiseInfo raiseInfo, NodeInfo nodeInfo);

    struct RaisePlan {
        address sponsor;         // raiser address
        uint64  minerId;         // miner's id
        uint256 raiseId;         // raise plan's id
        address controlerAddr;   // plan controler's address
    }
    // raiseId => raisePlan, all raise plan info
    mapping(uint256 => RaisePlan) public plans;

    //Network base annual interest rate for calculating fine
    uint256 private constant networkAnnual = 100;
    uint256 private constant rateBase = 10000;
    uint256 private constant fineCoeff = 30000;
    //Successfully to entered the delay period
    uint256 private constant sealMinCoeff = 5000;
    //to set the seal delay days
    uint256 private constant sealDelayCoeff = 5000;
    uint256 private constant protocolSealFineCoeff = 10;
    //The minimum security fund coefficient.
    uint256 private constant securityFundMinCoeff = 500;
    //The minimum maintenance margin coefficient.
    uint256 private constant opsSecurityFundMinCoeff = 500;
    //raise plan's commission coefficient
    uint256 private constant feeCoeff = 30;

    address public toolAddr = address(0x189a5BD936b64Caa4EbEbb27c1A46F8bCD47f50c); //Mainnet

    bool public fundSafe;

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function setToolAddress(address addr) public onlyOwner {
        toolAddr = addr;
    }

    function setFundSafe(bool safe) public onlyOwner {
        fundSafe = safe;
    }

    // create new raise plan
    function createRaisePlan(RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo, ExtendInfo memory _extendInfo) public returns (address planAddress) {
        require(_raiseInfo.id > 0, "LetsFilFactory: raiseId should greater than 0.");
        require(plans[_raiseInfo.id].raiseId == 0, "LetsFilFactory: plan already existed.");
        require( _raiseInfo.targetAmount > 0 &&
                 _raiseInfo.securityFund > 0 &&
                 _nodeInfo.opsSecurityFund > 0, "LetsFilFactory: plan target or security fund is 0.");

        if(!fundSafe) {
            uint256 fee = _raiseInfo.targetAmount * feeCoeff / rateBase;
            uint256 maxFine = _raiseInfo.targetAmount * securityFundMinCoeff / rateBase;
            require(_raiseInfo.securityFund >= maxFine + fee, "LetsFilFactory: securityFund is less than maxFine and fee.");
            require(_nodeInfo.opsSecurityFund >= (_raiseInfo.targetAmount + _nodeInfo.opsSecurityFund) * opsSecurityFundMinCoeff / rateBase, "LetsFilFactory: opsSecurityFund error.");
        }

        if(_extendInfo.oldId > 0) _extendInfo.oldId = _raiseInfo.id * 10;

        planAddress = deploy(_raiseInfo.id);
        ILetsFilControler(planAddress).initialize(_raiseInfo.id, _raiseInfo, _nodeInfo, _extendInfo);

        plans[_raiseInfo.id].raiseId = _raiseInfo.id;
        plans[_raiseInfo.id].sponsor = _raiseInfo.sponsor;
        plans[_raiseInfo.id].minerId = _nodeInfo.minerId;
        plans[_raiseInfo.id].controlerAddr = planAddress;

        emit CreateRaisePlan(_raiseInfo.id, planAddress, msg.sender, _raiseInfo, _nodeInfo, _extendInfo);
    }

    function createPlan( RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                         address[] memory sponsorList, uint256[] memory sponsorPPL,
                         uint256 startTime
                       ) public returns (address controlerAddr) {
        require(_raiseInfo.id > 0, "LetsFilFactory: raiseId should greater than 0.");
        require(plans[_raiseInfo.id].raiseId == 0, "LetsFilFactory: plan already existed.");
        require( _raiseInfo.targetAmount > 0 &&
                 _raiseInfo.securityFund > 0 &&
                 _nodeInfo.opsSecurityFund > 0, "LetsFilFactory: plan target or security fund is 0.");

        if(!fundSafe) {
            uint256 fee = _raiseInfo.targetAmount * feeCoeff / rateBase;
            uint256 maxFine = _raiseInfo.targetAmount * securityFundMinCoeff / rateBase;
            require(_raiseInfo.securityFund >= maxFine + fee, "LetsFilFactory: securityFund is less than maxFine and fee.");
            require(_nodeInfo.opsSecurityFund >= (_raiseInfo.targetAmount + _nodeInfo.opsSecurityFund) * opsSecurityFundMinCoeff / rateBase, "LetsFilFactory: opsSecurityFund error.");
        }

        controlerAddr = deploy(_raiseInfo.id);
        ILetsFilControler(controlerAddr).createPlan( _raiseInfo.id, _raiseInfo, _nodeInfo, 
                                                     sponsorList, sponsorPPL,
                                                     startTime
                                                   );

        plans[_raiseInfo.id].raiseId = _raiseInfo.id;
        plans[_raiseInfo.id].sponsor = _raiseInfo.sponsor;
        plans[_raiseInfo.id].minerId = _nodeInfo.minerId;
        plans[_raiseInfo.id].controlerAddr = controlerAddr;

        emit CreatePlan(_raiseInfo.id, controlerAddr, msg.sender, _raiseInfo, _nodeInfo);
    }

    //maxPledge: investor's max pledge amount (0 means there is no limit)
    function createPrivatePlan( RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                                address[] memory sponsorList, uint256[] memory sponsorPPL,
                                address[] memory investorList, uint256[] memory maxPledge,
                                uint256 startTime
                              ) public returns (address controlerAddr) {
        require(_raiseInfo.id > 0, "LetsFilFactory: raiseId should greater than 0.");
        require(plans[_raiseInfo.id].raiseId == 0, "LetsFilFactory: plan already existed.");
        require( _raiseInfo.targetAmount > 0 &&
                 _raiseInfo.securityFund > 0 &&
                 _nodeInfo.opsSecurityFund > 0, "LetsFilFactory: plan target or security fund is 0.");

        if(!fundSafe) {
            uint256 fee = _raiseInfo.targetAmount * feeCoeff / rateBase;
            uint256 maxFine = _raiseInfo.targetAmount * securityFundMinCoeff / rateBase;
            require(_raiseInfo.securityFund >= maxFine + fee, "LetsFilFactory: securityFund is less than maxFine and fee.");
            require(_nodeInfo.opsSecurityFund >= (_raiseInfo.targetAmount + _nodeInfo.opsSecurityFund) * opsSecurityFundMinCoeff / rateBase, "LetsFilFactory: opsSecurityFund error.");
        }

        controlerAddr = deploy(_raiseInfo.id);
        ILetsFilControler(controlerAddr).createPrivatePlan( _raiseInfo.id, _raiseInfo, _nodeInfo, 
                                                            sponsorList, sponsorPPL,
                                                            investorList, maxPledge,
                                                            startTime
                                                          );

        plans[_raiseInfo.id].raiseId = _raiseInfo.id;
        plans[_raiseInfo.id].sponsor = _raiseInfo.sponsor;
        plans[_raiseInfo.id].minerId = _nodeInfo.minerId;
        plans[_raiseInfo.id].controlerAddr = controlerAddr;

        emit CreatePrivatePlan(_raiseInfo.id, controlerAddr, msg.sender, _raiseInfo, _nodeInfo);
    }

    //sponsorPPL: sponsor power proportion list
    //investorPL: investor pledge list
    //investorPPL: investor power proportion list
    function mountNode( RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo,
                        address[] memory sponsorList, uint256[] memory sponsorPPL,
                        address[] memory investorList, uint256[] memory investorPL, uint256[] memory investorPPL,
                        uint256 totalPledge
                      ) public returns (address controlerAddr) {
        require(_raiseInfo.id > 0, "LetsFilFactory: raiseId should greater than 0.");
        require(plans[_raiseInfo.id].raiseId == 0, "LetsFilFactory: plan already existed.");

        controlerAddr = deploy(_raiseInfo.id);
        ILetsFilControler(controlerAddr).mountNode( _raiseInfo.id, _raiseInfo, _nodeInfo, 
                                                    sponsorList, sponsorPPL,
                                                    investorList, investorPL, investorPPL,
                                                    totalPledge
                                                  );

        plans[_raiseInfo.id].raiseId = _raiseInfo.id;
        plans[_raiseInfo.id].sponsor = _raiseInfo.sponsor;
        plans[_raiseInfo.id].minerId = _nodeInfo.minerId;
        plans[_raiseInfo.id].controlerAddr = controlerAddr;

        emit MountNode(_raiseInfo.id, controlerAddr, msg.sender, _raiseInfo, _nodeInfo);
    }

    // depoly raise plan
    function deploy(uint256 _raiseID) internal returns (address) {
        require(toolAddr != address(0), "LetsFilFactory: toolAddr is null.");
        return address(new LetsFilProxy{
                salt: keccak256(abi.encode(_raiseID))
            }(toolAddr));
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
}
