// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Optimizor} from "src/Optimizor.sol";
import {ConvexMapper} from "src/ConvexMapper.sol";

import {ILocker} from "src/interfaces/ILocker.sol";

contract CurveStrategy is Auth {
    using FixedPointMathLib for uint256;

    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker

    Optimizor public optimizor;
    ConvexMapper public convexMapper;
    mapping(address => address) public gauges; // token address --> gauge address

    error ADDRESS_NULL();

    constructor(Authority _authority) Auth(msg.sender, _authority) {
        optimizor = new Optimizor();
        convexMapper = new ConvexMapper();
    }

    function deposit(address token, uint256 amount) external {
        // Only vault can call this function

        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Check if the pool is active on convexFrax
        bool isOnConvexFrax = convexMapper.isOnConvexFrax(token);

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
