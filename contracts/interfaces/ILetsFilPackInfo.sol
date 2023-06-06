// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILetsFilPackInfo {
    struct RaiseInfo {
        uint256 id;             // raise id
        uint256 targetAmount;   // raise target amount
        uint256 minRaiseRate;   // the min raise rate when expire
        uint256 securityFund;   // first raise security fund
        uint256 raiseDays;      // raise days
        uint256 investorShare;  // staking reward share
        uint256 spFundShare;    // sp security fund share
        uint256 raiserShare;    // raiser reward share
        uint256 servicerShare;  // sp/servicer reward share
        uint256 filFiShare;     // FilFi reward share
        address sponsor;        // raise address
        string raiseCompany;    // raise company name
    }

    struct NodeInfo {
        uint64 minerId;             // Miner Id
        uint256 nodeSize;           // sp node size
        uint256 sectorSize;         // node sector size
        uint256 sealDays;           // seal period
        uint256 nodeDays;           // node period (180/360/540)
        uint256 opsSecurityFund;    // ops curity fund
        address spAddr;         // sp address
        uint256 companyId;      // sp company id
    }

    struct ExtendInfo {
        uint256 oldId;
        uint256 raiserOldShare;
        uint256 spOldShare;
        uint256 sponsorOldRewardShare;
        uint256 spOldRewardShare;
    }
}
