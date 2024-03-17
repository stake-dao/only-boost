// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

/// @notice RewardReceiver contract to hold rewards for LGV3+ Gauges.
contract RewardReceiver is Clone {
    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the gauge contract the contract receives rewards from.
    function gauge() public pure returns (address _gauge) {
        return _getArgAddress(0);
    }

    /// @notice Address of the locker contract.
    function locker() public pure returns (address _locker) {
        return _getArgAddress(20);
    }

    /// @notice Address of the reward token.
    function rewardToken() public pure returns (address _rewardToken) {
        return _getArgAddress(40);
    }

    /// @notice Address of the strategy contract.
    function strategy() public pure returns (address _strategy) {
        return _getArgAddress(60);
    }

    /// @notice Address of the reward distributor contract.
    function rewardDistributor() public pure returns (address _rewardDistributor) {
        return _getArgAddress(80);
    }

    /// @notice Throws if the caller is not the strategy contract.
    error UNAUTHORIZED();

    modifier onlyStrategy() {
        if (msg.sender != strategy()) revert UNAUTHORIZED();
        _;
    }

    function approveRewardToken(address token) external onlyStrategy {
        /// We approve the strategy as well in case there's a rescue of the reward token needed.
        SafeTransferLib.safeApproveWithRetry(token, strategy(), type(uint256).max);

        // Approve the reward distributor to spend the reward token.
        SafeTransferLib.safeApproveWithRetry(token, rewardDistributor(), type(uint256).max);
    }

    function notifyAll() external onlyStrategy returns (uint256 rewardTokenAmount) {
        // Claim rewards from the gauge and notify the strategy.
        ILiquidityGauge(gauge()).claim_rewards(locker());

        address _rewardToken;
        for (uint256 i = 0; i < 8; i++) {
            _rewardToken = ILiquidityGauge(gauge()).reward_tokens(i);
            if (_rewardToken == address(0)) break;

            uint256 _balance = ERC20(_rewardToken).balanceOf(address(this));

            if (_rewardToken == rewardToken()) {
                rewardTokenAmount = _balance;
                continue;
            } else {
                ILiquidityGauge(rewardDistributor()).deposit_reward_token(_rewardToken, _balance);
            }
        }

        if (rewardTokenAmount > 0) {
            ERC20(rewardToken()).transfer(strategy(), rewardTokenAmount);
        }

        return rewardTokenAmount;
    }

    function notifyRewardToken(address token) external {
        /// Only the strategy can notify the reward token even if it's an extra reward.
        if (token == rewardToken()) revert UNAUTHORIZED();

        /// We assume that the reward token is already added as reward token in the gauge.
        uint256 _balance = ERC20(token).balanceOf(address(this));

        // Notify with the balance of the reward token.
        ILiquidityGauge(rewardDistributor()).deposit_reward_token(token, _balance);
    }
}
