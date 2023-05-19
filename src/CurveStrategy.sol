// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";

import {ILocker} from "src/interfaces/ILocker.sol";

contract CurveStrategy {
    using SafeTransferLib for ERC20;

    //////////////////////////////// Constants ////////////////////////////////
    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker

    //////////////////////////////// Contracts ////////////////////////////////
    Optimizor public optimizor; // Optimizor contract

    //////////////////////////////// Variables ////////////////////////////////

    //////////////////////////////// Mappings /////////////////////////////////
    mapping(address => address) public gauges; // lp token from curve -> curve gauge

    //////////////////////////////// Errors ////////////////////////////////
    error ADDRESS_NULL();

    constructor() {
        optimizor = new Optimizor();
    }

    function deposit(address token, uint256 amount) external {
        // Transfer the token to this contract
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Do the deposit process
        _deposit(token, amount);
    }

    function _deposit(address token, uint256 amount) internal {
        // Get the gauge address
        address gauge = gauges[token];
        // Revert if the gauge is not set
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory optimizedAmounts) =
            optimizor.optimizeDeposit(token, gauge, amount);

        // Loops on fallback to deposit lp tokens
        for (uint8 i; i < recipients.length; ++i) {
            // Skip if the optimized amount is 0
            if (optimizedAmounts[i] == 0) continue;

            // Special process for Stake DAO locker
            if (recipients[i] == address(LOCKER_STAKEDAO)) {
                _depositIntoLiquidLocker(token, gauge, optimizedAmounts[i]);
            }
            // Deposit into other fallback
            else {
                ERC20(token).safeTransfer(recipients[i], optimizedAmounts[i]);
                BaseFallback(recipients[i]).deposit(token, optimizedAmounts[i]);
            }
        }
    }

    function _depositIntoLiquidLocker(address token, address gauge, uint256 amount) internal {
        ERC20(token).safeTransfer(address(LOCKER_STAKEDAO), amount);

        // Approve LOCKER_STAKEDAO to spend token
        LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
        LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, amount));

        // Locker deposit token
        (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", amount));
        require(success, "Deposit failed!");
    }

    function withdraw(address token, uint256 amount) external {
        // Do the withdraw process
        _withdraw(token, amount);

        // Transfer the token to the user
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    function _withdraw(address token, uint256 amount) internal {
        // Get the gauge address
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory optimizedAmounts) =
            optimizor.optimizeWithdraw(token, gauge, amount);

        uint256 len = recipients.length;
        for (uint8 i; i < len; ++i) {
            // Skip if the optimized amount is 0
            if (optimizedAmounts[i] == 0) continue;

            // Special process for Stake DAO locker
            if (recipients[i] == address(LOCKER_STAKEDAO)) {
                _withdrawFromLiquidLocker(token, gauge, optimizedAmounts[i]);
            }
            // Deposit into other fallback
            else {
                BaseFallback(recipients[i]).withdraw(token, optimizedAmounts[i]);
            }
        }
    }

    function _withdrawFromLiquidLocker(address token, address gauge, uint256 amount) internal {
        uint256 _before = ERC20(token).balanceOf(address(LOCKER_STAKEDAO));

        (bool success,) = LOCKER_STAKEDAO.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));
        require(success, "Transfer failed!");
        uint256 _after = ERC20(token).balanceOf(address(LOCKER_STAKEDAO));

        uint256 _net = _after - _before;
        (success,) =
            LOCKER_STAKEDAO.execute(token, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), _net));
        require(success, "Transfer failed!");
    }

    function setGauge(address token, address gauge) external {
        gauges[token] = gauge;
    }
}
