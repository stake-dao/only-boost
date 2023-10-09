// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

/// TODO: For testing, remove for production
//import "forge-std/Test.sol";

import "src/v2/StrategyV2.sol";

/// @title OnlyBoost Strategy Contract
/// @author Stake DAO
/// @notice OnlyBoost Compatible Strategy Proxy Contract to interact with Stake DAO Locker.
abstract contract OnlyBoost is Strategy {
    /// @notice Optimizer address for deposit/withdrawal allocations.
    address internal optimizer;

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    /// TO OVERRIDE
    /// DEPOSIT
    /// WITHDRAW
    /// CLAIM REWARDS

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE STRATEGY SETTERS
    //////////////////////////////////////////////////////

    /// @notice Set optimizer address
    /// @param _optimizer Optimizer address
    function setOptimizer(address _optimizer) external onlyGovernance {
        optimizer = _optimizer;
    }
}