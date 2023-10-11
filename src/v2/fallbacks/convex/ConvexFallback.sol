// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "src/v2/fallbacks/Fallback.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {IBaseRewardPool} from "src/interfaces/IBaseRewardPool.sol";

/// @title ConvexFallback
/// @author Stake DAO
/// @notice Manage LP deposit/withdraw/claim into Convex like platforms.
contract ConvexFallback is Fallback {
    using SafeTransferLib for ERC20;

    /// @notice Booster contract.
    IBooster public immutable booster;

    constructor(address _governance, address _token, address _fallbackRewardToken, address _strategy, address _booster)
        Fallback(_governance, _token, _fallbackRewardToken, _strategy)
    {
        // Set the booster contract
        booster = IBooster(_booster);

        updatePoolIDMappings();
    }

    /// @notice Internal process for mapping of pool ids from ConvexCurve to LP token address
    function updatePoolIDMappings() public {
        // Cache the length of the pool registry
        uint256 len = booster.poolLength();

        // If the length is the same, no need to update
        if (lastPid == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPid; i < len;) {
            // Get the LP token address
            (address _token,,,,, bool _isShutdown) = booster.poolInfo(i);

            // Map the LP token to the pool infos
            pids[_token] = Pid(i, _isShutdown);

            unchecked {
                ++i;
            }
        }

        // Update the last length
        lastPid = len;
    }

    /// @notice Main gateway to deposit LP token into ConvexCurve
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function deposit(address token, uint256 amount) external override onlyStrategy {
        // Approve the amount
        ERC20(token).safeApprove(address(booster), amount);
        // Deposit the amount into pid from ConvexCurve and stake it into gauge (true)
        booster.deposit(getPid(token).pid, amount, true);

        emit Deposited(token, amount);
    }

    /// @notice Main gateway to withdraw LP token from ConvexCurve
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function withdraw(address token, uint256 amount) external override onlyStrategy {
        // Get cvxLpToken address
        (,,, address rewardTokenDistributor,,) = booster.poolInfo(getPid(token).pid);

        // Withdraw from ConvexCurve gauge without claiming rewards
        IBaseRewardPool(rewardTokenDistributor).withdrawAndUnwrap(amount, false);

        // Transfer the amount
        ERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(token, amount);
    }

    /// @notice Main gateway to claim rewards from ConvexCurve
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to claim reward from
    /// @return rewardTokens Array of rewards tokens address
    /// @return amounts Array of rewards tokens amount
    function claimRewards(address token, bool _claimExtraRewards)
        external
        onlyStrategy
        returns (address[] memory rewardTokens, uint256[] memory amounts, uint256 _protocolFees)
    {
        /// Check if the pid is initialized.
        Pid memory pidInfo = pids[token];

        // Only claim if the pid is initialized and there is a position.
        if (!pidInfo.isInitialized) return (new address[](0), new uint256[](0), 0);

        /// Get RewardDistributor address.
        (,,, address rewardTokenDistributor,,) = booster.poolInfo(pidInfo.pid);

        /// We can save gas by not claiming extra rewards if we don't need them, there's no extra rewards, or not enough rewards worth to claim.
        if (_claimExtraRewards) {
            /// This will return at least 2 reward tokens, rewardToken and fallbackRewardToken.
            rewardTokens = getRewardTokens(rewardTokenDistributor);
        } else {
            rewardTokens = new address[](2);
            rewardTokens[0] = address(rewardToken);
            rewardTokens[1] = address(fallbackRewardToken);
        }

        amounts = new uint256[](rewardTokens.length);

        /// Claim rewardToken, fallbackRewardToken and _extraRewardTokens if _claimExtraRewards is true.
        IBaseRewardPool(rewardTokenDistributor).getReward(address(this), _claimExtraRewards);

        /// Charge Fees.
        /// Amounts[0] is the amount of rewardToken claimed.
        (amounts[0], _protocolFees) = _chargeProtocolFees(ERC20(rewardTokens[0]).balanceOf(address(this)));

        /// Transfer the reward token to the claimer
        ERC20(rewardTokens[0]).safeTransfer(msg.sender, amounts[0]);

        for (uint256 i = 1; i < rewardTokens.length;) {
            // Get the balance of the reward token
            amounts[i] = ERC20(rewardTokens[i]).balanceOf(address(this));

            // Transfer the reward token to the claimer
            ERC20(rewardTokens[i]).safeTransfer(msg.sender, amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Check if the pid corresponding to LP token is active and initialized internally
    /// @param token Address of the LP token
    /// @return Flag if the pool is active and initialized internally
    function isActive(address token) external view returns (bool) {
        // Check if the pool is initialized and not shutdown
        (,,,,, bool shutdown) = booster.poolInfo(pids[token].pid);

        // Return if the pool is initialized and not shutdown
        return pids[token].isInitialized && !shutdown;
    }

    /// @notice Get all the rewards tokens from pid corresponding to `token`
    /// @return Array of rewards tokens address
    function getRewardTokens(address rewardTokenDistributor) public view returns (address[] memory) {
        // Check if there is extra rewards
        uint256 extraRewardsLength = IBaseRewardPool(rewardTokenDistributor).extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength + 2);
        tokens[0] = address(rewardToken);
        tokens[1] = address(fallbackRewardToken);

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            // Add the extra reward token to the array
            _token = IBaseRewardPool(rewardTokenDistributor).extraRewards(i);

            /// Try Catch to see if the token is a valid ERC20
            try ERC20(_token).decimals() returns (uint8) {
                tokens[i + 2] = _token;
            } catch {
                tokens[i + 2] = IBaseRewardPool(_token).rewardToken();
            }

            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /// @notice Get the pid corresponding to LP token
    /// @param token Address of LP token to get pid
    /// @return pid Pid info struct
    function getPid(address token) public view returns (Pid memory pid) {
        // Get the pid infos
        pid = pids[token];

        // Revert if the pid is initialized
        if (!pid.isInitialized) revert NOT_VALID_PID();
    }

    /// @notice Get the balance of the LP token on ConvexCurve
    /// @param token Address of LP token to get balance
    /// @return Balance of the LP token on ConvexCurve
    function balanceOf(address token) public view override returns (uint256) {
        // Cache PID
        Pid memory pidInfo = pids[token];
        // Get cvxLpToken address
        (,,, address crvRewards,,) = booster.poolInfo(pidInfo.pid);

        // Return the balance of the LP token on ConvexCurve if initialized, else 0
        return pidInfo.isInitialized ? ERC20(crvRewards).balanceOf(address(this)) : 0;
    }
}
