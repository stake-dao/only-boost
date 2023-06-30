// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// --- Core Contracts
import {CurveStrategy} from "src/CurveStrategy.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

// --- Interfaces
import {ICVXLocker} from "src/interfaces/ICVXLocker.sol";

/**
 * @title Optimizor
 * @author Stake DAO
 * @notice External module for Stake DAO Strategy to optimize the deposit and withdraw between LiquidLockers and Fallbacks
 * @dev Inherits from Solmate `Auth` implementation
 */
contract Optimizor is Auth {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- STRUCTS
    //////////////////////////////////////////////////////
    struct CachedOptimization {
        uint256 value;
        uint256 timestamp;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    // --- ERC20
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV Token
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B); // CVX Token

    // --- Addresses
    address public constant LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2; // CRV Locker
    address public constant LOCKER_CVX = 0xD18140b4B819b895A3dba5442F959fA44994AF50; // CVX Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker
    address public constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker

    // --- Uints
    uint256 public constant FEES_CONVEX = 17e16; // 17% Convex
    uint256 public constant FEES_STAKEDAO = 16e16; // 16% StakeDAO

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    // --- Contracts
    CurveStrategy public curveStrategy;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    // --- Addresses
    address[] public fallbacks; // List of fallbacks

    // --- Bools
    bool public isConvexFraxPaused; // Pause Convex FRAX Deposit
    bool public isConvexFraxKilled; // Kill Convex FRAX Deposit and Withdraw
    bool public useLastOpti; // Use last optimization value

    // --- Uints
    uint256 public extraConvexFraxBoost = 1e16; // 1% extra boost for Convex FRAX
    uint256 public convexFraxPausedTimestamp; // Timestamp of the Convex FRAX pause
    uint256 public cachePeriod = 7 days; // Cache period for optimization

    // --- Mappings
    mapping(address => CachedOptimization) public lastOpti; // liquidityGauge => CachedOptimization
    mapping(address => CachedOptimization) public lastOptiMetapool; // liquidityGauge => CachedOptimization

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////
    error TOO_SOON();
    error NOT_PAUSED();
    error WRONG_AMOUNT();
    error ALREADY_PAUSED();
    error ALREADY_KILLED();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(
        address owner,
        Authority authority,
        address _curveStrategy,
        address _fallbackConvexCurve,
        address _fallbackConvexFrax
    ) Auth(owner, authority) {
        fallbackConvexFrax = FallbackConvexFrax(_fallbackConvexFrax);
        fallbackConvexCurve = FallbackConvexCurve(_fallbackConvexCurve);
        curveStrategy = CurveStrategy(_curveStrategy);

        fallbacks.push(LOCKER);
        fallbacks.push(address(fallbackConvexCurve));
        fallbacks.push(address(fallbackConvexFrax));
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STAKEDAO
    //////////////////////////////////////////////////////
    /**
     * @notice Return the optimal amount of LP token that must be held by Stake DAO Liquidity Locker
     * @param liquidityGauge Addres of the liquidity gauge
     * @param isMeta if the underlying pool is a metapool
     * @return Optimal amount of LP token
     */
    function optimalAmount(address liquidityGauge, bool isMeta) public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER);

        // Liquidity Gauge
        uint256 balanceConvex = ERC20(liquidityGauge).balanceOf(LOCKER_CONVEX);

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;

        // Additional boost
        uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Additional boost for Convex FRAX
        boost = isMeta ? boost + extraConvexFraxBoost : boost;

        // Result
        return balanceConvex * veCRVStakeDAO * (1e18 - FEES_STAKEDAO) / (veCRVConvex * (1e18 - FEES_CONVEX + boost));
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STRATEGIE DEPOSIT & WITHDRAW
    //////////////////////////////////////////////////////
    /**
     * @notice Return the amount that need to be deposited StakeDAO Liquid Locker and on each fallback
     * @dev This is not a view due to the cache system
     * @param token Address of LP token to deposit
     * @param liquidityGauge Address of Liquidity Gauge corresponding to LP token
     * @param amount Amount of LP token to deposit
     * @return Array of addresses to deposit in, Stake DAO LiquidLocker always first
     * @return Array of amounts to deposit in
     */
    function optimizeDeposit(address token, address liquidityGauge, uint256 amount)
        public
        requiresAuth
        returns (address[] memory, uint256[] memory)
    {
        // Check if the lp token has pool on ConvexCurve or ConvexFrax
        bool statusCurve = fallbackConvexCurve.isActive(token);
        bool statusFrax = fallbackConvexFrax.isActive(token);

        uint256[] memory amounts = new uint256[](3);

        // If Metapool and available on Convex Frax
        if (statusFrax && !isConvexFraxPaused) {
            // Get the optimal amount of lps that must be held by the locker
            uint256 opt;
            // If optimize calculation is activated and the last optimization is not too old, use the cached value
            if (useLastOpti && lastOptiMetapool[liquidityGauge].timestamp + cachePeriod > block.timestamp) {
                opt = lastOptiMetapool[liquidityGauge].value;
            }
            // Else, calculate the optimal amount and cache it
            else {
                opt = optimalAmount(liquidityGauge, true);
                lastOptiMetapool[liquidityGauge] = CachedOptimization(opt, block.timestamp);
            }

            // Get the balance of the locker on the liquidity gauge
            uint256 gaugeBalance = ERC20(liquidityGauge).balanceOf(address(LOCKER));

            // Stake DAO Curve
            amounts[0] = opt > gaugeBalance ? min(opt - gaugeBalance, amount) : 0;
            // Convex Curve
            // amounts[1] = 0;
            // Convex Frax
            amounts[2] = amount - amounts[0];
        }
        // If available on Convex Curve
        else if (statusCurve) {
            // Get the optimal amount of lps that must be held by the locker
            uint256 opt;
            // If optimize calculation is activated and the last optimization is not too old, use the cached value
            if (useLastOpti && lastOpti[liquidityGauge].timestamp + cachePeriod > block.timestamp) {
                opt = lastOpti[liquidityGauge].value;
            }
            // Else, calculate the optimal amount and cache it
            else {
                opt = optimalAmount(liquidityGauge, false);
                lastOpti[liquidityGauge] = CachedOptimization(opt, block.timestamp);
            }
            // Get the balance of the locker on the liquidity gauge
            uint256 gaugeBalance = ERC20(liquidityGauge).balanceOf(address(LOCKER));

            // Stake DAO Curve
            amounts[0] = opt > gaugeBalance ? min(opt - gaugeBalance, amount) : 0;
            // Convex Curve
            amounts[1] = amount - amounts[0];
            // Convex Frax
            // amounts[2] = 0;
        }
        // If not available on Convex Curve or Convex Frax
        else {
            // Stake DAO Curve
            amounts[0] = amount;
            // Convex Curve
            // amounts[1] = 0;
            // Convex Frax
            // amounts[2] = 0;
        }

        return (fallbacks, amounts);
    }

    /**
     * @notice Return the amount that need to be withdrawn from StakeDAO Liquid Locker and from each fallback
     * @param token Address of LP token to withdraw
     * @param liquidityGauge Address of Liquidity Gauge corresponding to LP token
     * @param amount Amount of LP token to withdraw
     * @return Array of addresses to withdraw from, Stake DAO LiquidLocker always first
     * @return Array of amounts to withdraw from
     */
    function optimizeWithdraw(address token, address liquidityGauge, uint256 amount)
        public
        view
        requiresAuth
        returns (address[] memory, uint256[] memory)
    {
        // Cache the balance of all fallbacks
        uint256 balanceOfStakeDAO = ERC20(liquidityGauge).balanceOf(LOCKER);
        uint256 balanceOfConvexCurve = FallbackConvexCurve(fallbacks[1]).balanceOf(token);
        uint256 balanceOfConvexFrax = isConvexFraxKilled ? 0 : FallbackConvexFrax(fallbacks[2]).balanceOf(token);

        // Initialize the result
        uint256[] memory amounts = new uint256[](3);

        // === Situation n°1 === //
        // If available on Convex Frax
        if (balanceOfConvexFrax > 0) {
            // Withdraw as much as possible from Convex Frax
            amounts[2] = min(amount, balanceOfConvexFrax);
            // Update the amount to withdraw
            amount -= amounts[2];

            // If there is still amount to withdraw
            if (amount > 0) {
                // Withdraw as much as possible from Stake DAO Curve
                amounts[0] = min(amount, balanceOfStakeDAO);
                // Update the amount to withdraw
                amount -= amounts[0];

                // If there is still amount to withdraw, but this situation should happen only rarely
                // Because there should not have deposit both on convex curve and convex frax
                if (amount > 0 && balanceOfConvexCurve > 0) {
                    // Withdraw as much as possible from Convex Curve
                    amounts[1] = min(amount, balanceOfConvexCurve);
                    // Update the amount to withdraw
                    amount -= amounts[1];
                }
            }
        }
        // === Situation n°2 === //
        // If available on Convex Curve
        else if (balanceOfConvexCurve > 0) {
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
        // === Situation n°3 === //
        // If not available on Convex Curve or Convex Frax
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

    /**
     * @notice Toggle the flag for using the last optimization
     */
    function toggleUseLastOptimization() external requiresAuth {
        useLastOpti = !useLastOpti;
    }

    /**
     * @notice Set the cache period
     * @param newCachePeriod New cache period
     */
    function setCachePeriod(uint256 newCachePeriod) external requiresAuth {
        cachePeriod = newCachePeriod;
    }

    //////////////////////////////////////////////////////
    /// --- REMOVE CONVEX FRAX
    //////////////////////////////////////////////////////
    /**
     * @notice Pause the deposit on Convex Frax
     */
    function pauseConvexFraxDeposit() external requiresAuth {
        // Revert if already paused
        if (isConvexFraxPaused) revert ALREADY_PAUSED();

        // Pause
        isConvexFraxPaused = true;
        // Set the timestamp
        convexFraxPausedTimestamp = block.timestamp;
    }

    /**
     * @notice Kill the deposit on Convex Frax
     */
    function killConvexFrax() external requiresAuth {
        // Revert if not paused
        if (!isConvexFraxPaused) revert NOT_PAUSED();
        // Revert if already killed
        if (isConvexFraxKilled) revert ALREADY_KILLED();
        // Revert if not enough time has passed
        if ((convexFraxPausedTimestamp + fallbackConvexFrax.lockingIntervalSec()) > block.timestamp) {
            revert TOO_SOON();
        }

        // Kill
        isConvexFraxKilled = true;

        // Cache len
        uint256 len = fallbackConvexFrax.lastPidsCount();

        for (uint256 i = 0; i < len;) {
            // Check balanceOf on the fallback
            uint256 balance = fallbackConvexFrax.balanceOf(i);

            if (balance > 0) {
                // Get LP token
                (address token,) = fallbackConvexFrax.getLP(i);
                // Withdraw from convex frax
                fallbackConvexFrax.withdraw(token, balance);

                // Follow optimized deposit logic
                curveStrategy.depositForOptimizor(token, balance);
            }

            // No need to check if overflow, because len is uint256
            unchecked {
                ++i;
            }
        }
    }

    // ONLY USED FOR TEST, SHOULD BE REMOVED IN PROD !!!
    function setFallbackAddresses(address addr1, address addr2) public {
        fallbackConvexCurve = FallbackConvexCurve(addr1);
        fallbackConvexFrax = FallbackConvexFrax(addr2);
        fallbacks[1] = addr1;
        fallbacks[2] = addr2;
    }

    /**
     * @notice Get the fallback addresses
     */
    function getFallbacks() external view returns (address[] memory) {
        return fallbacks;
    }

    /**
     * @notice Get the number of fallbacks
     */
    function fallbacksLength() external view returns (uint256) {
        return fallbacks.length;
    }

    /**
     * @notice Rescue lost ERC20 tokens from contract
     * @param token Addresss of token to rescue
     * @param to Address to send rescued tokens to
     * @param amount Amount of token to rescue
     */
    function rescueERC20(address token, address to, uint256 amount) external requiresAuth {
        // Transfer `amount` of `token` to `to`
        ERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Get minimum between two uint256
     * @param a First uint256
     * @param b Second uint256
     * @return The minimum between a and b
     */
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a < b) ? a : b;
    }
}
