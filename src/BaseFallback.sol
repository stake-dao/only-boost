// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract BaseFallback {
    struct PidsInfo {
        uint256 pid;
        bool isInitialized;
    }

    uint256 public lastPidsCount; // Number of pools on ConvexCurve or ConvexFrax

    mapping(address => PidsInfo) public pids; // lpToken address --> pool ids from ConvexCurve or ConvexFrax

    function setPid(uint256 index) public virtual {}

    function setAllPidsOptimized() public virtual {}

    function isActive(address lpToken) external virtual returns (bool) {}

    function balanceOf(address lpToken) external view virtual returns (uint256) {}

    function deposit(address lpToken, uint256 amount) external virtual {}

    function withdraw(address lpToken, uint256 amount) external virtual {}

    function getPid(address lpToken) external view virtual returns (PidsInfo memory) {}
}
