// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./NoDelegateCall.sol";
import "./interfaces/ILetsFilRaiseFactory.sol";
import "./LetsFilRaisePlan.sol";

contract LetsFilRaiseFactory is ILetsFilRaiseFactory, NoDelegateCall {

    event eCreateRaisePlan(address raisePool, address caller, uint256 payValue, RaiseInfo raiseInfo, NodeInfo nodeInfo, uint256 raiseID);
    event eTest(address addr);

    //raise plan ID
    uint256 private raiseID;
    // minerId => raiseId[], all inactive raise plan
    mapping(uint64 => uint256[]) private inactivePlan;
    // minerId => raiseId, running plan
    mapping(uint64 => uint256) private activePlan;
    // raiseId => raisePlan, all raise plan info
    mapping(uint256 => RaisePlan) private plans;
    // api manager
    address private manager;

    constructor(address _manager) {
        manager = _manager;
    }
    
    // endPlan, Need to move active to inactive array
    function endPlan(uint256 _raiseID) external noDelegateCall returns (bool) {
        RaisePlan memory plan = plans[_raiseID];
        require(plan.sponsor == tx.origin, "END_PLAN_ORIGIN_ERROR");
        delete activePlan[plan.minerId];
        inactivePlan[plan.minerId].push(plan.raiseId);
        return true;
    }

    // create new raise plan
    function createRaisePlan(RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo) payable external noDelegateCall returns (address planAddress) {
        _raiseInfo.id = ++raiseID;
        require(activePlan[_nodeInfo.minerID] == 0, "miner already exists");
        planAddress = deploy(++raiseID, _raiseInfo, _nodeInfo, manager);
        emit eCreateRaisePlan(planAddress, msg.sender, msg.value, _raiseInfo, _nodeInfo, _raiseInfo.id);
    }

    // depoly raise plan
    function deploy(uint256 _raiseID, RaiseInfo memory _raiseInfo, NodeInfo memory _nodeInfo, address manager) internal returns (address) {
        return address(new LetsFilRaisePlan{
                salt: keccak256(abi.encode(raiseID)), 
                value: msg.value
            }(_raiseID, _raiseInfo, _nodeInfo, manager, address(this)));
    }
}

