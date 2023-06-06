// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LetsFilProxy.sol";
import "./interfaces/ILetsFilPackInfo.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ILetsFilControler is ILetsFilPackInfo {
    function initialize(uint256 raiseID, RaiseInfo memory raiseInfo, NodeInfo memory nodeInfo, ExtendInfo memory extendInfo) external;
}

contract LetsFilFactory is ILetsFilPackInfo, Initializable, OwnableUpgradeable, UUPSUpgradeable {

    event CreateRaisePlan(uint256 id, address raisePool, address caller, RaiseInfo raiseInfo, NodeInfo nodeInfo, ExtendInfo extendInfo);

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
    //The minimum maintenance margin coefficient.
    uint256 private constant opsSecurityFundMinCoeff = 500;
    //raise plan's commission coefficient
    uint256 private constant feeCoeff = 30;

    address public toolAddr = address(0x6603D8B22B2dCEC2A1418aCC911Cf4bC21026353); //Hyperspace

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

        if(!fundSafe) {
            uint256 fee = _raiseInfo.targetAmount * feeCoeff / rateBase;
            uint256 maxFine = (_raiseInfo.targetAmount + _nodeInfo.opsSecurityFund) * networkAnnual / rateBase * _raiseInfo.raiseDays / 365;
            require(_raiseInfo.securityFund >= maxFine + fee, "LetsFilFactory: securityFund is less than maxFine and fee.");

            maxFine = _raiseInfo.targetAmount * networkAnnual / rateBase * fineCoeff / rateBase * _nodeInfo.sealDays / 365;
            require(_raiseInfo.securityFund >= maxFine + fee, "LetsFilFactory: securityFund is less than maxFine2 and fee.");

            maxFine = _raiseInfo.targetAmount * networkAnnual / rateBase * (rateBase - sealMinCoeff) / rateBase * fineCoeff / rateBase * _nodeInfo.sealDays / 365;
            maxFine *= (sealDelayCoeff + rateBase) / rateBase;
            maxFine += _raiseInfo.targetAmount * (rateBase - sealMinCoeff) / rateBase * protocolSealFineCoeff / rateBase * _nodeInfo.sealDays * sealDelayCoeff / rateBase;
            require(_raiseInfo.securityFund >= maxFine + fee, "LetsFilFactory: securityFund is less than maxFine3 and fee.");

            //require(_nodeInfo.opsSecurityFund * rateBase / _raiseInfo.targetAmount >= opsSecurityFundMinCoeff, "LetsFilFactory: opsSecurityFund error.");
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
