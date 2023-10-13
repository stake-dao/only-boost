// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

import {IFallback} from "src/interfaces/IFallback.sol";
import {IConvexFactory} from "src/interfaces/IConvexFactory.sol";

import {ICVXLocker} from "src/interfaces/ICVXLocker.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

/// @title Optimizer
/// @author Stake DAO
/// @notice Module to compute optimal allocation between Stake DAO and Convex.
contract Optimizer {
    using FixedPointMathLib for uint256;

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
    address public constant veToken = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    /// @notice Convex CVX Vote-escrow contract
    address public constant LOCKER_CVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    /// @notice Convex CRV Locker
    address public constant VOTER_PROXY_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice StakeDAO CRV Locker
    address public constant VOTER_PROXY_SD = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    // --- Uints
    /// @notice Fees on Convex
    uint256 public convexFee = 17e16;

    /// @notice Fees on StakeDAO
    uint256 public stakedaoFee = 16e16;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    /// @notice Stake DAO Curve Strategy
    address public immutable strategy;

    IConvexFactory public immutable proxyFactory;

    // --- Bools
    /// @notice Use last optimization value
    uint256 public cacheEnabled = 1;

    /// @notice Cache period for optimization
    uint256 public cachePeriod = 7 days;

    /// @notice Adjustment factor for CVX / vlCVX
    uint256 public adjustmentFactor = 1e18;

    // --- Mappings
    /// @notice Map gauge => CachedOptimization
    mapping(address => CachedOptimization) public cachedOptimizations;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////
    /// @notice Event emitted when the adjustment factor is updated
    /// @param newAdjustmentFactor The new adjustment factor
    event AdjustmentFactorUpdated(uint256 newAdjustmentFactor);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when caller is not the strategy
    error NOT_STRATEGY();

    /// @notice Error emitted when amount is wrong
    error WRONG_AMOUNT();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address _curveStrategy, address _proxyFactory) {
        strategy = _curveStrategy;
        proxyFactory = IConvexFactory(_proxyFactory);
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STAKEDAO
    //////////////////////////////////////////////////////

    /// @notice Return the optimal amount of LP token that must be held by Stake DAO Liquidity Locker
    /// @param gauge Addres of the gauge.
    /// @return Optimal amount of LP token
    function computeOptimalDepositAmount(address gauge) public view returns (uint256) {
        // Stake DAO
        uint256 veCRVStakeDAO = ERC20(veToken).balanceOf(VOTER_PROXY_SD);

        // veCRV
        uint256 veCRVConvex = ERC20(veToken).balanceOf(VOTER_PROXY_CONVEX);
        uint256 veCRVTotal = ERC20(veToken).totalSupply(); // New

        // Liquidity Gauge
        uint256 balanceConvex = ERC20(gauge).balanceOf(VOTER_PROXY_CONVEX);
        uint256 totalSupply = ERC20(gauge).totalSupply(); // New

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply();

        // Additional boost
        uint256 boost = adjustmentFactor * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Fees
        uint256 feeDiff = boost + stakedaoFee > convexFee ? stakedaoFee + boost - convexFee : 0;

        // Result
        return (
            3 * (1e18 - stakedaoFee) * balanceConvex * veCRVStakeDAO
                / (
                    (2 * (feeDiff) * balanceConvex * veCRVTotal) / totalSupply
                        + 3 * veCRVConvex * (1e18 + boost - convexFee)
                )
        );
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STRATEGIE DEPOSIT & WITHDRAW
    //////////////////////////////////////////////////////

    /// @notice Return the amount that need to be deposited StakeDAO Liquid Locker and on each fallback
    /// @dev This is not a view due to the cache system
    /// @param gauge Address of Liquidity Gauge corresponding to LP token
    /// @param amount Amount of LP token to deposit
    function getOptimalDepositAllocation(address gauge, uint256 amount)
        public
        returns (address[] memory _depositors, uint256[] memory _allocations)
    {
        _depositors = new address[](2);
        _allocations = new uint256[](2);

        address _fallback = proxyFactory.fallbacks(gauge);

        // If available on Convex Curve
        if (_fallback != address(0)) {
            // If Convex Curve has max boost, no need to optimize
            if (
                ILiquidityGauge(gauge).working_balances(VOTER_PROXY_CONVEX)
                    == ERC20(gauge).balanceOf(VOTER_PROXY_CONVEX)
            ) {
                _allocations[0] = amount;
            } else {
                // Get the optimal amount of lps that must be held by the locker
                uint256 opt = _getOptimalAmount(gauge);

                // Get the balance of the locker on the liquidity gauge
                uint256 gaugeBalance = ERC20(gauge).balanceOf(address(VOTER_PROXY_SD));

                // Stake DAO Curve
                _allocations[1] = absDiff(opt, gaugeBalance);

                // Convex Curve
                _allocations[0] = amount - _allocations[1];
            }
        }
        // If not available on Convex Curve
        else {
            // Stake DAO Curve
            _allocations[1] = amount;
        }
    }

    /// @notice Calcul the optimal amount of lps that must be held by the locker or use the cached value
    /// @param gauge Address of the liquidity gauge
    /// param balanceConvex Balance of the liquidity gauge on Convex Curve
    /// @return opt Optimal amount of LP token that must be held by the locker
    function _getOptimalAmount(address gauge) internal returns (uint256 opt) {
        if (
            // 1. Optimize calculation is activated
            cacheEnabled != 1
            // 2. The cached optimal amount is not too old
            && (cachedOptimizations[gauge].timestamp + cachePeriod > block.timestamp)
        ) {
            // Use cached optimal amount
            opt = cachedOptimizations[gauge].value;
        } else {
            // Calculate optimal amount
            opt = computeOptimalDepositAmount(gauge);

            // Cache only if needed
            if (cacheEnabled != 1) {
                // Update the cache for Classic Pool
                cachedOptimizations[gauge] = CachedOptimization(opt, block.timestamp);
            }
        }
    }

    function getOptimalWithdrawalPath(address gauge, uint256 amount)
        public
        view
        returns (address[] memory _fallbacks, uint256[] memory _allocations)
    {
        _fallbacks = new address[](2);
        _allocations = new uint256[](2);

        IFallback _fallback = IFallback(proxyFactory.fallbacks(gauge));

        _fallbacks[0] = address(_fallback);
        _fallbacks[1] = VOTER_PROXY_SD;

        uint256 balanceOfStakeDAO = ERC20(gauge).balanceOf(VOTER_PROXY_SD);
        uint256 balanceOfConvexCurve;

        if (address(_fallback) != address(0)) {
            balanceOfConvexCurve = _fallback.balanceOf();
        }

        if (balanceOfConvexCurve >= balanceOfStakeDAO) {
            // If Convex Curve has a higher (or equal) balance, prioritize it
            _allocations[0] = FixedPointMathLib.min(amount, balanceOfConvexCurve);
            amount -= _allocations[0];

            if (amount > 0) {
                _allocations[1] = FixedPointMathLib.min(amount, balanceOfStakeDAO);
                amount -= _allocations[1];
            }
        } else {
            // If Stake DAO has a higher balance, prioritize it
            _allocations[1] = FixedPointMathLib.min(amount, balanceOfStakeDAO);
            amount -= _allocations[1];

            if (amount > 0) {
                _allocations[0] = FixedPointMathLib.min(amount, balanceOfConvexCurve);
                amount -= _allocations[0];
            }
        }

        return (_fallbacks, _allocations);
    }

    function getFallback(address gauge) public view returns (address) {
        return proxyFactory.fallbacks(gauge);
    }

    /// @notice Adjust the conversion factor for CVX / vlCVX
    /// @param _adjustmentFactor The new adjustment factor
    /// @dev Only the admin can call this
    function setAdjustmentFactor(uint256 _adjustmentFactor) external {
        adjustmentFactor = _adjustmentFactor;
        emit AdjustmentFactorUpdated(_adjustmentFactor);
    }

    /// @notice Toggle the flag for using the last optimization
    function enableCache() external {
        cacheEnabled = 2;
    }

    function disableCache() external {
        cacheEnabled = 1;
    }

    /// @notice Set the cache period
    /// @param newCachePeriod New cache period
    function setCachePeriod(uint256 newCachePeriod) external {
        cachePeriod = newCachePeriod;
    }

    /// @notice Set fees percentage.
    /// @param _stakeDaoFees Fees percentage for StakeDAO
    /// @param _convexFees Fees percentage for Convex
    function setFees(uint256 _stakeDaoFees, uint256 _convexFees) external {
        stakedaoFee = _stakeDaoFees;
        convexFee = _convexFees;
    }

    /// @notice Get absolute difference between two uint256
    /// @param a First uint256
    /// @param b Second uint256
    /// @return The absolute difference between a and b
    function absDiff(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? a - b : b - a;
    }
}
