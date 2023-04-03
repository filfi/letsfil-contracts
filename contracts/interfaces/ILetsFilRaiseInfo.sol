// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILetsFilRaiseInfo {
    struct RaiseInfo {
        uint256 id;             // raise id
        uint256 targetAmount;   // raise target amount
        uint256 securityFund;   // first raise security fund
        uint256 securityFundRate; // second ops security fund
        uint256 deadline;       // raise deadline
        uint256 raiserShare;    // raiser reward share
        uint256 investorShare;  // staking reward share
        uint256 servicerShare;  // sp/servicer reward share
        address sponsor;        // raise address
        uint256 companyId;      // sp company id
        address spAddress;      // sp address
        string raiseCompany;    // raise company name
    }

    struct NodeInfo {
        uint256 nodeSize;           // sp node size
        uint256 sectorSize;         // node sector size
        uint256 sealPeriod;         // seal period
        uint256 nodePeriod;         // node period
        uint256 opsSecurityFund;    // ops curity fund
        address opsSecurityFundPayer; // address of pay ops curity fund 
        uint64 minerID;             // Miner ID
        uint256 realSealAmount;     // real seal pledge token amount
    }
}
