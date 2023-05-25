// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {CurveStrategy} from "src/CurveStrategy.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

import {ICVXLocker} from "src/interfaces/ICVXLocker.sol";

contract Optimizor {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV Token
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B); // CVX Token

    address public constant LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2; // CRV Locker
    address public constant LOCKER_CVX = 0xD18140b4B819b895A3dba5442F959fA44994AF50; // CVX Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker
    address public constant LOCKER_STAKEDAO = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker

    uint256 public constant FEES_CONVEX = 17e16; // 17% Convex
    uint256 public constant FEES_STAKEDAO = 16e16; // 16% StakeDAO

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    uint256 public extraConvexFraxBoost = 1e16; // 1% extra boost for Convex FRAX
    address[] public fallbacks;
    bool public isConvexFraxKilled;

    // --- Contracts
    CurveStrategy public curveStrategy;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor() {
        fallbackConvexFrax = new FallbackConvexFrax(msg.sender);
        fallbackConvexCurve = new FallbackConvexCurve();
        curveStrategy = CurveStrategy(msg.sender);

        fallbacks.push(LOCKER_STAKEDAO);
        fallbacks.push(address(fallbackConvexCurve));
        fallbacks.push(address(fallbackConvexFrax));
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STAKEDAO
    //////////////////////////////////////////////////////
    // This function return the optimal amount of lps that must be held by the locker
    function optimization1(address liquidityGauge, bool isMeta) public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER_STAKEDAO);

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

    // This function return the optimal amount of lps that must be held by the locker
    function optimization2(address liquidityGauge, bool isMeta) public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER_STAKEDAO);
        uint256 veCRVTotal = ERC20(LOCKER_CRV).totalSupply();

        // Liquidity Gauge
        uint256 totalSupply = ERC20(liquidityGauge).totalSupply();
        uint256 balanceConvex = ERC20(liquidityGauge).balanceOf(LOCKER_CONVEX);

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;

        // Additional boost
        uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Additional boost for Convex FRAX
        boost = isMeta ? boost + extraConvexFraxBoost : boost;

        // Result
        return 3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
            / (
                ((2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply)
                    + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
            );
    }

    // This function return the optimal amount of lps that must be held by the locker
    function optimization3(address liquidityGauge, bool isMeta) public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER_STAKEDAO);

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
        return balanceConvex * veCRVStakeDAO / (veCRVConvex * (1e18 + boost)) * 1e18;
    }

    //////////////////////////////////////////////////////
    /// --- OPTIMIZATION FOR STRATEGIE DEPOSIT & WITHDRAW
    //////////////////////////////////////////////////////
    // This function return the amount that need to be deposited StakeDAO locker and on each fallback
    function optimizeDeposit(address lpToken, address liquidityGauge, uint256 amount)
        public
        returns (address[] memory, uint256[] memory)
    {
        // Check if the lp token has pool on ConvexCurve or ConvexFrax
        //(bool statusCurve, bool statusFrax) = convexMapper.isActiveOnCurveOrFrax(lpToken);
        bool statusCurve = fallbackConvexCurve.isActive(lpToken);
        bool statusFrax = fallbackConvexFrax.isActive(lpToken);

        uint256[] memory amounts = new uint256[](3);

        // If Metapool and available on Convex Frax
        if (statusFrax && !isConvexFraxKilled) {
            // Get the optimal amount of lps that must be held by the locker
            uint256 opt = optimization1(liquidityGauge, true);
            // Get the balance of the locker on the liquidity gauge
            uint256 gaugeBalance = ERC20(liquidityGauge).balanceOf(address(LOCKER_STAKEDAO));

            // Stake DAO Curve
            amounts[0] = opt > gaugeBalance ? min(opt - gaugeBalance, amount) : 0;
            // Convex Curve
            // amounts[1] = 0;
            // Convex Frax
            amounts[2] = amount - amounts[0]; //min(opt - gaugeBalance, amount);
        }
        // If available on Convex Curve
        else if (statusCurve) {
            // Get the optimal amount of lps that must be held by the locker
            uint256 opt = optimization1(liquidityGauge, false);
            // Get the balance of the locker on the liquidity gauge
            uint256 gaugeBalance = ERC20(liquidityGauge).balanceOf(address(LOCKER_STAKEDAO));

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

    function optimizeWithdraw(address lpToken, address liquidityGauge, uint256 amount)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        // Cache the balance of all fallbacks
        uint256 balanceOfStakeDAO = ERC20(liquidityGauge).balanceOf(LOCKER_STAKEDAO);
        uint256 balanceOfConvexCurve = FallbackConvexCurve(fallbacks[1]).balanceOf(lpToken);
        uint256 balanceOfConvexFrax = isConvexFraxKilled ? 0 : FallbackConvexFrax(fallbacks[2]).balanceOf(lpToken);

        // Initialize the result
        uint256[] memory amounts = new uint256[](3);

        // === Situation n°1 === //
        // If available on Convex Curve
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

                // If there is still amount to withdraw, but this situation should happen only rarely
                // Because there should not have deposit both on convex curve and convex frax
                if (amount > 0 && balanceOfConvexFrax > 0) {
                    // Withdraw as much as possible from Convex Frax
                    amounts[2] = min(amount, balanceOfConvexFrax);
                    // Update the amount to withdraw
                    amount -= amounts[2];
                }
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
        assert(amount == 0);

        return (fallbacks, amounts);
    }

    //////////////////////////////////////////////////////
    /// --- REMOVE CONVEX FRAX
    //////////////////////////////////////////////////////
    function killConvexFrax() public {
        isConvexFraxKilled = true;

        uint256 len = fallbackConvexFrax.lastPidsCount();

        for (uint256 i = 0; i < len; ++i) {
            uint256 balance = fallbackConvexFrax.balanceOf(i);
            (address lpToken,) = fallbackConvexFrax.getLP(i);
            if (balance > 0 && lpToken != address(0)) {
                // Withdraw from convex frax
                fallbackConvexFrax.withdraw(lpToken, balance);

                // Follow optimized deposit logic
                curveStrategy.depositForOptimizor(lpToken, balance);
            }
        }
    }

    function fallbacksLength() public view returns (uint256) {
        return fallbacks.length;
    }

    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return (a < b) ? a : b;
    }
}
