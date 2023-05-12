// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Optimizor} from "src/Optimizor.sol";
import {ConvexMapper} from "src/ConvexMapper.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IStakingProxyConvex} from "src/interfaces/IStakingProxyConvex.sol";

contract CurveStrategy is Auth {
    using SafeTransferLib for ERC20;

    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker

    Optimizor public optimizor;
    ConvexMapper public convexMapper;
    IBoosterConvexFrax public boosterConvexFrax; // Convex Frax booster

    uint256 public lockingIntervalSec = 7 days; // 7 days

    mapping(address => address) public gauges; // token address --> gauge address
    mapping(uint256 => address) public vaults; // pid --> vault address
    mapping(address => bytes32) public kekIds; // vault address --> kekId

    error ADDRESS_NULL();
    error DEPOSIT_FAIL();

    constructor(Authority _authority) Auth(msg.sender, _authority) {
        optimizor = new Optimizor();
        convexMapper = new ConvexMapper();
        boosterConvexFrax = IBoosterConvexFrax(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa);
    }

    function deposit(address token, uint256 amount) external {
        // Only vault can call this function

        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Check if the pool is active on convexFrax
        (bool isOnConvexFrax, uint256 pid) = convexMapper.getPid(token);

        // Call the optimizor to get the optimal amount to deposit in Stake DAO
        uint256 result = optimizor.optimization(gauge, isOnConvexFrax);

        // Deposit first on Stake DAO
        uint256 balanceStakeDAO = ERC20(gauge).balanceOf(address(LOCKER_STAKEDAO));
        if (balanceStakeDAO < result) {
            // Calculate amount to deposit
            uint256 toDeposit = min(result - balanceStakeDAO, amount);
            // Update amount, cannot underflow due to previous min()
            amount -= toDeposit;

            // Approve LOCKER_STAKEDAO to spend token
            LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
            LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, toDeposit));

            // Locker deposit token
            (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", toDeposit));
            require(success, "Deposit failed!");
        }

        // Deposit all the remaining on Convex
        if (amount > 0) {
            if (isOnConvexFrax) {
                // Deposit on ConvexFrax
                if (vaults[pid] == address(0)) {
                    // Create personal vault if not exist
                    vaults[pid] = boosterConvexFrax.createVault(pid);
                }
                // Safe approve lp token to personal vault
                ERC20(token).safeApprove(vaults[pid], amount);

                if (kekIds[vaults[pid]] == bytes32(0)) {
                    // If no kekId, stake locked curve lp
                    kekIds[vaults[pid]] =
                        IStakingProxyConvex(vaults[pid]).stakeLockedCurveLp(amount, lockingIntervalSec);
                } else {
                    // Else lock additional curve lp
                    IStakingProxyConvex(vaults[pid]).lockAdditionalCurveLp(kekIds[vaults[pid]], amount);
                }
            } else {
                // Deposit on ConvexCurve
                // Cache Convex Curve booster address
                IBoosterConvexCurve convex = convexMapper.boosterConvexCurve();
                // Safe approve lp token to convex curve booster
                ERC20(token).safeApprove(address(convex), amount);
                // Deposit on ConvexCurve
                if (!convex.deposit(pid, amount, true)) revert DEPOSIT_FAIL();
            }
        }
    }

    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return (a < b) ? a : b;
    }
}
