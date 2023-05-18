// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "./BaseFallback.sol";

import {IBaseRewardsPool} from "src/interfaces/IBaseRewardsPool.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";

contract FallbackConvexCurve is BaseFallback {
    using SafeTransferLib for ERC20;

    IBoosterConvexCurve public boosterConvexCurve; // ConvexCurve booster contract

    error DEPOSIT_FAIL();

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

    function isActive(address lpToken) external override returns (bool) {
        setAllPidsOptimized();

        (,,,,, bool shutdown) = boosterConvexCurve.poolInfo(pids[lpToken].pid);
        return pids[lpToken].isInitialized && !shutdown;
    }

    function balanceOf(address lpToken) external view override returns (uint256) {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = boosterConvexCurve.poolInfo(pids[lpToken].pid);
        // Check current balance on convexCurve
        return ERC20(crvRewards).balanceOf(address(this));
    }

    function deposit(address lpToken, uint256 amount) public override {
        // Approve the amount
        ERC20(lpToken).safeApprove(address(boosterConvexCurve), amount);
        // Deposit the amount
        bool success = boosterConvexCurve.deposit(pids[lpToken].pid, amount, true);

        // Check if the deposit was successful
        if (!success) revert DEPOSIT_FAIL();
    }

    function withdraw(address lpToken, uint256 amount) public override {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = boosterConvexCurve.poolInfo(pids[lpToken].pid);
        // Withdraw from ConvexCurve gauge
        IBaseRewardsPool(crvRewards).withdrawAndUnwrap(amount, false);

        // Transfer the amount
        ERC20(lpToken).safeTransfer(msg.sender, amount);
    }
}
