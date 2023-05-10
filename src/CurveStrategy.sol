// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Optimizor} from "src/Optimizor.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract CurveStrategy is Auth {
    using FixedPointMathLib for uint256;

    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker

    Optimizor public optimizor;
    IBoosterConvexCurve public boosterConvexCurve; // Convex booster
    IPoolRegistryConvexFrax public poolRegistryConvexFrax; // ConvexFrax pool Registry

    uint256 public pidsCountConvexFrax; // Number of pools on ConvexFrax
    uint256 public pidsCountConvexCurve; // Number of pools on ConvexCurve
    mapping(address => address) public gauges; // token address --> gauge address
    mapping(address => uint256) public pidsConvexFrax; // lpToken address --> pool ids from convexFrax
    mapping(address => uint256) public pidsConvexCurve; // lpToken address --> pool ids from convexCurve

    error ADDRESS_NULL();
    error WRONG_LENGTH();

    constructor(Authority _authority, Optimizor _optimizor) Auth(msg.sender, _authority) {
        optimizor = _optimizor;
        boosterConvexCurve = IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69);

        // --- Map pool address to pids on ConvexFrax --- ///
        uint256 len = poolRegistryConvexFrax.poolLength();
        for (uint16 i; i < len; ++i) {
            setPidOnConvexFrax(i);
        }
    }

    function setPidOnConvexFrax(uint256 index) public {
        (,, address lpToken,,) = poolRegistryConvexFrax.poolInfo(index);

        // If the lpToken is not in the list, add it
        if (pidsConvexFrax[lpToken] == 0) ++pidsCountConvexFrax;

        // Set the lpToken address
        pidsConvexFrax[lpToken] = index;
    }

    function setPidOnConvexCurve(uint256 index) public {
        (address lpToken,,,,,) = boosterConvexCurve.poolInfo(index);

        // If the lpToken is not in the list, add it
        if (pidsConvexFrax[lpToken] == 0) ++pidsCountConvexCurve;

        // Set the lpToken address
        pidsConvexCurve[lpToken] = index;
    }

    function setAllPidsOnConvexFraxOptimized() public {
        // Cache the length of the pool registry
        uint256 len = poolRegistryConvexFrax.poolLength();

        // If the length is the same, no need to update
        if (pidsCountConvexFrax == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = pidsCountConvexFrax; i < len; ++i) {
            setPidOnConvexFrax(i);
        }
    }

    function setAllPidsOnConvexCurveOptimized() public {
        // Cache the length of the pool registry
        uint256 len = boosterConvexCurve.poolLength();

        // If the length is the same, no need to update
        if (pidsCountConvexCurve == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = pidsCountConvexCurve; i < len; ++i) {
            setPidOnConvexCurve(i);
        }
    }

    function deposit(address token, uint256 amount) external {
        // Only vault can call this function

        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // === Checks if on convexFrax === //
        // Update pids mapping if needed
        setAllPidsOnConvexFraxOptimized();
        // Check if the pool is active on convexFrax
        (,,,, uint8 isActive) = poolRegistryConvexFrax.poolInfo(pidsConvexFrax[token]);
        // Convert to bool and cache it
        bool isOnConvexFrax = isActive == 1;
        // === ---------------------- === //

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

        // Deposit on Convex
        if (amount > 0) {
            if (isOnConvexFrax) {
                // Deposit on ConvexFrax
            } else {
                // Deposit on ConvexCurve
            }
        }
    }

    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return (a < b) ? a : b;
    }
}
