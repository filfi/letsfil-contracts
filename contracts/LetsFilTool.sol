// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

contract LetsFilTool is Ownable {
    // api manager
    address public manager;
    address public receiver;
    address public managerProposed;
    address public implementation;

    constructor() {
        manager = msg.sender;
        receiver = msg.sender;
    }

    function changeManager(address _managerProposed) public {
        require(msg.sender == manager, "only manager can do changeManager");
        managerProposed = _managerProposed;
    }

    function claimManager() public {
        require(msg.sender == managerProposed, "do not have permission to claim");
        manager = managerProposed;
        managerProposed = address(0);
    }

    function setManager(address _manager) public onlyOwner {
        manager = _manager;
    }

    function setReceiver(address _receiver) public onlyOwner {
        receiver = _receiver;
    }

    function setImplementation(address _implementation) public onlyOwner {
        implementation = _implementation;
    }
}
