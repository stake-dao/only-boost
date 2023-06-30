// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Core Contracts
import "./BaseFallback.sol";

// --- Interfaces
import {IBaseRewardsPool} from "src/interfaces/IBaseRewardsPool.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";

/**
 * @title FallbackConvexCurve
 * @author Stake DAO
 * @notice Manage LP deposit/withdraw/claim into ConvexCurve
 * @dev Inherit from `BaseFallback` implementation
 */
contract FallbackConvexCurve is BaseFallback {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    IBoosterConvexCurve public constant BOOSTER_CONVEX_CURVE =
        IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31); // ConvexCurve booster contract

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    bool public claimOnWithdraw; // Flag to check if rewards should be claimed on withdraw

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////
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
    /**
     * @notice Update mapping of pool ids from ConvexCurve to LP token address
     */
    function setAllPidsOptimized() public override {
        // Cache the length of the pool registry
        uint256 len = BOOSTER_CONVEX_CURVE.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len;) {
            // Set pid
            _setPid(i);

            // No need to check for overflow, since i can't be bigger than 2**256 - 1
            unchecked {
                ++i;
            }
        }

        // Update the last length
        lastPidsCount = len;
    }

    /**
     * @notice Internal process for setting the pid to the mapping
     * @dev This function is only called by `setAllPidsOptimized`
     * @param index Index of the pool in the registry
     */
    function _setPid(uint256 index) internal override {
        // Get the lpToken address
        (address lpToken,,,,,) = BOOSTER_CONVEX_CURVE.poolInfo(index);

        // Map the lpToken to the pool infos
        pids[lpToken] = PidsInfo(index, true);
    }

    /**
     * @notice Check if the pid corresponding to LP token is active and initialized internally
     * @param lpToken Address of the LP token
     * @return Flag if the pool is active and initialized internally
     */
    function isActive(address lpToken) external view override returns (bool) {
        // Check if the pool is initialized and not shutdown
        (,,,,, bool shutdown) = BOOSTER_CONVEX_CURVE.poolInfo(pids[lpToken].pid);

        // Return if the pool is initialized and not shutdown
        return pids[lpToken].isInitialized && !shutdown;
    }

    /**
     * @notice Main gateway to deposit LP token into ConvexCurve
     * @dev Only callable by the strategy
     * @param lpToken Address of LP token to deposit
     * @param amount Amount of LP token to deposit
     */
    function deposit(address lpToken, uint256 amount) external override requiresAuth {
        // Approve the amount
        ERC20(lpToken).safeApprove(address(BOOSTER_CONVEX_CURVE), amount);
        // Deposit the amount into pid from ConvexCurve and stake it into gauge (true)
        BOOSTER_CONVEX_CURVE.deposit(pids[lpToken].pid, amount, true);

        emit Deposited(lpToken, amount);
    }

    /**
     * @notice Main gateway to withdraw LP token from ConvexCurve
     * @dev Only callable by the strategy
     * @param lpToken Address of LP token to withdraw
     * @param amount Amount of LP token to withdraw
     */
    function withdraw(address lpToken, uint256 amount) external override requiresAuth {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pids[lpToken].pid);
        // Withdraw from ConvexCurve gauge and claim rewards if toggle is on
        IBaseRewardsPool(crvRewards).withdrawAndUnwrap(amount, claimOnWithdraw);

        // Transfer the amount
        ERC20(lpToken).safeTransfer(curveStrategy, amount);

        emit Withdrawn(lpToken, amount);
    }

    /**
     * @notice Main gateway to claim rewards from ConvexCurve
     * @dev Only callable by the strategy
     * @param lpToken Address of LP token to claim reward from
     * @return Array of rewards tokens address
     * @return Array of rewards tokens amount
     */
    function claimRewards(address lpToken)
        external
        override
        requiresAuth
        returns (address[] memory, uint256[] memory)
    {
        // Cache rewardsTokens
        address[] memory rewardsTokens = getRewardsTokens(lpToken);
        // Cache the pid
        PidsInfo memory pidInfo = pids[lpToken];
        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized || (balanceOf(lpToken) == 0)) return (new address[](0), new uint256[](0));

        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidInfo.pid);
        // Withdraw from ConvexCurve gauge
        IBaseRewardsPool(crvRewards).getReward(address(this), rewardsTokens.length > 0 ? true : false);

        // Handle extra rewards split
        return (rewardsTokens, _handleRewards(rewardsTokens));
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////
    /**
     * @notice Get all the rewards tokens from pid corresponding to `lpToken`
     * @param lpToken Address of LP token to get rewards tokens
     * @return Array of rewards tokens address
     */
    function getRewardsTokens(address lpToken) public view override returns (address[] memory) {
        // Cache the pid
        PidsInfo memory pidInfo = pids[lpToken];
        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (new address[](0));

        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pidInfo.pid);
        // Check if there is extra rewards
        uint256 extraRewardsLength = IBaseRewardsPool(crvRewards).extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength + 2);
        tokens[0] = address(CRV);
        tokens[1] = address(CVX);

        // If there is extra rewards, add them to the array
        if (extraRewardsLength > 0) {
            for (uint256 i = 0; i < extraRewardsLength;) {
                // Add the extra reward token to the array
                tokens[i + 2] = IBaseRewardsPool(crvRewards).extraRewards(i);

                // No need to check for overflow, since i can't be bigger than 2**256 - 1
                unchecked {
                    ++i;
                }
            }
        }

        return tokens;
    }

    /**
     * @notice Get the pid corresponding to LP token
     * @param lpToken Address of LP token to get pid
     * @return Pid info struct
     */
    function getPid(address lpToken) external view override returns (PidsInfo memory) {
        return pids[lpToken];
    }

    /**
     * @notice Get the balance of the LP token on ConvexCurve
     * @param lpToken Address of LP token to get balance
     * @return Balance of the LP token on ConvexCurve
     */
    function balanceOf(address lpToken) public view override returns (uint256) {
        // Get cvxLpToken address
        (,,, address crvRewards,,) = BOOSTER_CONVEX_CURVE.poolInfo(pids[lpToken].pid);
        // Check current balance on convexCurve
        return ERC20(crvRewards).balanceOf(address(this));
    }
}
