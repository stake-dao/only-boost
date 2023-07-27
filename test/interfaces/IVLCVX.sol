// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface VLCVX {
    function lock(address, uint256, uint256) external;
    function lockedBalances(address) external view returns (uint256, uint256, uint256, uint256);
    function kickExpiredLocks(address account) external;
    function processExpiredLocks(bool _relock) external;
    function lockedSupply() external view returns (uint256);
}
