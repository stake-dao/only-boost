// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "test/pool-factory/Staking.t.sol";
import "test/pool-factory/PoolFactory.t.sol";

uint256 constant _0_PID = 56;
address constant _0_LIQUIDITY_GAUGE = address(0);

/// @notice Case where the gauge exists in Convex.
contract _0_Factory_Test is PoolFactory_Test(_0_PID, _0_LIQUIDITY_GAUGE) {}

uint256 constant _1_PID = 0;
address constant _1_LIQUIDITY_GAUGE = address(0x6Aba93E10147f86744bb9A50238d25F49eD4F342);

/// @notice Case where the gauge doesn't exist nor in Convex or Stake DAO.
contract _1_Factory_Test is PoolFactory_Test(_1_PID, _1_LIQUIDITY_GAUGE) {}
