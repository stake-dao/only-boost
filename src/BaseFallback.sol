// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract BaseFallback {
    struct PidsInfo {
        uint256 pid;
        bool isInitialized;
    }

    IBoosterConvexCurve public boosterConvexCurve; // ConvexCurve booster
    IPoolRegistryConvexFrax public poolRegistryConvexFrax; // ConvexFrax pool Registry

    uint256 public lastPidsCount; // Number of pools on ConvexCurve or ConvexFrax

    mapping(address => PidsInfo) public pids; // lpToken address --> pool ids from ConvexCurve or ConvexFrax

    function setPid(uint256 index) public virtual {}
    function setAllPidsOptimized() public virtual {}
    function isActive(address lpToken) public virtual returns (bool) {}

    function deposit(uint256 amount) external virtual {}
    function withdraw(uint256 amount) external virtual {}
    function balanceOf(address lpToken) external virtual returns (uint256) {}
}
