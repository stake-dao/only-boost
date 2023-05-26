// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "./BaseFallback.sol";

import {IBaseRewardsPool} from "src/interfaces/IBaseRewardsPool.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";

contract FallbackConvexCurve is BaseFallback {
    using SafeTransferLib for ERC20;

    IBoosterConvexCurve public boosterConvexCurve; // ConvexCurve booster contract

    bool public claimOnWithdraw = true;

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

    function deposit(address lpToken, uint256 amount) external override {
        // Approve the amount
        ERC20(lpToken).safeApprove(address(boosterConvexCurve), amount);
        // Deposit the amount
        bool success = boosterConvexCurve.deposit(pids[lpToken].pid, amount, true);

        // Check if the deposit was successful
        if (!success) revert DEPOSIT_FAIL();

        emit Deposited(lpToken, amount);
    }

    function withdraw(address lpToken, uint256 amount) external override {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = boosterConvexCurve.poolInfo(pids[lpToken].pid);
        // Withdraw from ConvexCurve gauge
        IBaseRewardsPool(crvRewards).withdrawAndUnwrap(amount, claimOnWithdraw);

        // Transfer the amount
        ERC20(lpToken).safeTransfer(msg.sender, amount);

        emit Withdrawn(lpToken, amount);
    }

    function claimRewards(address lpToken)
        external
        override
        returns (address[10] memory tokens, uint256[10] memory amounts)
    {
        // Todo: add possibility to charges fees
        // Only callable by the strategy

        // Cache the pid
        PidsInfo memory pidInfo = pids[lpToken];
        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (tokens, amounts);

        // Get cvxLpToken address
        (,,, address crvRewards,,) = boosterConvexCurve.poolInfo(pidInfo.pid);
        // Check if there is extra rewards
        uint256 extraRewardsLength = IBaseRewardsPool(crvRewards).extraRewardsLength();
        // Withdraw from ConvexCurve gauge
        IBaseRewardsPool(crvRewards).getReward(address(this), extraRewardsLength > 0 ? true : false);

        // Transfer CRV rewards to strategy
        uint256 balanceCRV = CRV.balanceOf(address(this));
        if (balanceCRV > 0) CRV.safeTransfer(msg.sender, balanceCRV);
        tokens[0] = address(CRV);
        amounts[0] = balanceCRV;
        // Transfer CVX rewards to strategy
        uint256 balanceCVX = CVX.balanceOf(address(this));
        if (balanceCVX > 0) CVX.safeTransfer(msg.sender, balanceCVX);
        tokens[1] = address(CVX);
        amounts[1] = balanceCVX;

        // Transfer extra rewards to strategy if any
        if (extraRewardsLength > 0) {
            for (uint256 i = 0; i < extraRewardsLength; ++i) {
                address extraRewardToken = IBaseRewardsPool(crvRewards).extraRewards(i);
                uint256 balanceExtraRewardToken = ERC20(extraRewardToken).balanceOf(address(this));
                if (balanceExtraRewardToken > 0) {
                    ERC20(extraRewardToken).safeTransfer(msg.sender, balanceExtraRewardToken);
                    tokens[i + 2] = extraRewardToken;
                    amounts[i + 2] = balanceExtraRewardToken;
                }
            }
        }

        // Returning the tokens and amounts using arrays is surely not optimal!
        // To be optimized in the future

        emit ClaimedRewards(lpToken, balanceCRV, balanceCVX);
    }

    function getPid(address lpToken) external view override returns (PidsInfo memory) {
        return pids[lpToken];
    }
}
