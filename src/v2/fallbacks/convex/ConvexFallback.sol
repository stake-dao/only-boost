// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// --- Core Contracts
import "src/v2/fallbacks/BaseFallback.sol";

// --- Interfaces
import {IBooster} from "src/interfaces/IBooster.sol";
import {IBaseRewardPool} from "src/interfaces/IBaseRewardPool.sol";

/// @title ConvexFallback
/// @author Stake DAO
/// @notice Manage LP deposit/withdraw/claim into ConvexCurve
/// @dev Inherit from `BaseFallback` implementation
contract ConvexFallback is BaseFallback {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice Booster contract.
    IBooster public immutable booster;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when deposit fails
    error DEPOSIT_FAIL();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address _governance, address _token, address _fallbackRewardToken, address _strategy, address _booster)
        BaseFallback(_governance, _token, _fallbackRewardToken, _strategy)
    {
        // Set the booster contract
        booster = IBooster(_booster);

        _updatePoolIDMappings();
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal process for mapping of pool ids from ConvexCurve to LP token address
    function _updatePoolIDMappings() internal override {
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
        (,,, address crvRewards,,) = booster.poolInfo(getPid(token).pid);
        // Withdraw from ConvexCurve gauge without claiming rewards
        IBaseRewardPool(crvRewards).withdrawAndUnwrap(amount, false);

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
        returns (address[] memory rewardTokens, uint256[] memory amounts)
    {
        // Cache the pid
        Pid memory pidInfo = pids[token];

        // Only claim if the pid is initialized and there is a position
        if (!pidInfo.isInitialized) return (new address[](0), new uint256[](0));

        if (_claimExtraRewards) {
            rewardTokens = getRewardTokens(pidInfo.pid);
            amounts = new uint256[](rewardTokens.length);
        } else {
            address[] memory tokens = new address[](2);
            tokens[0] = address(rewardToken);
            tokens[1] = address(fallbackRewardToken);

            amounts = new uint256[](2);
        }

        // Get cvxLpToken address
        (,,, address rewardTokenDistributor,,) = booster.poolInfo(pidInfo.pid);

        // Withdraw from ConvexCurve gauge
        IBaseRewardPool(rewardTokenDistributor).getReward(address(this), _claimExtraRewards);

        /// Charge Fees
        amounts[0] = _chargeProtocolFees(ERC20(rewardTokens[0]).balanceOf(address(this)));

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
    function isActive(address token) external view override returns (bool) {
        // Check if the pool is initialized and not shutdown
        (,,,,, bool shutdown) = booster.poolInfo(pids[token].pid);

        // Return if the pool is initialized and not shutdown
        return pids[token].isInitialized && !shutdown;
    }

    /// @notice Get all the rewards tokens from pid corresponding to `token`
    /// @return Array of rewards tokens address
    function getRewardTokens(uint256 pid) public view override returns (address[] memory) {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = booster.poolInfo(pid);

        // Check if there is extra rewards
        uint256 extraRewardsLength = IBaseRewardPool(crvRewards).extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength + 2);
        tokens[0] = address(rewardToken);
        tokens[1] = address(fallbackRewardToken);

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            // Add the extra reward token to the array
            _token = IBaseRewardPool(crvRewards).extraRewards(i);

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
    function getPid(address token) public view override returns (Pid memory pid) {
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
