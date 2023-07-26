// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// --- Core Contracts
import {CurveStrategy} from "src/CurveStrategy.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

// --- Interfaces
import {ICVXLocker} from "src/interfaces/ICVXLocker.sol";

/// @title Optimizor
/// @author Stake DAO
/// @notice External module for Stake DAO Strategy to optimize the deposit and withdraw between LiquidLockers and Fallbacks
/// @dev Inherits from Solmate `Auth` implementatio
contract Optimizor is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- STRUCTS
    //////////////////////////////////////////////////////

    /// @notice Struct to store cached optimization values and timestamp
    /// @param value Cached optimization value
    /// @param timestamp Timestamp of the cached optimization
    struct CachedOptimization {
        uint256 value;
        uint256 timestamp;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    // --- ERC20
    /// @notice Curve DAO ERC20 CRV Token
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    /// @notice Convex ERC20 CVX Token
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    // --- Addresses
    /// @notice Curve DAO CRV Vote-escrow contract
    address public constant LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    /// @notice Convex CVX Vote-escrow contract
    address public constant LOCKER_CVX = 0xD18140b4B819b895A3dba5442F959fA44994AF50;

    /// @notice Convex CRV Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice StakeDAO CRV Locker
    address public constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    // --- Uints
    /// @notice Fees on Convex
    uint256 public constant FEES_CONVEX = 17e16;

    /// @notice Fees on StakeDAO
    uint256 public constant FEES_STAKEDAO = 16e16;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    // --- Contracts
    /// @notice Stake DAO Curve Strategy
    CurveStrategy public curveStrategy;

    /// @notice Stake DAO Fallback Convex Curve
    FallbackConvexCurve public fallbackConvexCurve;

    // --- Addresses
    /// @notice List of fallbacks
    address[] public fallbacks;

    // --- Bools
    /// @notice Use last optimization value
    bool public useLastOpti;

    // --- Uints
    /// @notice veCRV difference threshold to trigger a new optimal amount calculation, 5e16 = 5%
    uint256 public veCRVDifferenceThreshold = 5e16;

    /// @notice Cached veCRV value for Stake DAO Liquidity Locker
    uint256 public cacheVeCRVLockerBalance;

    /// @notice Cache period for optimization
    uint256 public cachePeriod = 7 days;

    // --- Mappings
    /// @notice Map liquidityGauge => CachedOptimization
    mapping(address => CachedOptimization) public lastOpti;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////
    /// @notice Error emitted when not enough time has passed
    error TOO_SOON();

    /// @notice Error emitted when amount is wrong
    error WRONG_AMOUNT();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address owner, Authority authority, address _curveStrategy, address _fallbackConvexCurve)
        Auth(owner, authority)
    {
        fallbackConvexCurve = FallbackConvexCurve(_fallbackConvexCurve);
        curveStrategy = CurveStrategy(_curveStrategy);

        fallbacks.push(LOCKER);
        fallbacks.push(address(fallbackConvexCurve));
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STAKEDAO
    //////////////////////////////////////////////////////

    /// @notice Return the optimal amount of LP token that must be held by Stake DAO Liquidity Locker
    /// @param liquidityGauge Addres of the liquidity gauge
    /// @return Optimal amount of LP token
    function optimalAmount(address liquidityGauge, uint256 veCRVStakeDAO) public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVTotal = ERC20(LOCKER_CRV).totalSupply(); // New

        // Liquidity Gauge
        uint256 totalSupply = ERC20(liquidityGauge).totalSupply(); // New
        uint256 balanceConvex = ERC20(liquidityGauge).balanceOf(LOCKER_CONVEX);

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;

        // Additional boost
        uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Result
        return (
            3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
                / (
                    (2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply
                        + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
                )
        );
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STRATEGIE DEPOSIT & WITHDRAW
    //////////////////////////////////////////////////////

    /// @notice Return the amount that need to be deposited StakeDAO Liquid Locker and on each fallback
    /// @dev This is not a view due to the cache system
    /// @param token Address of LP token to deposit
    /// @param liquidityGauge Address of Liquidity Gauge corresponding to LP token
    /// @param amount Amount of LP token to deposit
    /// @return Array of addresses to deposit in, Stake DAO LiquidLocker always first
    /// @return Array of amounts to deposit in
    function optimizeDeposit(address token, address liquidityGauge, uint256 amount)
        public
        requiresAuth
        returns (address[] memory, uint256[] memory)
    {
        // Check if the lp token has pool on ConvexCurve
        bool statusCurve = fallbackConvexCurve.isActive(token);

        uint256[] memory amounts = new uint256[](2);

        // Cache Stake DAO Liquid Locker veCRV balance
        uint256 veCRVLocker = ERC20(LOCKER_CRV).balanceOf(LOCKER);

        // If available on Convex Curve
        if (statusCurve) {
            // Get the optimal amount of lps that must be held by the locker
            uint256 opt = _getOptimalAmount(liquidityGauge, veCRVLocker);

            // Get the balance of the locker on the liquidity gauge
            uint256 gaugeBalance = ERC20(liquidityGauge).balanceOf(address(LOCKER));

            // Stake DAO Curve
            amounts[0] = opt > gaugeBalance ? min(opt - gaugeBalance, amount) : 0;
            // Convex Curve
            amounts[1] = amount - amounts[0];
        }
        // If not available on Convex Curve
        else {
            // Stake DAO Curve
            amounts[0] = amount;
            // Convex Curve
            // amounts[1] = 0;
        }

        return (fallbacks, amounts);
    }

    /// @notice Calcul the optimal amount of lps that must be held by the locker or use the cached value
    /// @param liquidityGauge Address of the liquidity gauge
    /// @param veCRVBalance Amount of veCRV hold by Stake DAO Liquid Locker
    /// @return opt Optimal amount of LP token that must be held by the locker
    function _getOptimalAmount(address liquidityGauge, uint256 veCRVBalance) internal returns (uint256 opt) {
        if (
            // 1. Optimize calculation is activated
            useLastOpti
            // 2. The cached optimal amount is not too old
            && (lastOpti[liquidityGauge].timestamp + cachePeriod > block.timestamp)
            // 3. The cached veCRV balance of Stake DAO is below the acceptability threshold
            && absDiff(cacheVeCRVLockerBalance, veCRVBalance) < veCRVBalance.mulWadDown(veCRVDifferenceThreshold)
        ) {
            // Use cached optimal amount
            opt = lastOpti[liquidityGauge].value;
        } else {
            // Calculate optimal amount
            opt = optimalAmount(liquidityGauge, veCRVBalance);

            // Cache only if needed
            if (useLastOpti) {
                // Cache veCRV balance of Stake DAO, no need if already the same
                if (cacheVeCRVLockerBalance != veCRVBalance) cacheVeCRVLockerBalance = veCRVBalance;

                // Update the cache for Classic Pool
                lastOpti[liquidityGauge] = CachedOptimization(opt, block.timestamp);
            }
        }
    }

    /// @notice Return the amount that need to be withdrawn from StakeDAO Liquid Locker and from each fallback
    /// @param token Address of LP token to withdraw
    /// @param liquidityGauge Address of Liquidity Gauge corresponding to LP token
    /// @param amount Amount of LP token to withdraw
    /// @return Array of addresses to withdraw from, Stake DAO LiquidLocker always first
    /// @return Array of amounts to withdraw from
    function optimizeWithdraw(address token, address liquidityGauge, uint256 amount)
        public
        view
        requiresAuth
        returns (address[] memory, uint256[] memory)
    {
        // Cache the balance of all fallbacks
        uint256 balanceOfStakeDAO = ERC20(liquidityGauge).balanceOf(LOCKER);
        uint256 balanceOfConvexCurve = FallbackConvexCurve(fallbacks[1]).balanceOf(token);

        // Initialize the result
        uint256[] memory amounts = new uint256[](2);

        // === Situation n°1 === //
        // If available on Convex Curve
        if (balanceOfConvexCurve > 0) {
            // Withdraw as much as possible from Convex Curve
            amounts[1] = min(amount, balanceOfConvexCurve);
            // Update the amount to withdraw
            amount -= amounts[1];

            // If there is still amount to withdraw
            if (amount > 0) {
                // Withdraw as much as possible from Stake DAO Curve
                amounts[0] = min(amount, balanceOfStakeDAO);
                // Update the amount to withdraw
                amount -= amounts[0];
            }
        }
        // === Situation n°2 === //
        // If not available on Convex Curve
        else {
            // Withdraw as much as possible from Stake DAO Curve
            amounts[0] = min(amount, balanceOfStakeDAO);
            // Update the amount to withdraw
            amount -= amounts[0];
        }

        // If there is still some amount to withdraw, it means that optimizor miss calculated
        if (amount != 0) revert WRONG_AMOUNT();

        return (fallbacks, amounts);
    }

    /// @notice Toggle the flag for using the last optimization
    function toggleUseLastOptimization() external requiresAuth {
        useLastOpti = !useLastOpti;
    }

    /// @notice Set the cache period
    /// @param newCachePeriod New cache period
    function setCachePeriod(uint256 newCachePeriod) external requiresAuth {
        cachePeriod = newCachePeriod;
    }

    /// @notice Set veCRV Difference Threshold
    /// @param newVeCRVDifferenceThreshold New veCRV Difference Threshold
    function setVeCRVDifferenceThreshold(uint256 newVeCRVDifferenceThreshold) external requiresAuth {
        veCRVDifferenceThreshold = newVeCRVDifferenceThreshold;
    }

    /// @notice Set new Curve Strategy
    /// @param newCurveStrategy New Curve Strategy address
    function setCurveStrategy(address newCurveStrategy) external requiresAuth {
        curveStrategy = CurveStrategy(newCurveStrategy);
    }

    //////////////////////////////////////////////////////
    /// --- VIEWS
    //////////////////////////////////////////////////////

    /// @notice Get the fallback addresses
    function getFallbacks() external view returns (address[] memory) {
        return fallbacks;
    }

    /// @notice Get the number of fallbacks
    function fallbacksLength() external view returns (uint256) {
        return fallbacks.length;
    }

    /// @notice Rescue lost ERC20 tokens from contract
    /// @param token Addresss of token to rescue
    /// @param to Address to send rescued tokens to
    /// @param amount Amount of token to rescue
    function rescueERC20(address token, address to, uint256 amount) external requiresAuth {
        // Transfer `amount` of `token` to `to`
        ERC20(token).safeTransfer(to, amount);
    }

    /// @notice Get minimum between two uint256
    /// @param a First uint256
    /// @param b Second uint256
    /// @return The minimum between a and b
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a < b) ? a : b;
    }

    /// @notice Get absolute difference between two uint256
    /// @param a First uint256
    /// @param b Second uint256
    /// @return The absolute difference between a and b
    function absDiff(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? a - b : b - a;
    }
}
