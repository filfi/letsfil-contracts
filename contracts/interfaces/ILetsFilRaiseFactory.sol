// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import './ILetsFilRaiseInfo.sol';
interface ILetsFilRaiseFactory is ILetsFilRaiseInfo {

    struct RaisePlan {
        address sponsor; // raiser address
        uint64 minerId; // minerID
        uint256 raiseId; // raise id
        address raiseAddress; // raiser address
    }
   
}