// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "test/pool-factory/PoolFactory.t.sol";

uint256 constant _0_PID = 0;
contract _0_Deposit_Test is PoolFactory_Test(_0_PID) {}

uint256 constant _4_PID = 4;
contract _4_Deposit_Test is PoolFactory_Test(_4_PID) {}