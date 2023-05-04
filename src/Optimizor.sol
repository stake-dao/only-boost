// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ICVXLocker} from "src/interfaces/ICVXLocker.sol";

contract Optimizor {
    //////////////////////////////// Constants ////////////////////////////////
    address public constant LIQUDITY_GAUGE = 0x1E212e054d74ed136256fc5a5DDdB4867c6E003F; // 3EURPool Gauge

    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV Token
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B); // CVX Token

    address public constant LOCKER_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2; // CRV Locker
    address public constant LOCKER_CVX = 0xD18140b4B819b895A3dba5442F959fA44994AF50; // CVX Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker
    address public constant LOCKER_STAKEDAO = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker

    uint256 public constant FEES_CONVEX = 17e16; // 17% Convex
    uint256 public constant FEES_STAKEDAO = 16e16; // 16% StakeDAO

    //////////////////////////////// Optimization ////////////////////////////////
    // 47899 gas
    function optimization1() public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER_STAKEDAO);

        // Liquidity Gauge
        uint256 balanceConvex = ERC20(LIQUDITY_GAUGE).balanceOf(LOCKER_CONVEX);

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;

        // Additional boost
        uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Result
        uint256 result =
            balanceConvex * veCRVStakeDAO * (1e18 - FEES_STAKEDAO) / (veCRVConvex * (1e18 - FEES_CONVEX + boost));
        return result / 1e18;
    }

    // 65263 gas
    function optimization2() public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER_STAKEDAO);
        uint256 veCRVTotal = ERC20(LOCKER_CRV).totalSupply();

        // Liquidity Gauge
        uint256 totalSupply = ERC20(LIQUDITY_GAUGE).totalSupply();
        uint256 balanceConvex = ERC20(LIQUDITY_GAUGE).balanceOf(LOCKER_CONVEX);

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;

        // Additional boost
        uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Result
        uint256 result = 3 * (1e18 - FEES_STAKEDAO) * balanceConvex * veCRVStakeDAO
            / (
                ((2 * (FEES_STAKEDAO + boost - FEES_CONVEX) * balanceConvex * veCRVTotal) / totalSupply)
                    + 3 * veCRVConvex * (1e18 + boost - FEES_CONVEX)
            );
        return result / 1e18;
    }

    // 47612 gas
    function optimization3() public view returns (uint256) {
        // veCRV
        uint256 veCRVConvex = ERC20(LOCKER_CRV).balanceOf(LOCKER_CONVEX);
        uint256 veCRVStakeDAO = ERC20(LOCKER_CRV).balanceOf(LOCKER_STAKEDAO);

        // Liquidity Gauge
        uint256 balanceConvex = ERC20(LIQUDITY_GAUGE).balanceOf(LOCKER_CONVEX);

        // CVX
        uint256 cvxTotal = CVX.totalSupply();
        uint256 vlCVXTotal = ICVXLocker(LOCKER_CVX).lockedSupply() * 1e7;

        // Additional boost
        uint256 boost = 1e18 * (1e26 - cvxTotal) * veCRVConvex / (1e26 * vlCVXTotal);

        // Result
        uint256 result = balanceConvex * veCRVStakeDAO / (veCRVConvex * (1e18 + boost));
        return result;
    }
}
