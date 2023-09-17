// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// --- Core Contracts
import "./BaseFallback.sol";

// --- Interfaces
import {IBaseRewardsPool} from "src/interfaces/IBaseRewardsPool.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";

/// @title ConvexFallback
/// @author Stake DAO
/// @notice Manage LP deposit/withdraw/claim into ConvexCurve
/// @dev Inherit from `BaseFallback` implementation
contract ConvexFallback is BaseFallback {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice Interface for ConvexCurve booster contract
    IBoosterConvexCurve public constant BOOSTER_CONVEX_CURVE =
        IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////
    /// @notice Error emitted when deposit fails
    error DEPOSIT_FAIL();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address owner, Authority authority, address _curveStrategy)
        BaseFallback(owner, authority, _curveStrategy)
    {}

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Update mapping of pool ids from ConvexCurve to LP token address
    function setAllPidsOptimized() public override requiresAuth {
        _setAllPidsOptimized();
    }

    /// @notice Internal process for mapping of pool ids from ConvexCurve to LP token address
    function _setAllPidsOptimized() internal override {
        // Cache the length of the pool registry
        uint256 len = BOOSTER_CONVEX_CURVE.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len;) {
            // Get the LP token address
            (address token,,,,,) = BOOSTER_CONVEX_CURVE.poolInfo(i);

            // Map the LP token to the pool infos
            pids[token] = PidsInfo(i, true);

            unchecked {
                ++i;
            }
        }

        // Update the last length
        lastPidsCount = len;
    }

    /// @notice Main gateway to deposit LP token into ConvexCurve
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function deposit(address token, uint256 amount) external override onlyStrategy {
        // Approve the amount
        ERC20(token).safeApprove(address(BOOSTER_CONVEX_CURVE), amount);
        // Deposit the amount into pid from ConvexCurve and stake it into gauge (true)
        BOOSTER_CONVEX_CURVE.deposit(getPid(token).pid, amount, true);

        emit Deposited(token, amount);
    }

    /// @notice Main gateway to withdraw LP token from ConvexCurve
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function withdraw(address token, uint256 amount) external override onlyStrategy {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(getPid(token).pid);
        // Withdraw from ConvexCurve gauge without claiming rewards
        IBaseRewardsPool(crvRewards).withdrawAndUnwrap(amount, false);

        // Transfer the amount
        ERC20(token).safeTransfer(curveStrategy, amount);

        emit Withdrawn(token, amount);
    }

    /// @notice Main gateway to claim rewards from ConvexCurve
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to claim reward from
    /// @param claimer Address of the claimer
    /// @return Array of rewards tokens address
    /// @return Array of rewards tokens amount
    function claimRewards(address token, address claimer)
        external
        override
        onlyStrategy
        returns (address[] memory, uint256[] memory)
    {
        // Cache rewardsTokens
        address[] memory rewardsTokens = getRewardsTokens(token);

        // Cache the pid
        PidsInfo memory pidInfo = pids[token];
        // Only claim if the pid is initialized and there is a position
        if (!pidInfo.isInitialized) return (new address[](0), new uint256[](0));

        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidInfo.pid);
        // Withdraw from ConvexCurve gauge
        IBaseRewardsPool(crvRewards).getReward(address(this), rewardsTokens.length > 2 ? true : false);

        // Handle extra rewards split
        return (rewardsTokens, _handleRewards(token, rewardsTokens, claimer));
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Check if the pid corresponding to LP token is active and initialized internally
    /// @param token Address of the LP token
    /// @return Flag if the pool is active and initialized internally
    function isActive(address token) external view override returns (bool) {
        // Check if the pool is initialized and not shutdown
        (,,,,, bool shutdown) = BOOSTER_CONVEX_CURVE.poolInfo(pids[token].pid);

        // Return if the pool is initialized and not shutdown
        return pids[token].isInitialized && !shutdown;
    }

    /// @notice Get all the rewards tokens from pid corresponding to `token`
    /// @param token Address of LP token to get rewards tokens
    /// @return Array of rewards tokens address
    function getRewardsTokens(address token) public view override returns (address[] memory) {
        // Cache the pid
        PidsInfo memory pidInfo = pids[token];
        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (new address[](0));

        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidInfo.pid);

        // Check if there is extra rewards
        uint256 extraRewardsLength = IBaseRewardsPool(crvRewards).extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength + 2);
        tokens[0] = address(CRV);
        tokens[1] = address(CVX);

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            // Add the extra reward token to the array
            _token = IBaseRewardsPool(crvRewards).extraRewards(i);

            /// Try Catch to see if the token is a valid ERC20
            try ERC20(_token).decimals() returns (uint8) {
                tokens[i + 2] = _token;
            } catch {
                tokens[i + 2] = IBaseRewardsPool(_token).rewardToken();
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
    function getPid(address token) public view override returns (PidsInfo memory pid) {
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
        PidsInfo memory pidInfo = pids[token];
        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidInfo.pid);

        // Return the balance of the LP token on ConvexCurve if initialized, else 0
        return pidInfo.isInitialized ? ERC20(crvRewards).balanceOf(address(this)) : 0;
    }
}
