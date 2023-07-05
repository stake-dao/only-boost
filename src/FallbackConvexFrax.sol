// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Core Contracts
import "./BaseFallback.sol";

// --- Interfaces
import {IFraxFarmERC20} from "src/interfaces/IFraxFarmERC20.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IStakingProxyConvex} from "src/interfaces/IStakingProxyConvex.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

/// @title FallbackConvexFrax
/// @author Stake DAO
/// @notice Manage LP deposit/withdraw/claim into ConvexFrax
/// @dev Inherit from `BaseFallback` implementation
contract FallbackConvexFrax is BaseFallback {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    // --- Interfaces
    /// @notice Interface for Convex Frax booster contract
    IBoosterConvexFrax public constant BOOSTER_CONVEX_FRAX =
        IBoosterConvexFrax(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa);

    /// @notice Interface for Convex Frax pool registry contract
    IPoolRegistryConvexFrax public constant POOL_REGISTRY_CONVEX_FRAX =
        IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69);

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    // --- Uints
    /// @notice Duration in seconds for locking period
    uint256 public lockingIntervalSec = 7 days;

    // --- Mappings
    /// @notice Map LP token address --> staking token contract address
    mapping(address => address) public stkTokens;

    /// @notice Map pid from convex frax -> personal vault for convex frax
    mapping(uint256 => address) public vaults;

    /// @notice Map personal vault on convex frax -> kekId
    mapping(address => bytes32) public kekIds;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when tokens are fully withdrawn from personal vault, and partially deposited back into personal vault
    /// @param token Address of the LP token
    /// @param amount Amount of LP tokens deposited
    event Redeposited(address token, uint256 amount);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address owner, Authority authority, address _curveStrategy)
        BaseFallback(owner, authority, _curveStrategy)
    {}

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Update mapping of pool ids from ConvexFrax to LP token address
    function setAllPidsOptimized() public override requiresAuth {
        _setAllPidsOptimized();
    }

    /// @notice Internal process for mapping of pool ids from ConvexCurve to LP token address
    function _setAllPidsOptimized() internal override {
        // Cache the length of the pool registry
        uint256 len = POOL_REGISTRY_CONVEX_FRAX.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len;) {
            // Get curve LP and stkToken from ConvexFrax for the corresponding index
            (address token, address stkToken) = getLP(i);

            if (token != address(0)) {
                // Map the stkToken address from ConvexFrax to the curve lp token
                stkTokens[token] = stkToken;
                // Map the pool infos to stkToken address from ConvexFrax
                // Note: this is different from the ConvexFrax fallback contract, where pid are linked to curve lp token directly
                pids[stkToken] = PidsInfo(i, true);
            }

            // No need to check for overflow, since i can't be bigger than 2**256 - 1
            unchecked {
                ++i;
            }
        }

        // Update the last length
        lastPidsCount = len;
    }

    /// @notice Check if the pid corresponding to LP token is active and initialized internally
    /// @param token Address of the LP token
    /// @return Flag if the pool is active and initialized internally
    function isActive(address token) external view override returns (bool) {
        // Check if the pid is active
        (,,,, uint8 _isActive) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pids[stkTokens[token]].pid);

        // Return if the pid is active and initialized
        return pids[stkTokens[token]].isInitialized && _isActive == 1;
    }

    /// @notice Main gateway to deposit LP token into ConvexFrax
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function deposit(address token, uint256 amount) external override requiresAuth {
        // Cache the pid
        uint256 pid = pids[stkTokens[token]].pid;

        // Create personal vault if not exist
        if (vaults[pid] == address(0)) vaults[pid] = BOOSTER_CONVEX_FRAX.createVault(pid);

        // Approve the amount
        ERC20(token).safeApprove(vaults[pid], amount);

        if (kekIds[vaults[pid]] == bytes32(0)) {
            // Stake locked curve lp on personal vault and update kekId mapping for the corresponding vault
            kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
        } else {
            // Else lock additional curve lp
            IStakingProxyConvex(vaults[pid]).lockAdditionalCurveLp(kekIds[vaults[pid]], amount);
        }

        emit Deposited(token, amount);
    }

    /// @notice Main gateway to withdraw LP token from ConvexFrax
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function withdraw(address token, uint256 amount) external override requiresAuth {
        // Cache the pid
        uint256 pid = pids[stkTokens[token]].pid;

        // Release all the locked curve lp
        IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
        // Set kekId to 0
        delete kekIds[vaults[pid]];

        // Transfer the curve lp back to user
        ERC20(token).safeTransfer(address(curveStrategy), amount);

        emit Withdrawn(token, amount);

        // If there is remaining curve lp, stake it back
        uint256 remaining = ERC20(token).balanceOf(address(this));

        if (remaining == 0) return;

        // Safe approve lp token to personal vault
        ERC20(token).safeApprove(vaults[pid], remaining);
        // Stake back the remaining curve lp
        kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);

        emit Redeposited(token, remaining);
    }

    /// @notice Main gateway to claim rewards from ConvexFrax
    /// @dev Only callable by the strategy
    /// @param token Address of LP token to claim reward from
    /// @param claimer Address of the claimer
    /// @return Array of rewards tokens address
    /// @return Array of rewards tokens amount
    function claimRewards(address token, address claimer)
        external
        override
        requiresAuth
        returns (address[] memory, uint256[] memory)
    {
        // Cache rewardsTokens
        address[] memory rewardsTokens = getRewardsTokens(token);

        // Cache the pid
        PidsInfo memory pidInfo = pids[stkTokens[token]];

        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (new address[](0), new uint256[](0));

        // Release all the locked curve lp
        IStakingProxyConvex(vaults[pidInfo.pid]).getReward(true);

        // Handle extra rewards split
        return (rewardsTokens, _handleRewards(token, rewardsTokens, claimer));
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Get all the rewards tokens from pid corresponding to `token`
    /// @param token Address of LP token to get rewards tokens
    /// @return Array of rewards tokens address
    function getRewardsTokens(address token) public view override returns (address[] memory) {
        // Cache the pid
        PidsInfo memory pidInfo = pids[stkTokens[token]];

        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (new address[](0));

        // Get all the reward tokens
        address[] memory tokens_ =
            IFraxFarmERC20(IStakingProxyConvex(vaults[pidInfo.pid]).stakingAddress()).getAllRewardTokens();

        // Create new rewards tokens empty array
        address[] memory tokens = new address[](tokens_.length + 2);

        // Add CRV and CVX to the rewards tokens
        tokens[0] = address(CRV);
        tokens[1] = address(CVX);

        for (uint256 i = 2; i < tokens.length;) {
            tokens[i] = tokens_[i - 2];

            // No need to check for overflow, since i can't be bigger than 2**256 - 1
            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /// @notice Get the pid corresponding to LP token
    /// @param token Address of LP token to get pid
    /// @return Pid info struct
    function getPid(address token) external view override returns (PidsInfo memory) {
        // Return the pid corresponding to the stkToken, corresponding to the LP token
        return pids[stkTokens[token]];
    }

    /// @notice Get the liquid balance of the LP token on ConvexFrax
    /// @dev Because LP are locked for a certain period of time, this represent the liquid balance
    /// @param token Address of LP token to get balance
    /// @return Liquid Balance of the LP token on ConvexFrax
    function balanceOf(address token) public view override returns (uint256) {
        // Cache the pid
        uint256 pid = pids[stkTokens[token]].pid;

        return balanceOf(pid);
    }

    /// @notice Get the liquid balance of the LP token on ConvexFrax
    /// @dev Because LP are locked for a certain period of time, this represent the liquid balance
    /// @param pid Pid to get the balanceOf
    /// @return Liquid Balance of the LP token on ConvexFrax
    function balanceOf(uint256 pid) public view returns (uint256) {
        IFraxUnifiedFarm.LockedStake memory infos = _getInfos(pid);

        // If the lock is not expired, then return 0, as only the liquid balance is needed
        return block.timestamp >= infos.ending_timestamp ? infos.liquidity : 0;
    }

    /// @notice Get the locked balance of the LP token on ConvexFrax
    /// @dev Because LP are locked for a certain period of time, this represent the locked balance
    /// @param pid Pid to get the balanceOf
    /// @return Liquid Balance of the LP token on ConvexFrax
    function balanceOfLocked(uint256 pid) public view returns (uint256) {
        IFraxUnifiedFarm.LockedStake memory infos = _getInfos(pid);

        // If the lock is not expired, then return locked balance
        return block.timestamp >= infos.ending_timestamp ? 0 : infos.liquidity;
    }

    /// @notice Get the Locked Stake infos
    /// @param pid Pid to get the infos
    /// @return infos LockedStake struct
    function _getInfos(uint256 pid) internal view returns (IFraxUnifiedFarm.LockedStake memory infos) {
        (, address staking,,,) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pid);
        // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
        // and the last one is emptyed. So we need to get the last one.
        uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);

        // If no lockedStakes, return 0
        if (lockCount == 0) return infos;

        // Cache lockedStakes infos
        infos = IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];
    }

    /// @notice Get the LP token and stkToken address from corresponding pid
    /// @param pid Pid of the pool
    /// @return Address of LP token
    /// @return Address of the stkToken
    function getLP(uint256 pid) public returns (address, address) {
        // Get the staking token address
        (,, address stkToken,,) = POOL_REGISTRY_CONVEX_FRAX.poolInfo(pid);

        // Get the underlying curve lp token address
        (bool success, bytes memory data) = stkToken.call(abi.encodeWithSignature("curveToken()"));

        // Return the curve lp token address if call succeed otherwise return address(0)
        return success ? (abi.decode(data, (address)), stkToken) : (address(0), stkToken);
    }
}
