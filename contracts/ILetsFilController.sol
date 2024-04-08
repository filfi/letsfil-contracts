// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ILetsFilController {
    // 结束运维期
    // 需要在封装结束后(节点周期 + 180)天才能调用
    function emergencyPush(uint256 id) external;
    // 建设者提取奖励
    function investorWithdraw(uint256 id) external;
    // 单一主办人时，主办人提取奖励
    function raiserWithdraw(uint256 id) external;
    // 多主办人时，主办人提取奖励
    function sponsorWithdraw(uint256 id, address addr) external;
    // SP提取服务费奖励
    function spWithdraw(uint256 id) external;
    // SP提取运维保证金产生的奖励
    function withdrawFundReward(uint256 id) external;
    // 建设者提取质押币
    function unStaking(uint256 id) external;
    // 主办人提取保证金
    function withdrawSecurityFund(uint256 id) external;
    // SP提取保证金
    function withdrawOpsSecurityFund(uint256 id) external;
    // 查询建设者可提奖励
    function availableRewardOf(uint256 id, address addr) external view returns (uint256);
    // 查询建设者可提质押币、利息
    function getBack(uint256 id, address account) external view returns (uint256, uint256);
    // 单一主办人时，查询主办人可提奖励
    function raiserRewardAvailableLeft(uint256 id) external view returns (uint256);
    // 多主办人时，查询主办人可提奖励
    function sponsorRewardAvailableLeft(uint256 id, address addr) external view returns (uint256);
    // 查询SP可提服务费奖励
    function spRewardAvailableLeft(uint256 id) external view returns (uint256 amountReturn);
    // 查询SP运维保证金可提奖励
    function opsFundReward(uint256 id) external view returns(uint256);
}