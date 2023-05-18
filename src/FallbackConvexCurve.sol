// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {BaseFallback, IBoosterConvexCurve} from "./BaseFallback.sol";

contract FallbackConvexCurve is BaseFallback {
    constructor() {
        boosterConvexCurve = IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

        setAllPidsOptimized();
    }

    function setPid(uint256 index) public override {
        // Get the lpToken address
        (address lpToken,,,,,) = boosterConvexCurve.poolInfo(index);

        // Map the lpToken to the pool infos
        pids[lpToken] = PidsInfo(index, true);
    }

    function setAllPidsOptimized() public override {
        // Cache the length of the pool registry
        uint256 len = boosterConvexCurve.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len; ++i) {
            setPid(i);
        }

        // Update the last length
        lastPidsCount = len;
    }

    function isActive(address lpToken) public override returns (bool) {
        setAllPidsOptimized();

        (,,,,, bool shutdown) = boosterConvexCurve.poolInfo(pids[lpToken].pid);
        return pids[lpToken].isInitialized && !shutdown;
    }
}
