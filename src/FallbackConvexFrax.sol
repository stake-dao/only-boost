// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "./BaseFallback.sol";

import {IFraxFarmERC20} from "src/interfaces/IFraxFarmERC20.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IStakingProxyConvex} from "src/interfaces/IStakingProxyConvex.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract FallbackConvexFrax is BaseFallback {
    using SafeTransferLib for ERC20;

    IBoosterConvexFrax public constant BOOSTER = IBoosterConvexFrax(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa); // Convex Frax booster
    IPoolRegistryConvexFrax public constant POOL_REGISTRY =
        IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69); // ConvexFrax pool Registry

    uint256 public lockingIntervalSec = 7 days; // 7 days

    mapping(address => address) public stkTokens; // lpToken address --> staking token contract address
    mapping(uint256 => address) public vaults; // pid from convex frax -> personal vault for convex frax
    mapping(address => bytes32) public kekIds; // personal vault on convex frax -> kekId

    event Redeposited(address lpToken, uint256 amount);

    constructor(address owner, Authority authority, address _curveStrategy)
        BaseFallback(owner, authority, _curveStrategy)
    {
        setAllPidsOptimized();
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////
    function setAllPidsOptimized() public override {
        // Cache the length of the pool registry
        uint256 len = POOL_REGISTRY.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len; ++i) {
            _setPid(i);
        }

        // Update the last length
        lastPidsCount = len;
    }

    function _setPid(uint256 index) internal override {
        (address lpToken, address stkToken) = getLP(index);

        if (lpToken != address(0)) {
            // Map the stkToken address from ConvexFrax to the curve lp token
            stkTokens[lpToken] = stkToken;
            // Map the pool infos to stkToken address from ConvexFrax
            pids[stkToken] = PidsInfo(index, true);
        }
    }

    function isActive(address lpToken) external override returns (bool) {
        setAllPidsOptimized();

        (,,,, uint8 _isActive) = POOL_REGISTRY.poolInfo(pids[stkTokens[lpToken]].pid);
        return pids[stkTokens[lpToken]].isInitialized && _isActive == 1;
    }

    function deposit(address lpToken, uint256 amount) external override requiresAuth {
        // Cache the pid
        uint256 pid = pids[stkTokens[lpToken]].pid;

        // Create personal vault if not exist
        if (vaults[pid] == address(0)) vaults[pid] = BOOSTER.createVault(pid);

        // Approve the amount
        ERC20(lpToken).safeApprove(vaults[pid], amount);

        if (kekIds[vaults[pid]] == bytes32(0)) {
            // If no kekId, stake locked curve lp
            kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
        } else {
            // Else lock additional curve lp
            IStakingProxyConvex(vaults[pid]).lockAdditionalCurveLp(kekIds[vaults[pid]], amount);
        }

        emit Deposited(lpToken, amount);
    }

    function withdraw(address lpToken, uint256 amount) external override requiresAuth {
        // Cache the pid
        uint256 pid = pids[stkTokens[lpToken]].pid;

        // Release all the locked curve lp
        IStakingProxyConvex(vaults[pid]).withdrawLockedAndUnwrap(kekIds[vaults[pid]]);
        // Set kekId to 0
        delete kekIds[vaults[pid]];

        // Transfer the curve lp back to user
        ERC20(lpToken).safeTransfer(address(curveStrategy), amount);

        emit Withdrawn(lpToken, amount);

        // If there is remaining curve lp, stake it back
        uint256 remaining = ERC20(lpToken).balanceOf(address(this));

        if (remaining == 0) return;

        // Safe approve lp token to personal vault
        ERC20(lpToken).safeApprove(vaults[pid], remaining);
        // Stake back the remaining curve lp
        kekIds[vaults[pid]] = IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(remaining, lockingIntervalSec);

        emit Redeposited(lpToken, remaining);
    }

    function claimRewards(address lpToken, address[] calldata rewardsTokens) external override requiresAuth {
        // Cache the pid
        PidsInfo memory pidInfo = pids[stkTokens[lpToken]];

        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return;

        // Release all the locked curve lp
        IStakingProxyConvex(vaults[pidInfo.pid]).getReward(true);

        // Handle extra rewards split
        _handleRewards(lpToken, rewardsTokens);
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////
    function getRewardsTokens(address lpToken) public view override returns (address[] memory) {
        // Cache the pid
        PidsInfo memory pidInfo = pids[stkTokens[lpToken]];

        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (new address[](0));

        address[] memory tokens_ =
            IFraxFarmERC20(IStakingProxyConvex(vaults[pidInfo.pid]).stakingAddress()).getAllRewardTokens();
        address[] memory tokens = new address[](tokens_.length + 2);

        tokens[0] = address(CRV);
        tokens[1] = address(CVX);
        for (uint256 i = 2; i < tokens.length; ++i) {
            tokens[i] = tokens_[i - 2];
        }

        return tokens;
    }

    function getPid(address lpToken) external view override returns (PidsInfo memory) {
        return pids[stkTokens[lpToken]];
    }

    function balanceOf(address lpToken) external view override returns (uint256) {
        // Cache the pid
        uint256 pid = pids[stkTokens[lpToken]].pid;

        return balanceOf(pid);
    }

    function balanceOf(uint256 pid) public view returns (uint256) {
        // Withdraw from ConvexFrax
        (, address staking,,,) = POOL_REGISTRY.poolInfo(pid);
        // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
        // and the last one is emptyed. So we need to get the last one.
        uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);

        // If no lockedStakes, return 0
        if (lockCount == 0) return 0;

        // Cache lockedStakes infos
        IFraxUnifiedFarm.LockedStake memory infos = IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];

        return block.timestamp >= infos.ending_timestamp ? infos.liquidity : 0;
    }

    function getLP(uint256 pid) public returns (address, address) {
        // Get the staking token address
        (,, address stkToken,,) = POOL_REGISTRY.poolInfo(pid);

        // Get the underlying curve lp token address
        (bool success, bytes memory data) = stkToken.call(abi.encodeWithSignature("curveToken()"));

        // Return the curve lp token address if call succeed otherwise return address(0)
        return success ? (abi.decode(data, (address)), stkToken) : (address(0), stkToken);
    }
}
