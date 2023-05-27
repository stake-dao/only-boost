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
    using FixedPointMathLib for uint256;

    IBoosterConvexFrax public boosterConvexFrax; // Convex Frax booster
    IPoolRegistryConvexFrax public poolRegistryConvexFrax; // ConvexFrax pool Registry
    ERC20 public constant FXS = ERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);

    address public curveStrategy;
    uint256 public lockingIntervalSec = 7 days; // 7 days

    mapping(address => address) public stkTokens; // lpToken address --> staking token contract address
    mapping(uint256 => address) public vaults; // pid from convex frax -> personal vault for convex frax
    mapping(address => bytes32) public kekIds; // personal vault on convex frax -> kekId

    event Redeposited(address lpToken, uint256 amount);

    constructor(address _curveStrategy) {
        boosterConvexFrax = IBoosterConvexFrax(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa);
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69);
        curveStrategy = _curveStrategy;

        setAllPidsOptimized();
    }

    function setPid(uint256 index) public override {
        (address lpToken, address stkToken) = getLP(index);

        if (lpToken != address(0)) {
            // Map the stkToken address from ConvexFrax to the curve lp token
            stkTokens[lpToken] = stkToken;
            // Map the pool infos to stkToken address from ConvexFrax
            pids[stkToken] = PidsInfo(index, true);
        }
    }

    function getLP(uint256 pid) public returns (address, address) {
        // Get the staking token address
        (,, address stkToken,,) = poolRegistryConvexFrax.poolInfo(pid);

        // Get the underlying curve lp token address
        (bool success, bytes memory data) = stkToken.call(abi.encodeWithSignature("curveToken()"));

        // Return the curve lp token address if call succeed otherwise return address(0)
        return success ? (abi.decode(data, (address)), stkToken) : (address(0), stkToken);
    }

    function setAllPidsOptimized() public override {
        // Cache the length of the pool registry
        uint256 len = poolRegistryConvexFrax.poolLength();

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

        (,,,, uint8 _isActive) = poolRegistryConvexFrax.poolInfo(pids[stkTokens[lpToken]].pid);
        return pids[stkTokens[lpToken]].isInitialized && _isActive == 1;
    }

    function balanceOf(address lpToken) external view override returns (uint256) {
        // Cache the pid
        uint256 pid = pids[stkTokens[lpToken]].pid;

        return balanceOf(pid);
    }

    function balanceOf(uint256 pid) public view returns (uint256) {
        // Withdraw from ConvexFrax
        (, address staking,,,) = poolRegistryConvexFrax.poolInfo(pid);
        // On each withdraw all LP are withdraw and only the remaining is locked, so a new lockedStakes is created
        // and the last one is emptyed. So we need to get the last one.
        uint256 lockCount = IFraxUnifiedFarm(staking).lockedStakesOfLength(vaults[pid]);

        // If no lockedStakes, return 0
        if (lockCount == 0) return 0;

        // Cache lockedStakes infos
        IFraxUnifiedFarm.LockedStake memory infos = IFraxUnifiedFarm(staking).lockedStakesOf(vaults[pid])[lockCount - 1];

        return block.timestamp >= infos.ending_timestamp ? infos.liquidity : 0;
    }

    function deposit(address lpToken, uint256 amount) external override {
        // Cache the pid
        uint256 pid = pids[stkTokens[lpToken]].pid;

        // Create personal vault if not exist
        if (vaults[pid] == address(0)) vaults[pid] = boosterConvexFrax.createVault(pid);

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

    function withdraw(address lpToken, uint256 amount) external override {
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

    function claimRewards(address lpToken)
        external
        override
        returns (address[10] memory tokens, uint256[10] memory amounts)
    {
        // Todo: add possibility to charges fees

        // Cache the pid
        PidsInfo memory pidInfo = pids[stkTokens[lpToken]];

        // Only claim if the pid is initialized
        if (!pidInfo.isInitialized) return (tokens, amounts);

        // Release all the locked curve lp
        IStakingProxyConvex(vaults[pidInfo.pid]).getReward(true);

        // Transfer CRV rewards to strategy and charge fees
        amounts[0] = CRV.balanceOf(address(this));
        if (amounts[0] > 0) {
            uint256 feeAmount;
            tokens[0] = address(CRV);
            if (feesOnRewards > 0) {
                feeAmount = amounts[0].mulWadDown(feesOnRewards);
                CRV.safeTransfer(feesReceiver, feeAmount);
            }
            CRV.safeTransfer(msg.sender, amounts[0] - feeAmount);
        }
        // Transfer CVX rewards to strategy and charge fees
        amounts[1] = CVX.balanceOf(address(this));
        if (amounts[1] > 0) {
            uint256 feeAmount;
            tokens[1] = address(CVX);
            if (feesOnRewards > 0) {
                feeAmount = amounts[1].mulWadDown(feesOnRewards);
                CVX.safeTransfer(feesReceiver, feeAmount);
            }
            CVX.safeTransfer(msg.sender, amounts[1] - feeAmount);
        }
        // Transfer FXS rewards to strategy and charge fees
        amounts[2] = FXS.balanceOf(address(this));
        if (amounts[2] > 0) {
            uint256 feeAmount;
            tokens[2] = address(FXS);
            if (feesOnRewards > 0) {
                feeAmount = amounts[2].mulWadDown(feesOnRewards);
                FXS.safeTransfer(feesReceiver, feeAmount);
            }
            FXS.safeTransfer(msg.sender, amounts[2] - feeAmount);
        }

        // Handle extra rewards
        address[] memory rewardTokens =
            IFraxFarmERC20(IStakingProxyConvex(vaults[pidInfo.pid]).stakingAddress()).getAllRewardTokens();

        uint256 len = rewardTokens.length;
        if (len > 0) {
            for (uint256 i = 0; i < len; ++i) {
                amounts[i + 3] = ERC20(rewardTokens[i]).balanceOf(address(this));
                if (amounts[i + 3] > 0) {
                    tokens[i + 3] = rewardTokens[i];
                    uint256 feeAmount;

                    if (feesOnRewards > 0) {
                        feeAmount = amounts[i + 3].mulWadDown(feesOnRewards);
                        ERC20(rewardTokens[i]).safeTransfer(feesReceiver, feeAmount);
                    }
                    ERC20(rewardTokens[i]).safeTransfer(msg.sender, amounts[i + 3] - feeAmount);
                }
            }
        }

        emit ClaimedRewards(lpToken, amounts[0], amounts[1]);
    }

    function getPid(address lpToken) external view override returns (PidsInfo memory) {
        return pids[stkTokens[lpToken]];
    }
}
