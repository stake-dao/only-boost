// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Optimizor} from "src/OptimizorV2.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {ConvexMapper} from "src/ConvexMapperV2.sol";

import {ILocker} from "src/interfaces/ILocker.sol";

contract CurveStrategy {
    using SafeTransferLib for ERC20;

    //////////////////////////////// Constants ////////////////////////////////
    ILocker public constant LOCKER_STAKEDAO = ILocker(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6); // StakeDAO CRV Locker

    //////////////////////////////// Contracts ////////////////////////////////
    Optimizor public optimizor; // Optimizor contract
    ConvexMapper public convexMapper; // Convex mapper contract

    //////////////////////////////// Variables ////////////////////////////////
    address[] public fallbacks;

    //////////////////////////////// Mappings /////////////////////////////////
    mapping(address => address) public gauges; // lp token from curve -> curve gauge

    //////////////////////////////// Errors ////////////////////////////////
    error ADDRESS_NULL();

    constructor() {
        convexMapper = new ConvexMapper();
        optimizor = new Optimizor(convexMapper);
    }

    function deposit(address token, uint256 amount) external {
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Call the Optimizor contract
        (address[] memory recipients, uint256[] memory optimizedAmounts) = optimizor.optimization(token, gauge, amount);

        // Deposit first into Stake DAO
        for (uint8 i; i < fallbacks.length; ++i) {
            if (optimizedAmounts[i] == 0) continue;
            if (recipients[i] == address(LOCKER_STAKEDAO)) {
                _depositIntoLiquidLocker(token, gauge, optimizedAmounts[i]);
            } else {
                ERC20(token).safeTransfer(fallbacks[i], optimizedAmounts[i]);
                BaseFallback(fallbacks[i]).deposit(optimizedAmounts[i]);
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
}
