// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IFallback} from "src/interfaces/IFallback.sol";
import {ICVXLocker} from "src/interfaces/ICVXLocker.sol";
import {IOnlyBoost} from "src/interfaces/IOnlyBoost.sol";
import {IConvexFactory} from "src/interfaces/IConvexFactory.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @title Optimizer
/// @author Stake DAO
/// @notice Module to compute optimal allocation between Stake DAO and Convex.
/// @dev It should inherit from IOnlyBoost to be used in the StakeDAO Strategy.
contract Optimizer is IOnlyBoost {
    using FixedPointMathLib for uint256;

    /// @notice Struct to store cached optimization values and timestamp
    /// @param value Cached optimization value
    /// @param timestamp Timestamp of the cached optimization
    struct CachedOptimization {
        uint256 value;
        uint256 timestamp;
    }

    /// @notice Stake DAO Curve Strategy
    address public immutable strategy;

    /// @notice Minimal Proxy Factory for Convex Deposit Contracts.
    IConvexFactory public immutable proxyFactory;

    /// @notice CRV Token.
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    /// @notice CVX Token.
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    /// @notice Convex CVX Vote-escrow contract
    address public constant VL_CVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    /// @notice Curve DAO CRV Vote-escrow contract
    address public constant veToken = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    /// @notice StakeDAO CRV Locker.
    address public constant VOTER_PROXY_SD = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    /// @notice Convex CRV Locker.
    address public constant VOTER_PROXY_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Cache period for optimization.
    uint256 public cachePeriod = 7 days;

    /// @notice Adjustment factor for CVX / vlCVX.
    uint256 public adjustmentFactor = 1e18;

    /// @notice Fees on Convex.
    uint256 public convexTotalFee = 17e16;

    /// @notice Fees on StakeDAO.
    uint256 public stakeDaoTotalFee = 16e16;

    /// @notice Map gauge => CachedOptimization.
    mapping(address => CachedOptimization) public cachedOptimizations;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Event emitted when the adjustment factor is updated
    /// @param newAdjustmentFactor The new adjustment factor
    event AdjustmentFactorUpdated(uint256 newAdjustmentFactor);

    /// @notice Error emitted when auth failed
    error GOVERNANCE();

    /// @notice Error emitted when the caller is not the strategy.
    error STRATEGY();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    modifier onlyStrategy() {
        if (msg.sender != strategy) revert STRATEGY();
        _;
    }

    /// @notice Constructor to set the curve strategy and proxy factory
    /// @param _curveStrategy The address of the curve strategy
    /// @param _proxyFactory The address of the proxy factory
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
        uint256 vlCVXTotal = ICVXLocker(VL_CVX).lockedSupply();

        // Additional boost
        uint256 boost = adjustmentFactor * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Fees
        uint256 feeDiff = boost + stakeDaoTotalFee > convexTotalFee ? stakeDaoTotalFee + boost - convexTotalFee : 0;

        // Result
        return (
            3 * (1e18 - stakeDaoTotalFee) * balanceConvex * veCRVStakeDAO
                / (
                    (2 * (feeDiff) * balanceConvex * veCRVTotal) / totalSupply
                        + 3 * veCRVConvex * (1e18 + boost - convexTotalFee)
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
        onlyStrategy
        returns (address[] memory _depositors, uint256[] memory _allocations)
    {
        /// Gets the fallback address via the proxy factory; one fallback (clone) per Convex pid
        address _fallback = proxyFactory.fallbacks(gauge);

        // If available on Convex Curve
        if (_fallback != address(0)) {
            /// Initialize arrays
            _depositors = new address[](2);
            _allocations = new uint256[](2);

            _depositors[0] = _fallback;
            _depositors[1] = VOTER_PROXY_SD;

            // If Convex Curve has max boost, no need to optimize
            if (
                ILiquidityGauge(gauge).working_balances(VOTER_PROXY_CONVEX)
                    == ERC20(gauge).balanceOf(VOTER_PROXY_CONVEX)
            ) {
                _allocations[0] = amount;
            } else {
                // Get the balance of the locker on the liquidity gauge
                uint256 gaugeBalance = ERC20(gauge).balanceOf(address(VOTER_PROXY_SD));

                // Get the optimal amount of lps that must be held by the locker
                uint256 opt = _getOptimalAmount(gauge, gaugeBalance, amount);

                // Stake DAO Curve
                _allocations[1] = opt > gaugeBalance ? FixedPointMathLib.min(opt - gaugeBalance, amount) : 0;

                // Convex Curve
                _allocations[0] = amount - _allocations[1];
            }
        }
        // If not available on Convex
        // We only deposit on Stake DAO
        else {
            /// Initialize arrays
            _depositors = new address[](1);
            _depositors[0] = VOTER_PROXY_SD;

            _allocations = new uint256[](1);
            _allocations[0] = amount;
        }
    }

    /// @notice Return the amount that need to be deposited StakeDAO Liquid Locker and on each fallback
    /// @dev This is not a view due to the cache system
    /// @param gauge Address of Liquidity Gauge corresponding to LP token
    /// @param amount Amount of LP token to deposit
    function getRebalancedAllocation(address gauge, uint256 amount)
        public
        onlyStrategy
        returns (address[] memory _depositors, uint256[] memory _allocations)
    {
        /// Gets the fallback address via the proxy factory; one fallback (clone) per Convex pid
        address _fallback = proxyFactory.fallbacks(gauge);

        // If available on Convex Curve
        if (_fallback != address(0)) {
            /// Initialize arrays
            _depositors = new address[](2);
            _allocations = new uint256[](2);

            _depositors[0] = _fallback;
            _depositors[1] = VOTER_PROXY_SD;

            // Calculate optimal amount
            uint256 opt = computeOptimalDepositAmount(gauge);

            // Cache only if needed
            if (cachePeriod != 0) {
                // Update the cache for Classic Pool
                cachedOptimizations[gauge] = CachedOptimization(opt, block.timestamp);
            }

            // Stake DAO Curve
            _allocations[1] = amount > opt ? opt : amount;

            // Convex Curve
            _allocations[0] = amount - _allocations[1];
        } else {
            /// Initialize arrays
            _depositors = new address[](1);
            _depositors[0] = VOTER_PROXY_SD;

            _allocations = new uint256[](1);
            _allocations[0] = amount;
        }
    }

    /// @notice Calcul the optimal amount of lps that must be held by the locker or use the cached value
    /// @param gauge Address of the liquidity gauge
    /// @param gaugeBalance Balance of the liquidity gauge on Convex Curve
    /// @param amount Amount of LP token to get the optimal amount for
    /// @return opt Optimal amount of LP token that must be held by the locker
    function _getOptimalAmount(address gauge, uint256 gaugeBalance, uint256 amount) internal returns (uint256 opt) {
        CachedOptimization memory cachedOptimization = cachedOptimizations[gauge];

        if (
            cachedOptimization
                /// If the cache is enabled
                .timestamp + cachePeriod > block.timestamp
            /// And the new deposit is lower than the cached optimal amount
            && cachedOptimization.value >= amount + gaugeBalance
        ) {
            // Use cached optimal amount
            return cachedOptimization.value;
        } else {
            // Calculate optimal amount
            opt = computeOptimalDepositAmount(gauge);

            // Cache only if needed
            if (cachePeriod != 0) {
                // Update the cache for Classic Pool
                cachedOptimizations[gauge] = CachedOptimization(opt, block.timestamp);
            }
        }
    }

    /// @notice Return the amount that need to be withdrawn from StakeDAO Liquid Locker and from Convex Curve based on the amount to withdraw and boost optimization
    /// @param gauge Address of Liquidity Gauge corresponding to LP token
    /// @param amount Amount of LP token to withdraw
    function getOptimalWithdrawalPath(address gauge, uint256 amount)
        public
        view
        returns (address[] memory _withdrawalTargets, uint256[] memory _allocations)
    {
        _withdrawalTargets = new address[](2);
        _allocations = new uint256[](2);

        _withdrawalTargets[1] = VOTER_PROXY_SD;
        _withdrawalTargets[0] = proxyFactory.fallbacks(gauge);

        uint256 balanceSD = ERC20(gauge).balanceOf(VOTER_PROXY_SD);
        uint256 balanceConvex = IFallback(_withdrawalTargets[0]).balanceOf(gauge);

        // Calculate optimal boost for both pools
        uint256 optimalSD = cachedOptimizations[gauge].value;
        uint256 totalBalance = balanceSD + balanceConvex;

        // Adjust the withdrawal based on the optimal amount for Stake DAO
        if (totalBalance <= amount) {
            // If the total balance is less than or equal to the withdrawal amount, withdraw everything
            _allocations[0] = balanceConvex;
            _allocations[1] = balanceSD;
        } else if (optimalSD >= balanceSD) {
            // If Stake DAO balance is below optimal, prioritize withdrawing from Convex
            _allocations[0] = FixedPointMathLib.min(amount, balanceConvex);
            _allocations[1] = amount > _allocations[0] ? amount - _allocations[0] : 0;
        } else {
            // If Stake DAO balance is above optimal, prioritize withdrawing from Stake DAO
            _allocations[1] = FixedPointMathLib.min(amount, balanceSD);
            _allocations[0] = amount > _allocations[1] ? amount - _allocations[1] : 0;
        }
    }

    /// @notice Get the fallbacks address for a gauge
    /// @param gauge Address of the gauge
    function getFallbacks(address gauge) public view returns (address[] memory _fallbacks) {
        _fallbacks = new address[](1);
        _fallbacks[0] = address(proxyFactory.fallbacks(gauge));
    }

    /// @notice Adjust the conversion factor for CVX / vlCVX
    /// @param _adjustmentFactor The new adjustment factor
    /// @dev Only the admin can call this
    function setAdjustmentFactor(uint256 _adjustmentFactor) external onlyGovernance {
        adjustmentFactor = _adjustmentFactor;
        emit AdjustmentFactorUpdated(_adjustmentFactor);
    }

    /// @notice Set the cache period
    /// @param newCachePeriod New cache period
    /// @dev Only the governance can call this
    function setCachePeriod(uint256 newCachePeriod) external onlyGovernance {
        cachePeriod = newCachePeriod;
    }

    /// @notice Set fees percentage.
    /// @param _stakeDaoFees Fees percentage for StakeDAO
    /// @param _convexFees Fees percentage for Convex
    /// @dev Only the governance can call this
    function setFees(uint256 _stakeDaoFees, uint256 _convexFees) external onlyGovernance {
        stakeDaoTotalFee = _stakeDaoFees;
        convexTotalFee = _convexFees;
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    /// @dev Only the governance can call this
    /// @dev 2 step process, first you call this function with the new governance address, then the new governance contract has to call `acceptGovernance`
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }
}
